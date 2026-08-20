import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../data/migrations.dart';
import '../domain/sync/merge.dart';
import '../domain/sync/repair.dart';
import '../domain/sync/snapshot.dart';
import '../domain/sync/stamp.dart';
import '../domain/sync/tombstone.dart';
import '../data/models.dart';
import '../data/seed.dart';
import '../data/settings.dart';
import '../domain/macros.dart';
import '../domain/units.dart';

/// The whole app's state: both databases, the per-device settings, and every
/// operation the screens perform on them.
///
/// Every mutation goes through here and is followed by a debounced save, so
/// nothing on screen can drift from what is on disk.
class AppState extends ChangeNotifier {
  /// [directory] is for tests: it puts the three files somewhere temporary, so
  /// two AppStates can be run side by side in one process and reconciled.
  AppState({Directory? directory})
    : _directory = directory,
      _library = libraryStore(directory: directory),
      _pantry = pantryStore(directory: directory),
      _settingsStore = JsonStore<AppSettings>(
        fileName: 'settings.json',
        decode: AppSettings.fromJson,
        encode: (s) => s.toJson(),
        directory: directory,
      );

  /// Set in tests, so photos land beside the temporary databases rather than
  /// in the real app-support directory.
  final Directory? _directory;

  final JsonStore<LibraryDatabase> _library;
  final JsonStore<PantryDatabase> _pantry;
  final JsonStore<AppSettings> _settingsStore;

  LibraryDatabase library = LibraryDatabase();
  PantryDatabase pantry = PantryDatabase();
  AppSettings settings = AppSettings();

  bool loaded = false;

  Timer? _saveLibrary;
  Timer? _savePantry;
  Timer? _saveSettings;

  // ── Loading ─────────────────────────────────────────────────────────────

  Future<void> load() async {
    // Settings first, and deliberately so: every stamp names the device that
    // wrote it, and migrating either database backfills stamps — so this
    // device's identity has to exist before either file is touched.
    settings = await _settingsStore.load(_migrationContext()) ?? AppSettings();
    if (settings.deviceId == null) {
      settings.deviceId = newId();
      await _flushSettings();
    }

    final savedLibrary = await _library.load(
      _migrationContext(await _library.modifiedAt()),
    );
    final savedPantry = await _pantry.load(
      _migrationContext(await _pantry.modifiedAt()),
    );

    _clock = DeviceClock(deviceId: settings.deviceId!);
    _clock.seed(_highWaterMark(savedLibrary, savedPantry));

    if (savedLibrary == null || savedPantry == null) {
      // First run. There is no onboarding, so the app simply opens with
      // something in it.
      final seeded = Seed.build();
      library = savedLibrary ?? seeded.library;
      pantry = savedPantry ?? seeded.pantry;
      _flushLibrary();
      _flushPantry();
    } else {
      library = savedLibrary;
      pantry = savedPantry;
    }

    await _backfillPhotoHashes();

    loaded = true;
    notifyListeners();
  }

  /// Hashes photographs that were adopted before photos carried a hash.
  ///
  /// Photos travel between devices by content hash, never by path — the paths
  /// differ by construction between a Windows install and an Android one. A
  /// recipe with a photo but no hash is therefore invisible to the transfer:
  /// it can neither be advertised nor asked for. Nothing stamps the recipe,
  /// because filling in a derived value is not an edit and must not win a
  /// conflict against the other device's genuine one.
  Future<void> _backfillPhotoHashes() async {
    var filled = 0;
    for (final r in library.recipes) {
      final path = r.photoPath;
      if (path == null || r.photoHash != null) continue;
      final file = File(path);
      if (!await file.exists()) continue;
      r.photoHash = sha256.convert(await file.readAsBytes()).toString();
      filled++;
    }
    if (filled > 0) await _flushLibrary();
  }

  /// What a migration needs to backfill: who we are, and when the file it is
  /// reading was last written.
  MigrationContext _migrationContext([DateTime? fileModifiedAt]) =>
      MigrationContext(
        deviceId: settings.deviceId ?? '',
        now: DateTime.now().toUtc(),
        fileModifiedAt: fileModifiedAt,
      );

  /// The highest stamp anywhere on disk.
  ///
  /// The clock is primed with this so a restored backup, or a system clock
  /// that moved backwards between runs, cannot issue stamps below ones already
  /// written — records stamped in that window could never win again.
  Stamp _highWaterMark(LibraryDatabase? l, PantryDatabase? p) {
    var top = Stamp.epoch;
    void consider(Stamped e) => top = Stamp.max(top, e.stamp);
    l?.recipes.forEach(consider);
    l?.mealTypes.forEach(consider);
    l?.aisles.forEach(consider);
    l?.groceries.forEach(consider);
    l?.plan.forEach(consider);
    p?.items.forEach(consider);
    for (final t in [...?l?.tombstones, ...?p?.tombstones]) {
      top = Stamp.max(top, t.stamp);
    }
    return top;
  }

