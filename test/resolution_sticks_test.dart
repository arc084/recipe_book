import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/domain/sync/merge.dart';
import 'package:recipe_book/domain/sync/stamp.dart';
import 'package:recipe_book/state/app_state.dart';

/// Answering a tie has to *stick*. If the chosen copy keeps its original
/// stamp, the two devices still hold the same tied stamps and the identical
/// question comes back on every exchange for ever.
void main() {
  late Directory dirA;
  late Directory dirB;
  late AppState a;
  late AppState b;

  setUp(() async {
    dirA = await Directory.systemTemp.createTemp('rb-a');
    dirB = await Directory.systemTemp.createTemp('rb-b');
    a = AppState(directory: dirA);
    b = AppState(directory: dirB);
    await a.load();
    await b.load();
  });

  tearDown(() async {
    await dirA.delete(recursive: true);
    await dirB.delete(recursive: true);
  });

  test('an answered tie is restamped, so it is not asked again', () async {
    final id = a.library.recipes.first.id;
    final tie = Stamp(DateTime.utc(2026, 8, 19, 12), 'both');
    a.recipe(id)!
      ..notes = 'the laptop version'
      ..stamp = tie;
    b.recipe(id)!
      ..notes = 'the phone version'
      ..stamp = tie;

    // The tie is raised.
    final first = a.planMerge(b.library, b.pantry);
    expect(first.library.unresolved, hasLength(1));

    // The user keeps the laptop's copy, and it is restamped as their edit.
    final answered = a.planMerge(
      b.library,
      b.pantry,
      answers: {id: Resolution.takeLocal},
    );
    await a.applyMerge(answered.library, answered.pantry, restamp: {id});

    expect(a.recipe(id)!.notes, 'the laptop version');
    expect(
      a.recipe(id)!.stamp > tie,
      isTrue,
      reason: 'the answer must outrank the copies that caused the question',
    );

    // The peer now simply takes it: newer wins, nothing to ask.
    final onB = b.planMerge(a.library, a.pantry);
    expect(onB.library.unresolved, isEmpty);
    await b.applyMerge(onB.library, onB.pantry);
    expect(b.recipe(id)!.notes, 'the laptop version');

    // And asking again settles nothing new — the question is gone for good.
    expect(a.planMerge(b.library, b.pantry).library.unresolved, isEmpty);
  });

  test(
    'without restamping the same question returns — the regression',
    () async {
      final id = a.library.recipes.first.id;
      final tie = Stamp(DateTime.utc(2026, 8, 19, 12), 'both');
      a.recipe(id)!
        ..notes = 'A'
        ..stamp = tie;
      b.recipe(id)!
        ..notes = 'B'
        ..stamp = tie;

      // Apply the answer *without* restamping, the way it used to work.
      final answered = a.planMerge(
        b.library,
        b.pantry,
        answers: {id: Resolution.takeLocal},
      );
      await a.applyMerge(answered.library, answered.pantry);

      // The stamps still tie and the content still differs, so it comes back.
      expect(
        a.planMerge(b.library, b.pantry).library.unresolved,
        hasLength(1),
        reason: 'this is exactly why the answer has to be stamped',
      );
    },
  );
}
