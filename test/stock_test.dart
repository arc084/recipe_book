import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/domain/macros.dart';

/// A pantry item with macros, so coverage is the only thing under test.
PantryItem _item(String name, {bool inStock = true, bool isStaple = false}) =>
    PantryItem(
      id: 'p-$name',
      name: name,
      inStock: inStock,
      isStaple: isStaple,
      calories: 100,
      protein: 10,
    );

Ingredient _line(String name, String pantryItemId) => Ingredient(
  id: 'i-$name',
  componentId: 'c1',
  name: name,
  quantity: 100,
  unit: 'g',
  pantryItemId: pantryItemId,
  order: 0,
);

void main() {
  group('running out of something', () {
    test('an item in stock is covered by the pantry', () {
      final coverage = PantryCoverage(
        pantry: [_item('parmesan')],
        groceries: const [],
        assumeStaples: true,
      );
      final result = coverage.of(_line('parmesan', 'p-parmesan'));

      expect(result.coverage, Coverage.inPantry);
      expect(result.countsAsMissing, isFalse);
      expect(result.needsBuying, isFalse);
    });

    test('an item run out counts as missing and wants buying', () {
      final coverage = PantryCoverage(
        pantry: [_item('parmesan', inStock: false)],
        groceries: const [],
        assumeStaples: true,
      );
      final result = coverage.of(_line('parmesan', 'p-parmesan'));

      expect(result.coverage, Coverage.outOfStock);
      expect(result.countsAsMissing, isTrue);
      expect(result.needsBuying, isTrue);
      // It is still a known item — the macros behind it are not lost.
      expect(result.pantryItem, isNotNull);
    });

    test('run out is distinct from never having had it', () {
      final coverage = PantryCoverage(
        pantry: [_item('parmesan', inStock: false)],
        groceries: const [],
        assumeStaples: true,
      );

      expect(
        coverage.of(_line('parmesan', 'p-parmesan')).coverage,
        Coverage.outOfStock,
      );
      expect(
        coverage.of(_line('saffron', 'p-saffron')).coverage,
        Coverage.missing,
      );
    });

    test('macros still calculate for an item that is run out', () {
      // The numbers belong to the item, not to having some in the cupboard,
      // so a recipe's totals must not change when it is marked run out.
      final engine = MacroEngine([_item('parmesan', inStock: false)]);
      final recipe = Recipe(
        id: 'r1',
        title: 'Test',
        mealTypeId: 'm1',
        servings: 1,
        components: [
          RecipeComponent(id: 'c1', recipeId: 'r1', name: 'All', order: 0),
        ],
        ingredients: [_line('parmesan', 'p-parmesan')],
      );

      final totals = engine.forRecipe(recipe);
      expect(totals.macros.calories, 100);
      expect(totals.isComplete, isTrue);
    });

    test('a staple that is run out is still missing', () {
      // Assuming staples on hand is about not nagging over salt, not about
      // pretending a jar the user has emptied is full.
      final coverage = PantryCoverage(
        pantry: [_item('flour', inStock: false, isStaple: true)],
        groceries: const [],
        assumeStaples: true,
      );

      expect(
        coverage.of(_line('flour', 'p-flour')).coverage,
        Coverage.outOfStock,
      );
    });
  });
}
