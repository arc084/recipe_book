import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/settings.dart';
import 'package:recipe_book/domain/sync/merge.dart';
import 'package:recipe_book/domain/sync/stamp.dart';
import 'package:recipe_book/domain/sync/tombstone.dart';

DateTime t(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
Stamp s(int ms, String by) => Stamp(t(ms), by);

/// A pantry item, the simplest record with a name.
StampedRecord item(String id, {required int at, String by = 'A', String? name}) =>
    StampedRecord(
      kind: EntityKind.pantryItem,
      id: id,
      json: {'id': id, 'name': name ?? id, 'group': 'pantry', 'aliases': <String>[]},
      stamp: s(at, by),
      label: name ?? id,
    );

StampedRecord recipe(
  String id, {
  required int at,
  String by = 'A',
  String title = 'Katsu',
  List<Map<String, dynamic>>? ingredients,
}) =>
    StampedRecord(
      kind: EntityKind.recipe,
      id: id,
      json: {
        'id': id,
        'title': title,
        'mealTypeId': 'm',
        'components': [
          {'id': 'c1', 'recipeId': id, 'name': 'Main', 'order': 0},
        ],
        'ingredients': ingredients ??
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
}) =>
    DbSnapshot(
      entities: {for (final r in records) r.id: r},
      tombstones: {for (final g in graves) g.id: g},
      registers: registers,
    );

Tombstone grave(String id, int at, {String by = 'A', EntityKind kind = EntityKind.pantryItem}) =>
    Tombstone(kind: kind, id: id, stamp: s(at, by));

MergePlan run(
  DbSnapshot a,
  DbSnapshot b, {
  ConflictPolicy policy = ConflictPolicy.newestWins,
  Map<String, Resolution> answers = const {},
}) =>
    mergeDatabase(a, b, policy: policy, answers: answers);

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

    test('different content is a conflict', () {
      final plan = run(
        snap(records: [item('x', at: 1, name: 'parmesan')]),
        snap(records: [item('x', at: 5, by: 'B', name: 'parmigiano')]),
        policy: ConflictPolicy.ask,
      );
      expect(plan.unresolved.single.reason, ConflictReason.editEdit);
      expect(plan.isComplete, isFalse);
    });

    test('a delete beats a copy that predates it, silently', () {
      final plan = run(
        snap(graves: [grave('x', 10)]),
        snap(records: [item('x', at: 5)]),
      );
      expect(plan.result.entities, isEmpty);
      expect(plan.unresolved, isEmpty);
    });

    test('an edit after the delete raises a conflict', () {
      final plan = run(
        snap(graves: [grave('x', 5)]),
        snap(records: [item('x', at: 10, by: 'B')]),
        policy: ConflictPolicy.ask,
      );
      expect(plan.unresolved.single.reason, ConflictReason.editDelete);
      // The record is held rather than dropped: an unfinished review must not
      // lose the edit.
      expect(plan.result.entities.containsKey('x'), isTrue);
    });

    test('two deletes agree on the earlier stamp', () {
      // Both sides must land on the same answer, whichever asks.
      final ab = run(snap(graves: [grave('x', 5)]), snap(graves: [grave('x', 9, by: 'B')]));
      final ba = run(snap(graves: [grave('x', 9, by: 'B')]), snap(graves: [grave('x', 5)]));
      expect(ab.result.tombstones['x']!.stamp, s(5, 'A'));
      expect(ba.result.tombstones['x']!.stamp, s(5, 'A'));
    });

    test('tombstones union unconditionally', () {
      final plan = run(snap(graves: [grave('a', 1)]), snap(graves: [grave('b', 2)]));
      expect(plan.result.tombstones.keys.toSet(), {'a', 'b'});
    });
  });

  group('policies', () {
    final mine = item('x', at: 1, by: 'A', name: 'mine');
    final theirs = item('x', at: 9, by: 'B', name: 'theirs');

    test('newest wins settles without asking', () {
      final plan = run(snap(records: [mine]), snap(records: [theirs]));
      expect(plan.isComplete, isTrue);
      expect(plan.result.entities['x']!.json['name'], 'theirs');
    });

    test('ask defers and suggests the newer side', () {
      final plan = run(
        snap(records: [mine]),
        snap(records: [theirs]),
        policy: ConflictPolicy.ask,
      );
      expect(plan.unresolved.single.suggested, Resolution.takeRemote);
    });

    test('an answer settles it on replay', () {
      final plan = run(
        snap(records: [mine]),
        snap(records: [theirs]),
        policy: ConflictPolicy.ask,
        answers: {'x': Resolution.takeLocal},
      );
      expect(plan.isComplete, isTrue);
      expect(plan.result.entities['x']!.json['name'], 'mine');
    });

    test('keep both produces a second, labelled pantry item', () {
      final plan = run(
        snap(records: [mine]),
        snap(records: [theirs]),
        policy: ConflictPolicy.keepBoth,
      );
      expect(plan.result.entities, hasLength(2));
      final copy = plan.result.entities.values.firstWhere((e) => e.id != 'x');
      expect(copy.json['name'], contains('mine'));
      // The copy drops its aliases: two items answering to the same name would
      // make name matching depend on which was found first.
      expect(copy.json['aliases'], isEmpty);
    });

    test('keep both re-mints a copied recipe\'s nested records', () {
      final a = recipe('r', at: 1, title: 'Katsu');
      final b = recipe('r', at: 9, by: 'B', title: 'Katsu curry');
      final plan = run(
        snap(records: [a]),
        snap(records: [b]),
        policy: ConflictPolicy.keepBoth,
      );
      final copy = plan.result.entities.values.firstWhere((e) => e.id != 'r');
      final components = copy.json['components'] as List;
      final ingredients = copy.json['ingredients'] as List;
      expect(components.first['id'], isNot('c1'));
      expect(components.first['recipeId'], copy.id);
      // The ingredient must follow its component, or the copy has an orphan.
      expect(ingredients.first['componentId'], components.first['id']);
    });

    test('keep both degrades to newest for meal types and aisles', () {
      // Two "Dinner" categories are worse than losing a rename.
      final a = StampedRecord(
        kind: EntityKind.mealType,
        id: 'm',
        json: {'id': 'm', 'name': 'Dinner', 'order': 0},
        stamp: s(1, 'A'),
        label: 'Dinner',
      );
      final b = StampedRecord(
        kind: EntityKind.mealType,
        id: 'm',
        json: {'id': 'm', 'name': 'Supper', 'order': 0},
        stamp: s(9, 'B'),
        label: 'Supper',
      );
      final plan = run(
        snap(records: [a]),
        snap(records: [b]),
        policy: ConflictPolicy.keepBoth,
      );
      expect(plan.result.entities, hasLength(1));
      expect(plan.result.entities['m']!.json['name'], 'Supper');
    });
  });

  group('registers', () {
    test('resolve by stamp and never ask', () {
      final plan = run(
        snap(registers: {'assumeStaples': Register(true, s(1, 'A'))}),
        snap(registers: {'assumeStaples': Register(false, s(9, 'B'))}),
        policy: ConflictPolicy.ask,
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

    for (final policy in [ConflictPolicy.newestWins, ConflictPolicy.keepBoth]) {
      test('merging twice changes nothing the second time (${policy.name})', () {
        for (var seed = 0; seed < 40; seed++) {
          final d = drift(seed);
          final once = run(d.a, d.b, policy: policy).result;
          final twice = run(once, d.b, policy: policy).result;
          expect(
            fingerprint(twice),
            fingerprint(once),
            reason: 'seed $seed under ${policy.name}',
          );
        }
      });

      test('A→B and B→A converge (${policy.name})', () {
        for (var seed = 0; seed < 40; seed++) {
          final d = drift(seed);
          final ab = run(d.a, d.b, policy: policy).result;
          final ba = run(d.b, d.a, policy: policy).result;
          // Each side then hears the other's merged result.
          final finalA = run(ab, ba, policy: policy).result;
          final finalB = run(ba, ab, policy: policy).result;
          expect(
            finalA.entities.keys.toSet(),
            finalB.entities.keys.toSet(),
            reason: 'seed $seed under ${policy.name}',
          );
          expect(
            finalA.tombstones.keys.toSet(),
            finalB.tombstones.keys.toSet(),
            reason: 'seed $seed under ${policy.name}',
          );
        }
      });

      test('no id is ever lost without a tombstone explaining it (${policy.name})',
          () {
        for (var seed = 0; seed < 40; seed++) {
          final d = drift(seed);
          final out = run(d.a, d.b, policy: policy).result;
          final seen = {...d.a.entities.keys, ...d.b.entities.keys};
          for (final id in seen) {
            expect(
              out.entities.containsKey(id) || out.tombstones.containsKey(id),
              isTrue,
              reason: 'seed $seed lost $id under ${policy.name}',
            );
          }
        }
      });
    }

    test('keep-both does not breed copies of copies', () {
      // The mint is a pure function of the conflict, so the second merge
      // recomputes the same id, finds it already present, and does nothing.
      // A clock-read or random id here would double the library every sync.
      final a = snap(records: [item('x', at: 1, by: 'A', name: 'mine')]);
      final b = snap(records: [item('x', at: 9, by: 'B', name: 'theirs')]);

      final once = run(a, b, policy: ConflictPolicy.keepBoth).result;
      expect(once.entities, hasLength(2));

      final twice = run(once, b, policy: ConflictPolicy.keepBoth).result;
      expect(twice.entities, hasLength(2));

      final thrice = run(twice, b, policy: ConflictPolicy.keepBoth).result;
      expect(thrice.entities, hasLength(2));
    });
  });
}