  /// Issues this device's stamps. Every mutation goes through it.
  DeviceClock _clock = DeviceClock(deviceId: '');

  void _stampAll(Object? changed, Iterable<Stamped>? alsoChanged) {
    if (changed is Stamped) changed.stamp = _clock.next();
    if (changed is Iterable<Stamped>) {
      for (final e in changed) {
        e.stamp = _clock.next();
      }
    }
    for (final e in alsoChanged ?? const <Stamped>[]) {
      e.stamp = _clock.next();
    }
  }

  /// Records a deletion so it can travel.
  ///
  /// A record simply missing on one side is indistinguishable from one the
  /// other side has not seen yet, so without this every delete would be undone
  /// by the next exchange.
  void _bury(EntityKind kind, String id) {
    final grave = Tombstone(kind: kind, id: id, stamp: _clock.next());
    (kind.isPantry ? pantry.tombstones : library.tombstones).add(grave);
  }

  // ── Saving ──────────────────────────────────────────────────────────────

  /// Stamps what changed and schedules the library save.
  ///
  /// Naming the changed record is the whole point: a stamp is what lets the
  /// other device tell this edit from its own copy. A mutation that forgets to
  /// name its record still saves, but it will silently lose every conflict.
  void _touchLibrary([Object? changed, Iterable<Stamped>? alsoChanged]) {
    _stampAll(changed, alsoChanged);
    notifyListeners();
    _saveLibrary?.cancel();
    _saveLibrary = Timer(const Duration(milliseconds: 350), _flushLibrary);
  }

  /// Stamps what changed and schedules the pantry save. See [_touchLibrary].
  void _touchPantry([Object? changed, Iterable<Stamped>? alsoChanged]) {
    _stampAll(changed, alsoChanged);
    notifyListeners();
    _savePantry?.cancel();
    _savePantry = Timer(const Duration(milliseconds: 350), _flushPantry);
  }

  void _touchSettings() {
    notifyListeners();
    _saveSettings?.cancel();
    _saveSettings = Timer(const Duration(milliseconds: 350), _flushSettings);
  }

  Future<void> _flushLibrary() => _library.save(library);
  Future<void> _flushPantry() => _pantry.save(pantry);
  Future<void> _flushSettings() => _settingsStore.save(settings);

  /// Writes anything still pending. Called before the window closes.
  Future<void> flush() async {
    _saveLibrary?.cancel();
    _savePantry?.cancel();
    _saveSettings?.cancel();
    await Future.wait([_flushLibrary(), _flushPantry(), _flushSettings()]);
  }

  @override
  void dispose() {
    _saveLibrary?.cancel();
    _savePantry?.cancel();
    _saveSettings?.cancel();
    super.dispose();
  }

  // ── Derived helpers ─────────────────────────────────────────────────────

  MacroEngine get macros => MacroEngine(pantry.items);

  PantryCoverage get coverage => PantryCoverage(
    pantry: pantry.items,
    groceries: library.groceries,
    assumeStaples: pantry.assumeStaples,
  );

  /// The count in the sidebar and the phone's tab badge — unchecked only, and
  /// it matches the list exactly.
  int get openGroceryCount => library.groceries.where((g) => !g.checked).length;

  List<MealType> get mealTypes => [...library.mealTypes]..sort(byOrderThenId);

  List<Aisle> get aisles => [...library.aisles]..sort(byOrderThenId);

  MealType? mealType(String id) =>
      library.mealTypes.where((m) => m.id == id).firstOrNull;

  Recipe? recipe(String id) =>
      library.recipes.where((r) => r.id == id).firstOrNull;

  PantryItem? pantryItem(String id) =>
      pantry.items.where((p) => p.id == id).firstOrNull;

  /// Every tag the user has used, in the order they first appear.
  List<String> get allTags {
    final seen = <String>[];
    for (final r in library.recipes) {
      for (final t in r.tags) {
        if (!seen.contains(t)) seen.add(t);
      }
    }
    return seen;
  }

  int recipeCountFor(String? mealTypeId) => mealTypeId == null
      ? library.recipes.length
      : library.recipes.where((r) => r.mealTypeId == mealTypeId).length;

