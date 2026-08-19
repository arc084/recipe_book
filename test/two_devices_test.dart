import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/data/settings.dart';
import 'package:recipe_book/domain/sync/merge.dart';
import 'package:recipe_book/state/app_state.dart';

/// Two real `AppState`s over their own directories, edited independently and
/// then reconciled — the closest this pass gets to an end-to-end sync, and the
/// test that would catch a mutation that forgot to stamp itself.
void main() {
  late Directory dirA;
  late Directory dirB;
  late AppState a;
  late AppState b;

  /// Gives both devices the same starting library and pantry, the way the
  /// baseline adoption does before any real sync.
  Future<void> pair() async {
    final libPath = '${dirA.path}${Platform.pathSeparator}lib-export.json';
    final panPath = '${dirA.path}${Platform.pathSeparator}pan-export.json';
    await a.exportLibrary(libPath);
    await a.exportPantry(panPath);
    await b.adoptFrom(libraryPath: libPath, pantryPath: panPath);
  }

  /// Merges [from] into [into] and applies the result.
  Future<void> sync(AppState into, AppState from) async {
    final plan = into.planMerge(from.library, from.pantry);
    await into.applyMerge(plan.library, plan.pantry);
  }

  setUp(() async {
    dirA = Directory.systemTemp.createTempSync('rb_a');
    dirB = Directory.systemTemp.createTempSync('rb_b');
    a = AppState(directory: dirA);
    b = AppState(directory: dirB);
    await a.load();
    await b.load();
    a.settings.conflictPolicy = ConflictPolicy.newestWins;
    b.settings.conflictPolicy = ConflictPolicy.newestWins;
    await pair();
  });

  tearDown(() async {
    // Saves are debounced, so a pending timer would fire into a directory that
    // no longer exists. Flushing cancels the timers and writes now.
    await a.flush();
    await b.flush();
    dirA.deleteSync(recursive: true);
    dirB.deleteSync(recursive: true);
  });

  test('adoption gives both devices the same records under the same ids', () {
    // This is the whole point of the baseline: without it the two seeded
    // corpora share titles but not ids, and a merge would duplicate every one.
    expect(
      b.library.recipes.map((r) => r.id).toSet(),
      a.library.recipes.map((r) => r.id).toSet(),
    );
    expect(
      b.pantry.items.map((p) => p.id).toSet(),
      a.pantry.items.map((p) => p.id).toSet(),
    );
    expect(b.settings.deviceId, isNot(a.settings.deviceId));
  });

  test('adoption keeps a copy of what it replaced', () {
    final backups = dirB
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('.replaced-'))
        .toList();
    expect(backups, hasLength(2));
  });

  test('a recipe added on one device arrives on the other', () async {
    final added = Recipe(
      id: newId(),
      title: 'Miso Soup',
      mealTypeId: a.mealTypes.first.id,
    );
    a.saveRecipe(added);

    await sync(b, a);

    expect(b.recipe(added.id)?.title, 'Miso Soup');
  });

  test('a deletion travels instead of being undone', () async {
    // Without a tombstone the record is merely missing on one side, which is
    // indistinguishable from news the other side has not had yet.
    final victim = a.library.recipes.first.id;
    a.deleteRecipe(victim);

    await sync(b, a);

    expect(b.recipe(victim), isNull);
    expect(b.library.tombstones.map((t) => t.id), contains(victim));
  });

  test('a deleted recipe does not come back on the next exchange', () async {
    final victim = a.library.recipes.first.id;
    a.deleteRecipe(victim);
    await sync(b, a);
    // B now knows. Syncing the other way must not resurrect it from A.
    await sync(a, b);
    await sync(b, a);

    expect(a.recipe(victim), isNull);
    expect(b.recipe(victim), isNull);
  });

  test(
    'the newer edit wins when both devices change the same recipe',
    () async {
      final id = a.library.recipes.first.id;

      a.recipe(id)!.notes = 'from A';
      a.saveRecipe(a.recipe(id)!);

      await Future<void>.delayed(const Duration(milliseconds: 5));

      b.recipe(id)!.notes = 'from B';
      b.saveRecipe(b.recipe(id)!);

      await sync(a, b);
      expect(a.recipe(id)!.notes, 'from B');
    },
  );

  test('editing different recipes on each device keeps both edits', () async {
    final ids = a.library.recipes.map((r) => r.id).toList();
    a.recipe(ids[0])!.notes = 'A note';
    a.saveRecipe(a.recipe(ids[0])!);
    b.recipe(ids[1])!.notes = 'B note';
    b.saveRecipe(b.recipe(ids[1])!);

    await sync(a, b);

    expect(a.recipe(ids[0])!.notes, 'A note');
    expect(a.recipe(ids[1])!.notes, 'B note');
  });

  test('running out of something on one device shows on the other', () async {
    final item = a.pantry.items.firstWhere((p) => p.inStock);
    a.setInStock(item.id, false);

    await sync(b, a);

    expect(b.pantryItem(item.id)!.inStock, isFalse);
    // And the macros came through untouched — this is the whole reason run-out
    // is a flag rather than a delete.
    expect(b.pantryItem(item.id)!.calories, item.calories);
  });

  test('assumeStaples travels as a register', () async {
    a.setAssumeStaples(false);
    await sync(b, a);
    expect(b.pantry.staplesAssumed, isFalse);
  });

  test(
    'deleting a pantry item unlinks it everywhere, on both devices',
    () async {
      final linked = a.library.recipes
          .expand((r) => r.ingredients)
          .firstWhere((i) => i.pantryItemId != null);
      final itemId = linked.pantryItemId!;
      // Take its aliases out of the way, or the repair pass will helpfully
      // re-link the line by name — which is correct behaviour, but not what this
      // test is about.
      final item = a.pantryItem(itemId)!;
      for (final alias in [...item.aliases]) {
        a.removeAlias(itemId, alias);
      }
      item.name = 'zzz-not-a-real-name';
      a.savePantryItem(item);
      a.deletePantryItem(itemId);

      await sync(b, a);

      expect(b.pantryItem(itemId), isNull);
      final line = b.library.recipes
          .expand((r) => r.ingredients)
          .firstWhere((i) => i.id == linked.id);
      expect(line.pantryItemId, isNull);
    },
  );

  test('syncing twice transfers nothing the second time', () async {
    a.saveRecipe(
      Recipe(id: newId(), title: 'Congee', mealTypeId: a.mealTypes.first.id),
    );
    await sync(b, a);

    final second = b.planMerge(a.library, a.pantry);
    expect(second.library.stats.isEmpty, isTrue);
    expect(second.pantry.stats.isEmpty, isTrue);
  });

  test('both devices end up holding the same thing', () async {
    a.saveRecipe(
      Recipe(id: newId(), title: 'Only on A', mealTypeId: a.mealTypes.first.id),
    );
    b.saveRecipe(
      Recipe(id: newId(), title: 'Only on B', mealTypeId: b.mealTypes.first.id),
    );
    a.deleteRecipe(a.library.recipes.first.id);

    await sync(a, b);
    await sync(b, a);

    expect(
      a.library.recipes.map((r) => r.id).toSet(),
      b.library.recipes.map((r) => r.id).toSet(),
    );
  });

  test('what was merged survives a restart', () async {
    final added = Recipe(
      id: newId(),
      title: 'Persisted',
      mealTypeId: a.mealTypes.first.id,
    );
    a.saveRecipe(added);
    await sync(b, a);

    final reopened = AppState(directory: dirB);
    await reopened.load();
    expect(reopened.recipe(added.id)?.title, 'Persisted');
  });

  test('ask refuses to apply until the conflict is answered', () async {
    a.settings.conflictPolicy = ConflictPolicy.ask;
    final id = a.library.recipes.first.id;
    a.recipe(id)!.notes = 'A';
    a.saveRecipe(a.recipe(id)!);
    b.recipe(id)!.notes = 'B';
    b.saveRecipe(b.recipe(id)!);

    final plan = a.planMerge(b.library, b.pantry);
    expect(plan.library.unresolved, hasLength(1));
    expect(
      () => a.applyMerge(plan.library, plan.pantry),
      throwsA(isA<StateError>()),
    );

    // Answering it and replaying settles the merge.
    final answered = a.planMerge(
      b.library,
      b.pantry,
      answers: {id: Resolution.takeRemote},
    );
    await a.applyMerge(answered.library, answered.pantry);
    expect(a.recipe(id)!.notes, 'B');
  });
}
