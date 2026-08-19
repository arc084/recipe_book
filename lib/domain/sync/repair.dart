import '../../data/database.dart';
import '../../data/models.dart';
import 'stamp.dart';
import 'tombstone.dart';

/// What a repair pass had to change, so a sync can report it rather than
/// silently rewriting the user's data.
class RepairReport {
  int droppedPlanEntries = 0;
  int unlinkedIngredients = 0;
  int unlinkedGroceries = 0;
  int refiledGroceries = 0;
  int recategorisedRecipes = 0;
  int relinkedByName = 0;

  bool get isEmpty =>
      droppedPlanEntries == 0 &&
      unlinkedIngredients == 0 &&
      unlinkedGroceries == 0 &&
      refiledGroceries == 0 &&
      recategorisedRecipes == 0 &&
      relinkedByName == 0;
}

/// Repairs references that the merge could not have known about on its own.
///
/// The two databases stay separate for storage, backup and restore — but a
/// sync session merges both and then repairs across the merged *pair*, once,
/// before either is written. Splitting this would leave a window where a
/// recipe points at a pantry item that no longer exists.
///
/// Every rule here mirrors behaviour the app already has when the same thing
/// happens locally.
RepairReport repairCrossReferences(
  LibraryDatabase library,
  PantryDatabase pantry, {
  required DeviceClock clock,
}) {
  final report = RepairReport();

  final recipeIds = {for (final r in library.recipes) r.id};
  final pantryIds = {for (final p in pantry.items) p.id};
  final pantryGraves = {
    for (final t in pantry.tombstones)
      if (t.kind == EntityKind.pantryItem) t.id,
  };

  // ── Plan entries pointing at a recipe that is gone ────────────────────────
  // Mirrors deleteRecipe's own cascade.
  final orphanedPlans = library.plan
      .where((p) => !recipeIds.contains(p.recipeId))
      .toList();
  for (final entry in orphanedPlans) {
    library.plan.remove(entry);
    library.tombstones.add(
      Tombstone(kind: EntityKind.planEntry, id: entry.id, stamp: clock.next()),
    );
    report.droppedPlanEntries++;
  }

  // ── Ingredient links ──────────────────────────────────────────────────────
  // Only a *known* deletion clears a link. An id we simply have not seen —
  // because the peer's pantry holds records we have not merged, or the two
  // databases were restored from different backups — is left alone: both
  // readers already degrade gracefully, and clearing on unknown ids would wipe
  // every link after a single asymmetric restore.
  for (final recipe in library.recipes) {
    for (final line in recipe.ingredients) {
      final linked = line.pantryItemId;
      if (linked == null || pantryIds.contains(linked)) continue;
      if (pantryGraves.contains(linked)) {
        line.pantryItemId = null;
        report.unlinkedIngredients++;
      }
    }
  }

  for (final g in library.groceries) {
    final linked = g.pantryItemId;
    if (linked == null || pantryIds.contains(linked)) continue;
    if (pantryGraves.contains(linked)) {
      g.pantryItemId = null;
      report.unlinkedGroceries++;
    }
  }

  // ── Aisles and meal types ─────────────────────────────────────────────────
  // A merge that removed every aisle would otherwise crash the next grocery
  // add: the app's own fallback ends in `aisles.first`.
  if (library.aisles.isEmpty) {
    library.aisles.add(
      Aisle(id: newId(), name: 'Other', order: 0)..stamp = clock.next(),
    );
  }
  if (library.mealTypes.isEmpty) {
    library.mealTypes.add(
      MealType(id: newId(), name: 'Uncategorised', order: 0)
        ..stamp = clock.next(),
    );
  }

  final firstAisle = _byOrder(library.aisles).first;
  final aisleIds = {for (final a in library.aisles) a.id};
  for (final g in library.groceries) {
    if (aisleIds.contains(g.aisleId)) continue;
    g.aisleId = firstAisle.id;
    report.refiledGroceries++;
  }

  final firstType = _byOrder(library.mealTypes).first;
  final typeIds = {for (final m in library.mealTypes) m.id};
  for (final r in library.recipes) {
    if (typeIds.contains(r.mealTypeId)) continue;
    r.mealTypeId = firstType.id;
    report.recategorisedRecipes++;
  }

  // ── Re-link by name ───────────────────────────────────────────────────────
  report.relinkedByName = relinkIngredientsToPantry(library, pantry.items);

  return report;
}

/// Links unlinked ingredient lines to a pantry item that answers to their name.
///
/// This is the same pass an import already runs, extracted so both callers use
/// one behaviour: after a merge, a recipe that arrived from the other device
/// naming "parmesan" should draw on this device's Parmesan without being asked.
int relinkIngredientsToPantry(LibraryDatabase library, List<PantryItem> items) {
  var linked = 0;
  for (final recipe in library.recipes) {
    for (final line in recipe.ingredients) {
      if (line.pantryItemId != null) continue;
      // A branded line keeps its own ingredient and its own macros, and is
      // never linked to the pantry item it happens to resemble.
      if (line.isBranded) continue;
      for (final item in items) {
        if (!item.matchesName(line.name)) continue;
        line.pantryItemId = item.id;
        linked++;
        break;
      }
    }
  }
  return linked;
}

/// The one total order both devices compute identically.
///
/// Two devices that independently reorder a list produce duplicate `order`
/// values once merged. Renormalising them would mean either restamping the
/// records — an endless ping-pong of "newer" reorderings — or leaving the
/// stored bytes divergent. Sorting on `(order, id)` instead needs no writes at
/// all, and both sides derive the same sequence from the same data.
List<T> _byOrder<T>(List<T> items) {
  final sorted = [...items];
  sorted.sort((a, b) {
    final ao = (a as dynamic).order as int;
    final bo = (b as dynamic).order as int;
    final byOrder = ao.compareTo(bo);
    if (byOrder != 0) return byOrder;
    return ((a as dynamic).id as String).compareTo((b as dynamic).id as String);
  });
  return sorted;
}