  /// Items with no macros yet — the footer counts these with one Review.
  List<PantryItem> get itemsNeedingMacros =>
      pantry.items.where((p) => !p.hasMacros).toList();

  // ── Recipes ─────────────────────────────────────────────────────────────

  void saveRecipe(Recipe edited) {
    final i = library.recipes.indexWhere((r) => r.id == edited.id);
    if (i == -1) {
      library.recipes.add(edited);
    } else {
      library.recipes[i] = edited;
    }
    _touchLibrary(edited);
  }

  void deleteRecipe(String id) {
    // The plan entries go with it, and each leaves its own record — otherwise
    // a device that still has the recipe would put them straight back.
    for (final entry in library.plan.where((p) => p.recipeId == id).toList()) {
      _bury(EntityKind.planEntry, entry.id);
    }
    library.recipes.removeWhere((r) => r.id == id);
    library.plan.removeWhere((p) => p.recipeId == id);
    _bury(EntityKind.recipe, id);
    _touchLibrary();
  }

  void setRecipePhoto(String recipeId, String path) {
    final r = recipe(recipeId);
    r?.photoPath = path;
    _touchLibrary(r);
  }

  /// Takes a copy of [sourcePath] into the app's own storage and points the
  /// recipe at that.
  ///
  /// Photographs are supplied by the user and stored with the library, so the
  /// app must not depend on wherever the file came from: a desktop drop can be
  /// from a folder that later moves, and Android hands back a path inside a
  /// cache directory that the system is free to clear.
  Future<void> adoptRecipePhoto(String recipeId, String sourcePath) async {
    final r = recipe(recipeId);
    if (r == null) return;

    final dir = await _photoDir();

    final dot = sourcePath.lastIndexOf('.');
    final ext = dot == -1 ? '.jpg' : sourcePath.substring(dot).toLowerCase();
    // The name carries a stamp so replacing a photo does not land on the old
    // file while Flutter still has it in its image cache.
    final name = '$recipeId-${DateTime.now().millisecondsSinceEpoch}$ext';
    final target = '${dir.path}${Platform.pathSeparator}$name';

    final previous = r.photoPath;
    final bytes = await File(sourcePath).readAsBytes();
    await File(target).writeAsBytes(bytes, flush: true);

    r.photoPath = target;
    // The hash is what identifies the picture between devices; the path never
    // could, since it is built from this device's own storage directory.
    r.photoHash = sha256.convert(bytes).toString();
    _touchLibrary(r);

    // Drop the file it replaced, now that the new one is safely in place.
    if (previous != null &&
        previous != target &&
        previous.startsWith(dir.path)) {
      try {
        await File(previous).delete();
      } on FileSystemException {
        // A photo that will not delete is not worth failing the change over.
      }
    }
  }

  void markCooked(String recipeId) {
    final r = recipe(recipeId);
    if (r == null) return;
    r.timesCooked += 1;
    _touchLibrary(r);
  }

  MealType addMealType(String name) {
    final t = MealType(
      id: newId(),
      name: name,
      order: library.mealTypes.length,
    );
    library.mealTypes.add(t);
    _touchLibrary(t);
    return t;
  }

  void addTagToRecipe(String recipeId, String tag) {
    final r = recipe(recipeId);
    if (r == null || r.tags.contains(tag)) return;
    r.tags.add(tag);
    _touchLibrary(r);
  }

  // ── Pantry ──────────────────────────────────────────────────────────────

  PantryItem addPantryItem(String name, {PantryGroup? group}) {
    // Anything added lands in Pantry until it is moved.
    final item = PantryItem(
      id: newId(),
      name: name.trim(),
      group: group ?? PantryGroup.pantry,
    );
    pantry.items.add(item);
    _touchPantry(item);
    return item;
  }

  void movePantryItem(String id, PantryGroup group) {
    final item = pantryItem(id);
    if (item == null || item.group == group) return;
    item.group = group;
    _touchPantry(item);
  }

  /// Marks an item as on hand or run out.
  ///
  /// Nothing is thrown away — the macros, the other known names and the group
  /// all stay — so this is reversible and safe to hit by accident, unlike
  /// removing the item.
  void setInStock(String id, bool inStock) {
    final item = pantryItem(id);
    if (item == null || item.inStock == inStock) return;
    item.inStock = inStock;
    _touchPantry(item);
  }

  void savePantryItem(PantryItem edited) {
    final i = pantry.items.indexWhere((p) => p.id == edited.id);
    if (i == -1) {
      pantry.items.add(edited);
    } else {
      pantry.items[i] = edited;
    }
    _touchPantry(edited);
  }

