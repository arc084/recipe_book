import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/seed.dart';
import 'package:recipe_book/domain/sync/canonical_content.dart';
import 'package:recipe_book/domain/sync/merge.dart';
import 'package:recipe_book/domain/sync/snapshot.dart';
import 'package:recipe_book/domain/sync/stamp.dart';
import 'package:recipe_book/domain/sync/tombstone.dart';

/// The property that was broken in four places at once: every tie-break
/// reached for `mine`, and `mine`/`theirs` are swapped between the two
/// devices, so each reached the opposite answer and the pair never converged.
void main() {
  StampedRecord rec(String id, {required Stamp stamp, required String name}) =>
      StampedRecord(
        kind: EntityKind.pantryItem,
        id: id,
        json: {'id': id, 'name': name},
        stamp: stamp,
        label: name,
      );

  DbSnapshot snap(List<StampedRecord> records) => DbSnapshot(
    entities: {for (final r in records) r.id: r},
    tombstones: const {},
    registers: const {},
  );

  group('the tie-break is symmetric', () {
    final tie = Stamp(DateTime.utc(2026, 1, 1), 'A');

    test('a tie is raised as a question on both devices, not swallowed', () {
      final a = snap([rec('x', stamp: tie, name: 'mine')]);
      final b = snap([rec('x', stamp: tie, name: 'theirs')]);

      // Before the fix both sides silently kept their own copy: no conflict,
      // no convergence, and neither user ever told.
      expect(mergeDatabase(a, b).unresolved, hasLength(1));
      expect(mergeDatabase(b, a).unresolved, hasLength(1));
    });

    test('answering the same way on both devices converges', () {
      final a = snap([rec('x', stamp: tie, name: 'mine')]);
      final b = snap([rec('x', stamp: tie, name: 'theirs')]);

      // The user picks one copy; the other device is told the same thing.
      final onA = mergeDatabase(a, b, answers: {'x': Resolution.takeLocal});
      final onB = mergeDatabase(b, a, answers: {'x': Resolution.takeRemote});

      expect(
        onA.result.entities['x']!.json['name'],
        onB.result.entities['x']!.json['name'],
      );
    });

    test('an unanswered tie leaves both devices exactly as they were', () {
      final a = snap([rec('x', stamp: tie, name: 'mine')]);
      final b = snap([rec('x', stamp: tie, name: 'theirs')]);

      expect(mergeDatabase(a, b).result.entities['x']!.json['name'], 'mine');
      expect(mergeDatabase(b, a).result.entities['x']!.json['name'], 'theirs');
    });

    test('content ordering is symmetric', () {
      // The tie-break of last resort has to give opposite answers to the two
      // devices, or they never agree.
      const kind = EntityKind.pantryItem;
      final x = {'id': 'x', 'name': 'aaa'};
      final y = {'id': 'x', 'name': 'bbb'};
      expect(compareContent(kind, x, y), lessThan(0));
      expect(compareContent(kind, y, x), greaterThan(0));
      expect(compareContent(kind, x, x), 0);
    });
  });

  group('the shipped seed', () {
    test('two fresh installs merge to nothing at all', () {
      // Deterministic ids and one shared seed stamp: the two sides are
      // identical, so there is nothing to transfer and nothing to ask.
      final a = Seed.build().library.toSnapshot();
      final b = Seed.build().library.toSnapshot();

      final plan = mergeDatabase(a, b);
      expect(plan.unresolved, isEmpty);
      expect(plan.stats.totalAdded, 0);
      expect(plan.stats.totalUpdated, 0);
    });

    test('seeded records are stamped, not left at the epoch', () {
      // At the epoch every seeded record ties with its counterpart, so the
      // first seed change shipped in an update would have become a pile of
      // questions about recipes the user never touched.
      final seeded = Seed.build().library.recipes.first;
      expect(seeded.stamp.at.isAfter(Stamp.epoch.at), isTrue);
      // No device id: a seeded record must still lose to any genuine edit.
      expect(seeded.stamp.by, isEmpty);
    });

    test('a real edit beats a seeded record', () {
      final seeded = Seed.build().library.recipes.first;
      final edited = Stamp(DateTime.utc(2030), 'some-device');
      expect(edited > seeded.stamp, isTrue);
    });
  });
}
