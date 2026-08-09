import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../data/database.dart';
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
  AppState();

  final _library = libraryStore();
  final _pantry = pantryStore();
  final _settingsStore = JsonStore<AppSettings>(
    fileName: 'settings.json',
    decode: AppSettings.fromJson,
    encode: (s) => s.toJson(),
  );

  LibraryDatabase library = LibraryDatabase();
  PantryDatabase pantry = PantryDatabase();
  AppSettings settings = AppSettings();

  bool loaded = false;

  Timer? _saveLibrary;
  Timer? _savePantry;
  Timer? _saveSettings;

  // ── Loading ─────────────────────────────────────────────────────────────

  Future<void> load() async {
    final savedLibrary = await _library.load();
    final savedPantry = await _pantry.load();
    settings = await _settingsStore.load() ?? AppSettings();

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

    loaded = true;
    notifyListeners();
  }

  // ── Saving ──────────────────────────────────────────────────────────────

  void _touchLibrary() {
    notifyListeners();
    _saveLibrary?.cancel();
    _saveLibrary = Timer(const Duration(milliseconds: 350), _flushLibrary);
  }

  void _touchPantry() {
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
  int get openGroceryCount =>
      library.groceries.where((g) => !g.checked).length;

  List<MealType> get mealTypes =>
      [...library.mealTypes]..sort((a, b) => a.order.compareTo(b.order));

  List<Aisle> get aisles =>
      [...library.aisles]..sort((a, b) => a.order.compareTo(b.order));

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
    _touchLibrary();
  }

  void deleteRecipe(String id) {
    library.recipes.removeWhere((r) => r.id == id);
    library.plan.removeWhere((p) => p.recipeId == id);
    _touchLibrary();
  }

  void setRecipePhoto(String recipeId, String path) {
    recipe(recipeId)?.photoPath = path;
    _touchLibrary();
  }

  void markCooked(String recipeId) {
    final r = recipe(recipeId);
    if (r == null) return;
    r.timesCooked += 1;
    _touchLibrary();
  }

  MealType addMealType(String name) {
    final t = MealType(
      id: newId(),
      name: name,
      order: library.mealTypes.length,
    );
    library.mealTypes.add(t);
    _touchLibrary();
    return t;
  }

  void addTagToRecipe(String recipeId, String tag) {
    final r = recipe(recipeId);
    if (r == null || r.tags.contains(tag)) return;
    r.tags.add(tag);
    _touchLibrary();
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
    _touchPantry();
    return item;
  }

  void movePantryItem(String id, PantryGroup group) {
    final item = pantryItem(id);
    if (item == null || item.group == group) return;
    item.group = group;
    _touchPantry();
  }

  void savePantryItem(PantryItem edited) {
    final i = pantry.items.indexWhere((p) => p.id == edited.id);
    if (i == -1) {
      pantry.items.add(edited);
    } else {
      pantry.items[i] = edited;
    }
    _touchPantry();
  }

  void deletePantryItem(String id) {
    pantry.items.removeWhere((p) => p.id == id);
    // Lines pointing at it become recipe-only rather than dangling.
    for (final r in library.recipes) {
      for (final ing in r.ingredients) {
        if (ing.pantryItemId == id) ing.pantryItemId = null;
      }
    }
    _touchPantry();
    _touchLibrary();
  }

  void addAlias(String itemId, String alias) {
    final item = pantryItem(itemId);
    final a = alias.trim();
    if (item == null || a.isEmpty || item.matchesName(a)) return;
    item.aliases.add(a);
    _touchPantry();
  }

  void removeAlias(String itemId, String alias) {
    pantryItem(itemId)?.aliases.remove(alias);
    _touchPantry();
  }

  void setAssumeStaples(bool value) {
    pantry.assumeStaples = value;
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
        final result =
            totals.lines.where((l) => l.ingredient.id == line.id).firstOrNull;
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
      final a = library.aisles.where((x) => x.id == previous.aisleId).firstOrNull;
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
      _touchLibrary();
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
    _touchLibrary();
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
    _touchLibrary();
  }

  void moveGrocery(String id, String aisleId) {
    final g = library.groceries.where((x) => x.id == id).firstOrNull;
    if (g == null || g.aisleId == aisleId) return;
    g.aisleId = aisleId;
    _touchLibrary();
  }

  void renameGrocery(String id, String name) {
    final g = library.groceries.where((x) => x.id == id).firstOrNull;
    if (g == null || name.trim().isEmpty) return;
    g.name = name.trim();
    _touchLibrary();
  }

  /// The only thing that removes checked items, and it is one action for the
  /// whole list. Anything that maps to a pantry item goes back to the pantry.
  int clearChecked() {
    final checked = library.groceries.where((g) => g.checked).toList();
    for (final g in checked) {
      final known = pantry.items
          .where((p) => p.matchesName(g.name))
          .firstOrNull;
      if (known == null) {
        addPantryItem(g.name);
      }
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
    _touchLibrary();
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
    _touchLibrary();
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
      library.plan.add(PlanEntry(
        id: newId(),
        date: dayOnly(date),
        slot: slot,
        recipeId: recipeId,
      ));
    }
    _touchLibrary();
  }

  void clearPlan(DateTime date, MealSlot slot) {
    final d = dayOnly(date);
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
        out.sort((a, b) => engine
            .forRecipe(b.recipe)
            .perServing
            .protein
            .compareTo(engine.forRecipe(a.recipe).perServing.protein));
      case SuggestionSort.fewestCalories:
        out.sort((a, b) => engine
            .forRecipe(a.recipe)
            .perServing
            .calories
            .compareTo(engine.forRecipe(b.recipe).perServing.calories));
      case SuggestionSort.quickest:
        out.sort((a, b) =>
            (a.recipe.totalMinutes ?? 9999).compareTo(b.recipe.totalMinutes ?? 9999));
    }
    return out;
  }

  // ── Settings ────────────────────────────────────────────────────────────

  void setThemeMode(ThemeMode mode) {
    settings.themeMode = mode;
    _touchSettings();
  }

  void setConflictPolicy(ConflictPolicy p) {
    settings.conflictPolicy = p;
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
    final incoming = await _library.importFrom(path);
    var linked = 0;
    for (final r in incoming.recipes) {
      for (final line in r.ingredients) {
        if (line.pantryItemId != null) continue;
        final match =
            pantry.items.where((p) => p.matchesName(line.name)).firstOrNull;
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
    pantry = await _pantry.importFrom(path);
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