  void deletePantryItem(String id) {
    pantry.items.removeWhere((p) => p.id == id);
    _bury(EntityKind.pantryItem, id);
    _touchPantry();

    // The ingredient lines pointing at it are deliberately left alone.
    //
    // Clearing them here would edit recipe content without stamping it — and
    // stamping is not the answer either, because that would make this device's
    // copy of a dozen unrelated recipes newer than the other device's genuine
    // edits. Unstamped, the two devices hold the same recipe at the same stamp
    // with different content, which is exactly what the merge now stops to ask
    // about: a question about a link the user never touched.
    //
    // Instead the link is derived. `repairCrossReferences` clears any
    // pantryItemId whose item has a tombstone, and it runs on both devices
    // after every merge, so both reach the same answer from the same input. In
    // the meantime a dangling id is harmless: MacroEngine.item returns null for
    // it and PantryCoverage falls back to matching on the name.
    _touchLibrary();
  }

  void addAlias(String itemId, String alias) {
    final item = pantryItem(itemId);
    final a = alias.trim();
    if (item == null || a.isEmpty || item.matchesName(a)) return;
    item.aliases.add(a);
    _touchPantry(item);
  }

  void removeAlias(String itemId, String alias) {
    final item = pantryItem(itemId);
    item?.aliases.remove(alias);
    _touchPantry(item);
  }

  void setAssumeStaples(bool value) {
    pantry.assumeStaples = value;
    // A bare bool has no id to merge on, so it travels as a register.
    pantry.registers['assumeStaples'] = Register(value, _clock.next());
    _touchPantry();
  }

  /// Every recipe drawing on an item, with what each calls it and what it
  /// contributes — so changing one number here is visibly one change
  /// everywhere.
  List<({Recipe recipe, Ingredient line, double calories})> usedIn(
    String itemId,
  ) {
    final engine = macros;
    final out = <({Recipe recipe, Ingredient line, double calories})>[];
    for (final r in library.recipes) {
      for (final line in r.ingredients) {
        if (line.pantryItemId != itemId) continue;
        final totals = engine.forRecipe(r);
        final result = totals.lines
            .where((l) => l.ingredient.id == line.id)
            .firstOrNull;
        out.add((
          recipe: r,
          line: line,
          calories: result?.macros.calories ?? 0,
        ));
      }
    }
    return out;
  }

  /// Recipes that name a brand this item resembles but which keep their own
  /// macros — listed on the item, never linked to it.
  List<({Recipe recipe, Ingredient line})> brandedMentions(String itemId) {
    final item = pantryItem(itemId);
    if (item == null) return const [];
    final out = <({Recipe recipe, Ingredient line})>[];
    for (final r in library.recipes) {
      for (final line in r.ingredients) {
        if (line.pantryItemId == itemId) continue;
        if (!line.isBranded) continue;
        final name = line.name.toLowerCase();
        if (item.allNames.any((n) => name.contains(n.toLowerCase()))) {
          out.add((recipe: r, line: line));
        }
      }
    }
    return out;
  }

  // ── Groceries ───────────────────────────────────────────────────────────

  Aisle _defaultAisleFor(String name) {
    // An item remembers the aisle it was last filed under, so adding it again
    // puts it straight back there.
    final previous = library.groceries
        .where((g) => g.name.trim().toLowerCase() == name.trim().toLowerCase())
        .firstOrNull;
    if (previous != null) {
      final a = library.aisles
          .where((x) => x.id == previous.aisleId)
          .firstOrNull;
      if (a != null) return a;
    }
    return aisles.first;
  }

  /// Adds an item, combining with an existing line rather than repeating it.
  ///
  /// Returns the line it landed on. Never navigates — adding from a recipe or
  /// a pantry item leaves the user where they were.
  GroceryItem addGrocery(
    String name, {
    String quantity = '',
    String source = 'Added by hand',
    String? pantryItemId,
    String? aisleId,
  }) {
    final key = name.trim().toLowerCase();
    final existing = library.groceries
        .where((g) => g.name.trim().toLowerCase() == key && !g.checked)
        .firstOrNull;

    if (existing != null) {
      // Quantities from several recipes combine into one line — but only once
      // per source, so pressing "add the missing items" twice does not keep
      // growing the quantity.
      final alreadyFrom = existing.sources.contains(source);
      if (quantity.isNotEmpty && !alreadyFrom) {
        existing.quantity = existing.quantity.isEmpty
            ? quantity
            : '${existing.quantity} + $quantity';
      }
      if (!alreadyFrom) existing.sources.add(source);
      _touchLibrary(existing);
      return existing;
    }

    final item = GroceryItem(
      id: newId(),
      name: name.trim(),
      aisleId: aisleId ?? _defaultAisleFor(name).id,
      quantity: quantity,
      sources: [source],
      pantryItemId: pantryItemId,
    );
    library.groceries.add(item);
    _touchLibrary(item);
    return item;
  }

