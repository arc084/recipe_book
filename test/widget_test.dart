import 'package:flutter_test/flutter_test.dart';

import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/domain/macros.dart';
import 'package:recipe_book/domain/recipe_parser.dart';
import 'package:recipe_book/domain/units.dart';

/// The calculation rule is the thing the whole app hangs off, so it is what
/// gets tested: macros are summed from linked pantry items, an ingredient with
/// no macros is flagged rather than counted as zero, and estimated values
/// carry through to a recipe's totals.
void main() {
  group('units', () {
    test('reduces mass and volume to their base units', () {
      expect(toBase(1, 'kg')!.amount, 1000);
      expect(toBase(1, 'kg')!.dimension, Dimension.mass);
      expect(toBase(2, 'tbsp')!.amount, closeTo(29.57, 0.01));
      expect(toBase(2, 'tbsp')!.dimension, Dimension.volume);
      expect(toBase(4, '')!.dimension, Dimension.count);
    });

    test('refuses to guess at an unmeasurable amount', () {
      expect(toBase(null, 'handful'), isNull);
      expect(toBase(1, 'pinch'), isNull);
    });

    test('formats amounts without trailing zeroes', () {
      expect(formatAmount(4), '4');
      expect(formatAmount(1.5), '1.5');
      expect(formatAmount(null), '');
    });
  });

  group('MacroEngine', () {
    late PantryItem chicken;
    late PantryItem oil;
    late PantryItem basil;
    late Recipe recipe;

    setUp(() {
      chicken = PantryItem(
        id: 'chicken',
        name: 'chicken breast',
        servingAmount: 150,
        servingUnit: 'g',
        altAmount: 1,
        altUnit: 'cutlet',
        calories: 165,
        protein: 31,
        fat: 3.6,
        carbs: 0,
        sugar: 0,
      );
      oil = PantryItem(
        id: 'oil',
        name: 'olive oil',
        servingAmount: 13.5,
        servingUnit: 'g',
        altAmount: 1,
        altUnit: 'tbsp',
        calories: 884,
        protein: 0,
        fat: 100,
        carbs: 0,
        sugar: 0,
      );
      // No macros entered yet.
      basil = PantryItem(id: 'basil', name: 'basil');

      recipe = Recipe(id: 'r', title: 'Test', mealTypeId: 'm', servings: 2);
      final component =
          RecipeComponent(id: 'c', recipeId: 'r', name: 'All', order: 0);
      recipe.components.add(component);
    });

    Ingredient line(
      double? qty,
      String unit,
      String name, {
      String? link,
      int order = 0,
    }) =>
        Ingredient(
          id: 'i$order$name',
          componentId: 'c',
          quantity: qty,
          unit: unit,
          name: name,
          pantryItemId: link,
          order: order,
        );

    test('scales a mass amount against a per-100 g basis', () {
      recipe.ingredients.add(line(200, 'g', 'chicken', link: 'chicken'));
      final totals = MacroEngine([chicken]).forRecipe(recipe);

      expect(totals.macros.calories, closeTo(330, 0.001));
      expect(totals.macros.protein, closeTo(62, 0.001));
      expect(totals.isComplete, isTrue);
    });

    test('bridges a count to a mass through the item’s second measurement',
        () {
      // 2 cutlets, where the item says one cutlet is 150 g.
      recipe.ingredients.add(line(2, '', 'chicken cutlets', link: 'chicken'));
      final totals = MacroEngine([chicken]).forRecipe(recipe);

      // 300 g == 3 portions of 100 g == 495 cal.
      expect(totals.macros.calories, closeTo(495, 0.001));
    });

    test('bridges volume to mass through the item’s second measurement', () {
      recipe.ingredients.add(line(2, 'tbsp', 'olive oil', link: 'oil'));
      final totals = MacroEngine([oil]).forRecipe(recipe);

      // 2 tbsp ≈ 29.57 ml; the item says 13.5 g is 1 tbsp, so ≈ 27 g.
      expect(totals.macros.calories, closeTo(238.7, 1.0));
    });

    test('flags an ingredient with no macros instead of counting it as zero',
        () {
      recipe.ingredients
        ..add(line(200, 'g', 'chicken', link: 'chicken', order: 0))
        ..add(line(null, 'handful', 'basil', link: 'basil', order: 1));

      final totals = MacroEngine([chicken, basil]).forRecipe(recipe);

      expect(totals.isComplete, isFalse);
      expect(totals.gaps, hasLength(1));
      expect(totals.gaps.single.gap, LineGap.noMacros);
      // The counted line still contributes in full.
      expect(totals.macros.calories, closeTo(330, 0.001));
    });

    test('flags a line that is not linked to a pantry item at all', () {
      recipe.ingredients.add(line(100, 'g', 'panko breadcrumbs'));
      final totals = MacroEngine([chicken]).forRecipe(recipe);

      expect(totals.gaps.single.gap, LineGap.notLinked);
      expect(totals.macros.calories, 0);
    });

    test('carries an estimated flag through to the recipe totals', () {
      final estimated = chicken.copy()..isEstimated = true;
      recipe.ingredients.add(line(100, 'g', 'chicken', link: 'chicken'));

      final totals = MacroEngine([estimated]).forRecipe(recipe);
      expect(totals.isEstimated, isTrue);
    });

    test('scales to a different serving count without touching the recipe',
        () {
      recipe.ingredients.add(line(200, 'g', 'chicken', link: 'chicken'));
      final engine = MacroEngine([chicken]);

      final asSaved = engine.forRecipe(recipe);
      final doubled = engine.forRecipe(recipe, servings: 4);

      expect(asSaved.macros.calories, closeTo(330, 0.001));
      expect(doubled.macros.calories, closeTo(660, 0.001));
      // Per serving is unchanged by scaling — that is the point of it.
      expect(asSaved.perServing.calories, closeTo(165, 0.001));
      expect(doubled.perServing.calories, closeTo(165, 0.001));
      // Nothing was written.
      expect(recipe.servings, 2);
    });
  });

  group('PantryCoverage', () {
    test('excludes staples and reads the grocery list', () {
      final salt = PantryItem(id: 's', name: 'salt', isStaple: true);
      final tomatoes = PantryItem(id: 't', name: 'canned tomatoes');

      final recipe =
          Recipe(id: 'r', title: 'Test', mealTypeId: 'm', servings: 2);
      recipe.components
          .add(RecipeComponent(id: 'c', recipeId: 'r', name: 'All', order: 0));
      recipe.ingredients.addAll([
        Ingredient(
            id: '1', componentId: 'c', unit: '', name: 'salt', order: 0),
        Ingredient(
            id: '2',
            componentId: 'c',
            unit: 'g',
            quantity: 400,
            name: 'canned tomatoes',
            order: 1),
        Ingredient(
            id: '3',
            componentId: 'c',
            unit: 'g',
            quantity: 100,
            name: 'panko breadcrumbs',
            order: 2),
        Ingredient(
            id: '4', componentId: 'c', unit: '', name: 'lemons', order: 3),
      ]);

      final coverage = PantryCoverage(
        pantry: [salt, tomatoes],
        groceries: [
          GroceryItem(id: 'g', name: 'lemons', aisleId: 'a'),
        ],
        assumeStaples: true,
      );

      final summary = coverage.summarise(recipe);
      // Salt is a staple and the tomatoes are in the pantry, so the user has
      // 2 of the 4. The lemons are on the list but still not in the pantry,
      // so they count as missing alongside the panko.
      expect(summary.have, 2);
      expect(summary.total, 4);
      expect(
        summary.missing.map((c) => c.ingredient.name).toList(),
        ['panko breadcrumbs', 'lemons'],
      );
      // But only the panko still needs buying — the lemons are already on the
      // list, so adding the missing items must not add them twice.
      expect(summary.toBuy.map((c) => c.ingredient.name).toList(),
          ['panko breadcrumbs']);
    });

    test('counts staples when the user turns the assumption off', () {
      final salt = PantryItem(id: 's', name: 'salt', isStaple: true);
      final recipe =
          Recipe(id: 'r', title: 'Test', mealTypeId: 'm', servings: 2);
      recipe.components
          .add(RecipeComponent(id: 'c', recipeId: 'r', name: 'All', order: 0));
      recipe.ingredients.add(
        Ingredient(id: '1', componentId: 'c', unit: '', name: 'salt', order: 0),
      );

      final coverage = PantryCoverage(
        pantry: [salt],
        groceries: const [],
        assumeStaples: false,
      );
      // Still in the pantry — turning the assumption off does not make an item
      // the user owns go missing.
      expect(coverage.of(recipe.ingredients.first).coverage,
          Coverage.inPantry);
    });
  });

  group('continuous step numbering', () {
    test('runs across components in component order', () {
      final recipe =
          Recipe(id: 'r', title: 'Test', mealTypeId: 'm', servings: 2);
      recipe.components.addAll([
        RecipeComponent(id: 'c1', recipeId: 'r', name: 'First', order: 0),
        RecipeComponent(id: 'c2', recipeId: 'r', name: 'Second', order: 1),
      ]);
      recipe.steps.addAll([
        RecipeStep(id: 's3', componentId: 'c2', text: 'third', order: 2),
        RecipeStep(id: 's1', componentId: 'c1', text: 'first', order: 0),
        RecipeStep(id: 's2', componentId: 'c1', text: 'second', order: 1),
      ]);

      expect(
        recipe.orderedSteps.map((s) => s.text).toList(),
        ['first', 'second', 'third'],
      );
    });
  });

  group('RecipeParser', () {
    test('splits an ingredient line into three separate fields', () {
      final line = RecipeParser.parseIngredientLine('400 g canned tomatoes');
      expect(line.quantity, 400);
      expect(line.unit, 'g');
      expect(line.name, 'canned tomatoes');
    });

    test('reads mixed numbers and unicode fractions', () {
      expect(RecipeParser.parseIngredientLine('1 1/2 cups flour').quantity,
          closeTo(1.5, 0.001));
      expect(RecipeParser.parseIngredientLine('½ tsp salt').quantity,
          closeTo(0.5, 0.001));
    });

    test('leaves an unrecognised unit as part of the name', () {
      final line = RecipeParser.parseIngredientLine('2 large onions');
      expect(line.quantity, 2);
      expect(line.unit, '');
      expect(line.name, 'large onions');
    });

    test('reads a schema.org JSON-LD recipe off a page', () {
      const page = '''
<html><head>
<script type="application/ld+json">
{"@context":"https://schema.org","@type":"Recipe",
 "name":"Test Bake","recipeYield":"4 servings","totalTime":"PT1H20M",
 "recipeIngredient":["200 g flour","2 eggs"],
 "recipeInstructions":[{"@type":"HowToStep","text":"Mix it."},
                       {"@type":"HowToStep","text":"Bake it."}],
 "nutrition":{"@type":"NutritionInformation","calories":"520 kcal"}}
</script></head><body></body></html>
''';

      final parsed = RecipeParser.parse(page, url: 'https://example.com/r');
      expect(parsed, isNotNull);
      expect(parsed!.title, 'Test Bake');
      expect(parsed.servings, 4);
      expect(parsed.totalMinutes, 80);
      expect(parsed.ingredients, hasLength(2));
      expect(parsed.ingredients.first.quantity, 200);
      expect(parsed.ingredients.first.unit, 'g');
      expect(parsed.steps, ['Mix it.', 'Bake it.']);
      // The page's own figure is read, but only so it can be shown as about
      // to be replaced.
      expect(parsed.listedCalories, 520);
      expect(parsed.sourceUrl, 'https://example.com/r');
    });

    test('returns null when a page holds no recipe', () {
      expect(RecipeParser.parse('<html><body>Hello</body></html>'), isNull);
    });
  });
}
