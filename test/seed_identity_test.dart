import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/data/seed.dart';

void main() {
  group('shipped seed identity', () {
    // The bug this guards against: the seed used to mint a fresh uuid per
    // install, so two devices held the same shipped recipes under different
    // ids. A sync saw them as unrelated records and added both, duplicating
    // the entire corpus — three times over, in practice.
    test('two independent installs agree on every seeded id', () {
      final a = Seed.build();
      final b = Seed.build();

      Set<String> ids(Iterable<dynamic> xs) => {
        for (final x in xs) x.id as String,
      };

      expect(ids(a.library.recipes), ids(b.library.recipes));
      expect(ids(a.library.mealTypes), ids(b.library.mealTypes));
      expect(ids(a.library.aisles), ids(b.library.aisles));
      expect(ids(a.library.groceries), ids(b.library.groceries));
      expect(ids(a.library.plan), ids(b.library.plan));
      expect(ids(a.pantry.items), ids(b.pantry.items));
    });

    test('nested recipe records agree too', () {
      final a = Seed.build().library.recipes.first;
      final b = Seed.build().library.recipes.first;

      expect(a.id, b.id);
      expect(
        a.components.map((c) => c.id).toList(),
        b.components.map((c) => c.id).toList(),
      );
      expect(
        a.ingredients.map((i) => i.id).toList(),
        b.ingredients.map((i) => i.id).toList(),
      );
      expect(
        a.steps.map((s) => s.id).toList(),
        b.steps.map((s) => s.id).toList(),
      );
    });

    test('ids are unique within one seed', () {
      final s = Seed.build();
      final all = [
        ...s.library.recipes.map((r) => r.id),
        ...s.library.mealTypes.map((m) => m.id),
        ...s.library.aisles.map((a) => a.id),
        ...s.library.groceries.map((g) => g.id),
        ...s.library.plan.map((p) => p.id),
        ...s.pantry.items.map((i) => i.id),
      ];
      expect(all.toSet().length, all.length, reason: 'a seed id collided');
    });

    test('distinct kinds with the same key do not collide', () {
      // "Dessert" is a meal type; nothing stops a pantry item sharing a name
      // with an aisle. The kind prefix is what keeps them apart.
      expect(
        seedIdFor('mealType', 'Dessert'),
        isNot(seedIdFor('aisle', 'Dessert')),
      );
    });
  });
}