  /// Adds every missing ingredient from a recipe. Returns how many lines were
  /// added or combined.
  int addMissingToGroceries(Recipe r) {
    // Only what is not already on the list — re-adding is a no-op, not a
    // duplicate.
    final missing = coverage.summarise(r).toBuy;
    for (final m in missing) {
      final line = m.ingredient;
      final qty = line.quantity == null
          ? line.unit
          : '${formatAmount(line.quantity)} ${line.unit}'.trim();
      addGrocery(
        line.name,
        quantity: qty,
        source: r.title,
        pantryItemId: line.pantryItemId,
      );
    }
    return missing.length;
  }

  void toggleGrocery(String id) {
    final g = library.groceries.where((x) => x.id == id).firstOrNull;
    if (g == null) return;
    g.checked = !g.checked;
    _touchLibrary(g);
  }

  void moveGrocery(String id, String aisleId) {
    final g = library.groceries.where((x) => x.id == id).firstOrNull;
    if (g == null || g.aisleId == aisleId) return;
    g.aisleId = aisleId;
    _touchLibrary(g);
  }

  void renameGrocery(String id, String name) {
    final g = library.groceries.where((x) => x.id == id).firstOrNull;
    if (g == null || name.trim().isEmpty) return;
    g.name = name.trim();
    _touchLibrary(g);
  }

  /// The only thing that removes checked items, and it is one action for the
  /// whole list. Anything that maps to a pantry item goes back to the pantry.
  int clearChecked() {
    final checked = library.groceries.where((g) => g.checked).toList();
    // Restocked items are a real change the other device needs to hear about.
    final restocked = <PantryItem>[];
    for (final g in checked) {
      final known = pantry.items
          .where((p) => p.matchesName(g.name))
          .firstOrNull;
      if (known == null) {
        addPantryItem(g.name);
      } else {
        // Buying it again is what puts a run-out item back in stock.
        known.inStock = true;
        restocked.add(known);
      }
    }
    _touchPantry(restocked);
    for (final g in checked) {
      _bury(EntityKind.grocery, g.id);
    }
    library.groceries.removeWhere((g) => g.checked);
    _touchLibrary();
    return checked.length;
  }

  Aisle addAisle(String name) {
    final a = Aisle(
      id: newId(),
      name: name.trim(),
      order: library.aisles.length,
    );
    library.aisles.add(a);
    _touchLibrary(a);
    return a;
  }

  void reorderAisles(int oldIndex, int newIndex) {
    final list = aisles;
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = list.removeAt(oldIndex);
    list.insert(newIndex, moved);
    for (var i = 0; i < list.length; i++) {
      list[i].order = i;
    }
    // Every aisle whose position moved is a real change the other device has
    // to hear about, so they all restamp — not just the one dragged.
    _touchLibrary(library.aisles);
  }

  // ── Meal plan ───────────────────────────────────────────────────────────

  DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  PlanEntry? planAt(DateTime date, MealSlot slot) {
    final d = dayOnly(date);
    return library.plan
        .where((p) => dayOnly(p.date) == d && p.slot == slot)
        .firstOrNull;
  }

  void setPlan(DateTime date, MealSlot slot, String recipeId) {
    final existing = planAt(date, slot);
    if (existing != null) {
      existing.recipeId = recipeId;
    } else {
      library.plan.add(
        PlanEntry(
          id: newId(),
          date: dayOnly(date),
          slot: slot,
          recipeId: recipeId,
        ),
      );
    }
    _touchLibrary();
  }

  void clearPlan(DateTime date, MealSlot slot) {
    final d = dayOnly(date);
    for (final entry
        in library.plan
            .where((p) => dayOnly(p.date) == d && p.slot == slot)
            .toList()) {
      _bury(EntityKind.planEntry, entry.id);
    }
    library.plan.removeWhere((p) => dayOnly(p.date) == d && p.slot == slot);
    _touchLibrary();
  }

