import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/domain/sync/merge.dart';
import 'package:recipe_book/domain/sync/stamp.dart';
import 'package:recipe_book/domain/sync/tombstone.dart';

DateTime t(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
Stamp s(int ms, String by) => Stamp(t(ms), by);

/// A pantry item, the simplest record with a name.
StampedRecord item(
  String id, {
  required int at,
  String by = 'A',
  String? name,
}) => StampedRecord(
  kind: EntityKind.pantryItem,
  id: id,
  json: {
    'id': id,
    'name': name ?? id,
    'group': 'pantry',
    'aliases': <String>[],
  },
  stamp: s(at, by),
  label: name ?? id,
);

StampedRecord recipe(
  String id, {
  required int at,
  String by = 'A',
  String title = 'Katsu',
  List<Map<String, dynamic>>? ingredients,
}) => StampedRecord(
  kind: EntityKind.recipe,
  id: id,
  json: {
    'id': id,
    'title': title,
    'mealTypeId': 'm',
    'components': [
      {'id': 'c1', 'recipeId': id, 'name': 'Main', 'order': 0},
    ],
    'ingredients':
        ingredients ??
        [
          {'id': 'i1', 'componentId': 'c1', 'name': 'chicken', 'order': 0},
        ],
    'steps': <Map<String, dynamic>>[],
  },
  stamp: s(at, by),
  label: title,
);

DbSnapshot snap({
  List<StampedRecord> records = const [],
  List<Tombstone> graves = const [],
  Map<String, Register> registers = const {},
}) => DbSnapshot(
  entities: {for (final r in records) r.id: r},
  tombstones: {for (final g in graves) g.id: g},
  registers: registers,
);

Tombstone grave(
  String id,
  int at, {
  String by = 'A',
  EntityKind kind = EntityKind.pantryItem,
}) => Tombstone(kind: kind, id: id, stamp: s(at, by));

MergePlan run(
  DbSnapshot a,
  DbSnapshot b, {
  Map<String, Resolution> answers = const {},
}) => mergeDatabase(a, b, answers: answers);

void main() {
  group('the decision table', () {
    test('a record only the peer has is added', () {
      final plan = run(snap(), snap(records: [item('x', at: 1)]));
      expect(plan.result.entities.keys, ['x']);
      expect(plan.stats.totalAdded, 1);
    });

    test('a record only we have is kept — the peer simply has not seen it', () {
      final plan = run(snap(records: [item('x', at: 1)]), snap());
      expect(plan.result.entities.keys, ['x']);
    });

    test('equal stamps are a no-op', () {
      final plan = run(
        snap(records: [item('x', at: 1)]),
        snap(records: [item('x', at: 1)]),
      );
      expect(plan.unresolved, isEmpty);
      expect(plan.stats.totalUpdated, 0);
    });

    test('same content, different stamps converges on the higher stamp', () {
      // Not a conflict: settling here is what stops the pair oscillating on
      // every future exchange.
      final plan = run(
        snap(records: [item('x', at: 1, by: 'A')]),
        snap(records: [item('x', at: 5, by: 'B')]),
      );
      expect(plan.unresolved, isEmpty);
      expect(plan.result.entities['x']!.stamp, s(5, 'B'));
    });

    test('different content at different stamps is not a conflict', () {
      // The newer copy wins outright. Only a tie is worth interrupting for.
      final plan = run(
        snap(records: [item('x', at: 1, name: 'parmesan')]),
        snap(
          records: [item('x', at: 5, by: 'B', name: 'parmigiano')],
        ),
      );
      expect(plan.isComplete, isTrue);
      expect(plan.result.entities['x']!.json['name'], 'parmigiano');
    });

    test('a delete beats a copy that predates it, silently', () {
      final plan = run(
        snap(graves: [grave('x', 10)]),
        snap(records: [item('x', at: 5)]),
      );
      expect(plan.result.entities, isEmpty);
      expect(plan.unresolved, isEmpty);
    });

    test('an edit after the delete wins and brings the record back', () {
      // The edit is strictly newer than the delete, so newest-wins settles it
      // without asking: someone changed their mind after deleting.
      final plan = run(
        snap(graves: [grave('x', 5)]),
        snap(records: [item('x', at: 10, by: 'B')]),
      );
      expect(plan.isComplete, isTrue);
      expect(plan.result.entities.containsKey('x'), isTrue);
      expect(plan.result.tombstones.containsKey('x'), isFalse);
    });

    test('an edit stamped exactly at the delete is a question', () {
      // A tie against a tombstone is the same problem as a tie between two
      // edits: nothing in the stamps can settle it.
      final plan = run(
        snap(graves: [grave('x', 5)]),
        snap(records: [item('x', at: 5, by: 'A')]),
      );
      expect(plan.unresolved.single.reason, ConflictReason.editDelete);
      // Held rather than dropped: an unfinished review must not lose the edit.
      expect(plan.result.entities.containsKey('x'), isTrue);
    });

    test('two deletes agree on the earlier stamp', () {
      // Both sides must land on the same answer, whichever asks.
      final ab = run(
        snap(graves: [grave('x', 5)]),
        snap(graves: [grave('x', 9, by: 'B')]),
      );
      final ba = run(
        snap(graves: [grave('x', 9, by: 'B')]),
        snap(graves: [grave('x', 5)]),
      );
      expect(ab.result.tombstones['x']!.stamp, s(5, 'A'));
      expect(ba.result.tombstones['x']!.stamp, s(5, 'A'));
    });

    test('tombstones union unconditionally', () {
      final plan = run(
        snap(graves: [grave('a', 1)]),
        snap(graves: [grave('b', 2)]),
      );
      expect(plan.result.tombstones.keys.toSet(), {'a', 'b'});
    });
  });

  group('ties — the only thing the merge ever asks about', () {
    final mine = item('x', at: 1, by: 'A', name: 'mine');
    final theirs = item('x', at: 9, by: 'B', name: 'theirs');

    test('the newer copy wins, with nothing to answer', () {
      final plan = run(snap(records: [mine]), snap(records: [theirs]));
      expect(plan.unresolved, isEmpty);
      expect(plan.result.entities['x']!.json['name'], 'theirs');
    });

    test('an identical stamp with differing content is a question', () {
      // Same instant, same writer — the stamps have nothing left to say, so
      // this is the one case the user has to settle.
      final plan = run(
        snap(
          records: [item('x', at: 5, by: 'A', name: 'mine')],
        ),
        snap(
          records: [item('x', at: 5, by: 'A', name: 'theirs')],
        ),
      );
      expect(plan.unresolved, hasLength(1));
      expect(plan.unresolved.single.reason, ConflictReason.editEdit);
    });

    test('an identical stamp with identical content is silent', () {
      final plan = run(
        snap(
          records: [item('x', at: 5, by: 'A', name: 'same')],
        ),
        snap(
          records: [item('x', at: 5, by: 'A', name: 'same')],
        ),
      );
      expect(plan.unresolved, isEmpty);
      expect(plan.stats.totalConflicted, 0);
    });

    test('an answer settles it on replay', () {
      final a = snap(
        records: [item('x', at: 5, by: 'A', name: 'mine')],
      );
      final b = snap(
        records: [item('x', at: 5, by: 'A', name: 'theirs')],
      );
      final plan = run(a, b, answers: {'x': Resolution.takeRemote});
      expect(plan.isComplete, isTrue);
      expect(plan.result.entities['x']!.json['name'], 'theirs');
    });

    test('a tie holds the local copy until it is answered', () {
      // Abandoning a review must lose nothing.
      final a = snap(
        records: [item('x', at: 5, by: 'A', name: 'mine')],
      );
      final b = snap(
        records: [item('x', at: 5, by: 'A', name: 'theirs')],
      );
      expect(run(a, b).result.entities['x']!.json['name'], 'mine');
    });

    test('a tie is raised on BOTH devices, not just one', () {
      // The bug this replaces: each device silently kept its own copy and no
      // conflict was raised at all, so the two never converged and neither
      // user was ever told.
      final a = snap(
        records: [item('x', at: 5, by: 'A', name: 'mine')],
      );
      final b = snap(
        records: [item('x', at: 5, by: 'A', name: 'theirs')],
      );
      expect(run(a, b).unresolved, hasLength(1));
      expect(run(b, a).unresolved, hasLength(1));
    });
  });

  group('registers', () {
    test('resolve by stamp and never ask', () {
      final plan = run(
        snap(registers: {'assumeStaples': Register(true, s(1, 'A'))}),
        snap(registers: {'assumeStaples': Register(false, s(9, 'B'))}),
      );
      expect(plan.result.registers['assumeStaples']!.value, false);
      expect(plan.unresolved, isEmpty);
    });
  });

  group('idempotence and convergence', () {
    String fingerprint(DbSnapshot s) {
      final ids = s.entities.keys.toList()..sort();
      final graves = s.tombstones.keys.toList()..sort();
      return jsonEncode({
        'entities': {
          for (final id in ids)
            id: {
              'json': s.entities[id]!.json,
              'stamp': s.entities[id]!.stamp.toString(),
            },
        },
        'tombstones': graves,
      });
    }

    /// Random but reproducible pairs of snapshots that have drifted apart.
    ({DbSnapshot a, DbSnapshot b}) drift(int seed) {
      final rng = Random(seed);
      final a = <StampedRecord>[];
      final b = <StampedRecord>[];
      final ga = <Tombstone>[];
      final gb = <Tombstone>[];

      for (var i = 0; i < 12; i++) {
        final id = 'e$i';
        final base = 100 + rng.nextInt(50);
        switch (rng.nextInt(6)) {
          case 0: // only on A
            a.add(item(id, at: base));
          case 1: // only on B
            b.add(item(id, at: base, by: 'B'));
          case 2: // same on both
            a.add(item(id, at: base));
            b.add(item(id, at: base));
          case 3: // edited on both — a real conflict
            a.add(item(id, at: base, name: 'a$i'));
            b.add(item(id, at: base + rng.nextInt(20), by: 'B', name: 'b$i'));
          case 4: // deleted on A, still present on B
            ga.add(grave(id, base + 10));
            b.add(item(id, at: base + rng.nextInt(30), by: 'B'));
          case 5: // deleted on both
            ga.add(grave(id, base));
            gb.add(grave(id, base + 5, by: 'B'));
        }
      }
      return (a: snap(records: a, graves: ga), b: snap(records: b, graves: gb));
    }

    {
      test('merging twice changes nothing the second time', () {
        for (var seed = 0; seed < 40; seed++) {
          final d = drift(seed);
          final once = run(d.a, d.b).result;
          final twice = run(once, d.b).result;
          expect(fingerprint(twice), fingerprint(once), reason: 'seed $seed');
        }
      });

      test('A→B and B→A converge', () {
        for (var seed = 0; seed < 40; seed++) {
          final d = drift(seed);
          final ab = run(d.a, d.b).result;
          final ba = run(d.b, d.a).result;
          // Each side then hears the other's merged result.
          final finalA = run(ab, ba).result;
          final finalB = run(ba, ab).result;
          expect(
            finalA.entities.keys.toSet(),
            finalB.entities.keys.toSet(),
            reason: 'seed $seed',
          );
          expect(
            finalA.tombstones.keys.toSet(),
            finalB.tombstones.keys.toSet(),
            reason: 'seed $seed',
          );
        }
      });

      test('no id is ever lost without a tombstone explaining it', () {
        for (var seed = 0; seed < 40; seed++) {
          final d = drift(seed);
          final out = run(d.a, d.b).result;
          final seen = {...d.a.entities.keys, ...d.b.entities.keys};
          for (final id in seen) {
            expect(
              out.entities.containsKey(id) || out.tombstones.containsKey(id),
              isTrue,
              reason: 'seed $seed lost $id',
            );
          }
        }
      });
    }

    test('a merge never invents a record', () {
      // What "keep both" used to do, and why it was removed: on a tie each
      // device made *itself* the winner, minted a copy the other had never
      // seen, and every exchange bred another one. Nothing is minted now.
      final a = snap(
        records: [item('x', at: 1, by: 'A', name: 'mine')],
      );
      final b = snap(
        records: [item('x', at: 9, by: 'B', name: 'theirs')],
      );

      final once = run(a, b).result;
      expect(once.entities, hasLength(1));
      expect(run(once, b).result.entities, hasLength(1));
      expect(run(run(once, b).result, b).result.entities, hasLength(1));
    });
  });
}