  /// Dragging within the grid moves a meal; dropping onto a filled slot swaps
  /// the two.
  void movePlan(
    DateTime fromDate,
    MealSlot fromSlot,
    DateTime toDate,
    MealSlot toSlot,
  ) {
    final from = planAt(fromDate, fromSlot);
    if (from == null) return;
    final to = planAt(toDate, toSlot);

    if (to == null) {
      from.date = dayOnly(toDate);
      from.slot = toSlot;
    } else {
      final tmp = from.recipeId;
      from.recipeId = to.recipeId;
      to.recipeId = tmp;
    }
    _touchLibrary();
  }

  /// A day's calories and protein, summed from the same calculated macros the
  /// recipe screens show.
  ({double calories, double protein}) dayTotals(DateTime date) {
    final engine = macros;
    var cal = 0.0;
    var protein = 0.0;
    for (final slot in MealSlot.values) {
      final entry = planAt(date, slot);
      if (entry == null) continue;
      final r = recipe(entry.recipeId);
      if (r == null) continue;
      final per = engine.forRecipe(r).perServing;
      cal += per.calories;
      protein += per.protein;
    }
    return (calories: cal, protein: protein);
  }

  /// Every ingredient the week's recipes are short of, counted before the one
  /// action on the meal plan screen is pressed.
  List<CoverageResult> missingForWeek(DateTime weekStart) {
    final cov = coverage;
    final seen = <String>{};
    final out = <CoverageResult>[];
    for (var i = 0; i < 7; i++) {
      final day = dayOnly(weekStart.add(Duration(days: i)));
      for (final slot in MealSlot.values) {
        final entry = planAt(day, slot);
        if (entry == null) continue;
        final r = recipe(entry.recipeId);
        if (r == null) continue;
        // What still has to be bought — the count on the button is what
        // pressing it will actually add.
        for (final m in cov.summarise(r).toBuy) {
          final key = m.ingredient.name.trim().toLowerCase();
          if (seen.add(key)) out.add(m);
        }
      }
    }
    return out;
  }

  int addWeekMissingToGroceries(DateTime weekStart) {
    final missing = missingForWeek(weekStart);
    for (final m in missing) {
      final line = m.ingredient;
      final qty = line.quantity == null
          ? line.unit
          : '${formatAmount(line.quantity)} ${line.unit}'.trim();
      addGrocery(line.name, quantity: qty, source: 'Meal plan');
    }
    return missing.length;
  }

  // ── Suggestions ─────────────────────────────────────────────────────────

  /// The user's own recipes, ranked, with anything missing named.
  ///
  /// Web results sit below these and are marked approximate until saved; the
  /// app is offline by design so that half is only populated once a fetch has
  /// actually happened.
  List<({Recipe recipe, int missing, List<String> missingNames})> suggestions({
    List<String> withIngredients = const [],
    SuggestionSort sort = SuggestionSort.pantryMatch,
  }) {
    final cov = coverage;
    final engine = macros;
    final out = <({Recipe recipe, int missing, List<String> missingNames})>[];

    for (final r in library.recipes) {
      if (withIngredients.isNotEmpty) {
        final names = r.ingredients.map((i) => i.name.toLowerCase()).join(' ');
        final wanted = withIngredients.every(
          (w) => names.contains(w.toLowerCase()),
        );
        if (!wanted) continue;
      }
      final missing = cov.summarise(r).missing;
      out.add((
        recipe: r,
        missing: missing.length,
        missingNames: [for (final m in missing) m.ingredient.name],
      ));
    }

    switch (sort) {
      case SuggestionSort.pantryMatch:
        out.sort((a, b) => a.missing.compareTo(b.missing));
      case SuggestionSort.mostProtein:
        out.sort(
          (a, b) => engine
              .forRecipe(b.recipe)
              .perServing
              .protein
              .compareTo(engine.forRecipe(a.recipe).perServing.protein),
        );
      case SuggestionSort.fewestCalories:
        out.sort(
          (a, b) => engine
              .forRecipe(a.recipe)
              .perServing
              .calories
              .compareTo(engine.forRecipe(b.recipe).perServing.calories),
        );
      case SuggestionSort.quickest:
        out.sort(
          (a, b) => (a.recipe.totalMinutes ?? 9999).compareTo(
            b.recipe.totalMinutes ?? 9999,
          ),
        );
    }
    return out;
  }

  // ── Settings ────────────────────────────────────────────────────────────

  void setThemeMode(ThemeMode mode) {
    settings.themeMode = mode;
    _touchSettings();
  }

  void setPermission(String key, bool granted) {
    final p = settings.permissions.where((x) => x.key == key).firstOrNull;
    if (p == null) return;
    p.granted = granted;
    _touchSettings();
  }

  /// A six-digit pairing code, shown on the device being added to. It expires,
  /// so it is generated fresh each time the dialog opens.
  String newPairingCode() {
    final r = Random.secure();
    return List.generate(6, (_) => r.nextInt(10)).join();
  }

  void unpair(String deviceId) {
    // Unpairing is per device and never deletes anything.
    settings.devices.removeWhere((d) => d.id == deviceId);
    _touchSettings();
  }

  Future<int> librarySize() => _library.sizeInBytes();
  Future<int> pantrySize() => _pantry.sizeInBytes();

  // ── Reconciling with another device ─────────────────────────────────────

  /// Works out what merging [incomingLibrary] and [incomingPantry] into this
  /// device would do. Nothing is written — pass the result to [applyMerge].
  ///
  /// The two databases are merged separately, as they are stored, but they are
  /// applied together: cross-references are repaired across the merged pair
  /// before either file is written.
  ({MergePlan library, MergePlan pantry}) planMerge(
    LibraryDatabase incomingLibrary,
    PantryDatabase incomingPantry, {
    Map<String, Resolution> answers = const {},
  }) {
    return (
      library: mergeDatabase(
        library.toSnapshot(),
        incomingLibrary.toSnapshot(),
        answers: answers,
      ),
      pantry: mergeDatabase(
        pantry.toSnapshot(),
        incomingPantry.toSnapshot(),
        answers: answers,
      ),
    );
  }

  /// Applies a plan, repairs what the merge could not have known, and saves.
  ///
  /// Refuses a plan with unanswered conflicts rather than picking for the user:
  /// the whole point of "ask" is that it is their call.
  Future<RepairReport> applyMerge(
    MergePlan libraryPlan,
    MergePlan pantryPlan, {

    /// Ids the user just chose between, which are re-stamped as this device's
    /// own edit.
    ///
    /// Answering a tie *is* an edit — the user picked this copy, just now — and
    /// stamping it now is what makes their answer newer than either copy that
    /// caused the question. Without it the two devices would still hold the
    /// same tied stamps, and the identical question would come back on every
    /// exchange for ever.
    Set<String> restamp = const {},
  }) async {
    if (!libraryPlan.isComplete || !pantryPlan.isComplete) {
      throw StateError('Answer the conflicts before applying the merge.');
    }

    library = libraryFromSnapshot(libraryPlan.result);
    pantry = pantryFromSnapshot(pantryPlan.result);

    if (restamp.isNotEmpty) {
      for (final e in <Stamped>[
        ...library.recipes,
        ...library.mealTypes,
        ...library.aisles,
        ...library.groceries,
        ...library.plan,
        ...pantry.items,
      ]) {
        if (restamp.contains(e.id)) e.stamp = _clock.next();
      }
    }

    final report = repairCrossReferences(library, pantry, clock: _clock);

    // Undebounced: a merge is not a keystroke, and the next thing that happens
    // is usually the peer being told we are done.
    await Future.wait([_flushLibrary(), _flushPantry()]);
    notifyListeners();
    return report;
  }

  /// Replaces both databases wholesale with another device's, keeping a copy
  /// of what was here first.
  ///
  /// This is how two devices that have never synced are brought to a common
  /// baseline. It is destructive by design — the point is that afterwards both
  /// hold the same records under the same ids — so the outgoing databases are
  /// backed up before anything is overwritten.
  Future<AdoptionResult> adoptFrom({
    required String libraryPath,
    required String pantryPath,
  }) async {
    final replacing = AdoptionResult(
      replacedRecipes: library.recipes.length,
      replacedPantryItems: pantry.items.length,
      backupSuffix: DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first,
    );

    await flush();
    await _library.exportTo(
      await _backupPath('library', replacing.backupSuffix),
    );
    await _pantry.exportTo(await _backupPath('pantry', replacing.backupSuffix));

    library = await _library.importFrom(libraryPath, _migrationContext());
    pantry = await _pantry.importFrom(pantryPath, _migrationContext());

    // The adopted files came from a device with its own id; everything in them
    // keeps the stamps it arrived with, so the two devices now agree on both
    // identity and history.
    _clock.seed(_highWaterMark(library, pantry));
    repairCrossReferences(library, pantry, clock: _clock);
    await Future.wait([_flushLibrary(), _flushPantry()]);

    notifyListeners();
    return replacing;
  }

  Future<String> _backupPath(String name, String suffix) async {
    final f = await (name == 'library' ? _library : _pantry).file();
    return '${f.path}.replaced-$suffix.bak';
  }

  // ── Devices ─────────────────────────────────────────────────────────────

  /// Records a device we have paired with, replacing any earlier record of it.
  void rememberDevice(PairedDevice device) {
    settings.devices.removeWhere((d) => d.id == device.id);
    settings.devices.add(device);
    _touchSettings();
  }

  /// Notes that a session with [peer] finished, and how much it holds.
  ///
  /// The watermarks are what make a second sync with nothing in between a true
  /// no-op: records at or below them are not new, so nothing transfers and —
  /// more importantly — nothing is re-asked. They advance only after the merge
  /// is safely written, so a failure part-way through simply redoes the work.
  void recordSync(
    PairedDevice peer,
    LibraryDatabase theirLibrary,
    PantryDatabase theirPantry,
  ) {
    final now = DateTime.now().toUtc();
    peer
      ..lastSync = now
      ..recipeCount = theirLibrary.recipes.length
      ..pantryCount = theirPantry.items.length
      ..libraryWatermark = _highWaterMark(theirLibrary, null).at
      ..pantryWatermark = _highWaterMark(null, theirPantry).at;
    settings.lastSync = now;
    rememberDevice(peer);
  }

  // ── Photos by content ───────────────────────────────────────────────────

  Future<Directory> _photoDir() async {
    final base = _directory ?? await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}photos');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// A photograph by content hash, or null when this device does not hold it.
  Future<List<int>?> photoBytesByHash(String hash) async {
    for (final r in library.recipes) {
      if (r.photoHash != hash || r.photoPath == null) continue;
      final f = File(r.photoPath!);
      if (await f.exists()) return f.readAsBytes();
    }
    return null;
  }

  /// Hashes named by a recipe whose bytes are not on this device.
  ///
  /// After a merge, a recipe that arrived from the other device names a
  /// picture we have never seen. This is the list to go and fetch.
  Future<List<String>> missingPhotoHashes() async {
    final wanted = <String>{};
    for (final r in library.recipes) {
      final hash = r.photoHash;
      if (hash == null) continue;
      final path = r.photoPath;
      if (path != null && await File(path).exists()) continue;
      wanted.add(hash);
    }
    return wanted.toList();
  }

  /// Stores bytes fetched from a peer and points every recipe expecting that
  /// hash at the local copy.
  Future<void> storePhotoBytes(String hash, List<int> bytes) async {
    // Trust nothing: a peer that hands back bytes which do not hash to what we
    // asked for has either a bug or bad intent, and either way the file is not
    // the one the recipe means.
    if (sha256.convert(bytes).toString() != hash) return;

    final dir = await _photoDir();
    final target = '${dir.path}${Platform.pathSeparator}$hash.jpg';
    await File(target).writeAsBytes(bytes, flush: true);

    var changed = false;
    for (final r in library.recipes) {
      if (r.photoHash != hash) continue;
      r.photoPath = target;
      changed = true;
    }
    // Deliberately unstamped: pointing at a local file is this device catching
    // up, not an edit the other device needs told about.
    if (changed) {
      notifyListeners();
      await _flushLibrary();
    }
  }

  Future<void> exportLibrary(String path) async {
    await flush();
    await _library.exportTo(path);
  }

  Future<void> exportPantry(String path) async {
    await flush();
    await _pantry.exportTo(path);
  }

  /// Replaces the library, matching its ingredient names against the existing
  /// pantry on the way in — the same as a web import.
  Future<int> importLibrary(String path) async {
    final incoming = await _library.importFrom(path, _migrationContext());
    var linked = 0;
    for (final r in incoming.recipes) {
      for (final line in r.ingredients) {
        if (line.pantryItemId != null) continue;
        final match = pantry.items
            .where((p) => p.matchesName(line.name))
            .firstOrNull;
        if (match != null) {
          line.pantryItemId = match.id;
          linked++;
        }
      }
    }
    library = incoming;
    _touchLibrary();
    return linked;
  }

  Future<void> importPantry(String path) async {
    pantry = await _pantry.importFrom(path, _migrationContext());
    _touchPantry();
  }
}

enum SuggestionSort {
  pantryMatch('Pantry match'),
  mostProtein('Most protein'),
  fewestCalories('Fewest calories'),
  quickest('Quickest');

  const SuggestionSort(this.label);
  final String label;
}

/// What adopting another device's databases replaced.
class AdoptionResult {
  const AdoptionResult({
    required this.replacedRecipes,
    required this.replacedPantryItems,
    required this.backupSuffix,
  });

  final int replacedRecipes;
  final int replacedPantryItems;

  /// Identifies the `.replaced-<when>.bak` files written before the overwrite.
  final String backupSuffix;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
