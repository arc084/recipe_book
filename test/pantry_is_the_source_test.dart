import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/state/app_state.dart';

/// Nothing is an ingredient without being a pantry item.
///
/// Groceries and recipe lines used to be able to name something the pantry
/// had never heard of — a grocery carried a loose string, and an unmatched
/// recipe line was flagged and left alone. Both now resolve to a pantry item,
/// making one when the name is new.
void main() {
  late Directory dir;
  late AppState app;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('rb_pantry_source');
    app = AppState(directory: dir);
    await app.load();
    app.pantry.items.clear();
    app.library.groceries.clear();
  });

  tearDown(() async {
    await app.flush();
    dir.deleteSync(recursive: true);
  });

  Recipe recipeNaming(List<String> names, {Set<String> branded = const {}}) {
    final r = Recipe(id: newId(), title: 'Dish', mealTypeId: 'x', servings: 2);
    final c = RecipeComponent(
      id: newId(),
      recipeId: r.id,
      name: 'Main',
      order: 0,
    );
    r.components.add(c);
    for (var i = 0; i < names.length; i++) {
      r.ingredients.add(
        Ingredient(
          id: newId(),
          componentId: c.id,
          quantity: 1,
          unit: '',
          name: names[i],
          order: i,
          isBranded: branded.contains(names[i]),
        ),
      );
    }
    return r;
  }

  group('groceries', () {
    test('an unknown name makes a pantry item, out of stock', () {
      final g = app.addGrocery('lemons');
      final item = app.pantryItem(g.pantryItemId!)!;
      expect(item.name, 'lemons');
      expect(item.inStock, isFalse, reason: 'it is on the list to be bought');
    });

    test('a known name links to what is already there', () {
      final butter = app.addPantryItem('Butter');
      final g = app.addGrocery('butter');
      expect(g.pantryItemId, butter.id);
      expect(app.pantry.items, hasLength(1));
    });

    test('an alias counts as known', () {
      final chips = app.addPantryItem('Chocolate chips');
      app.addAlias(chips.id, 'choc chips');
      expect(app.addGrocery('choc chips').pantryItemId, chips.id);
      expect(app.pantry.items, hasLength(1));
    });

    test('checking it off puts that same item back in stock', () {
      final g = app.addGrocery('lemons');
      app.toggleGrocery(g.id);
      app.clearChecked();
      expect(app.pantryItem(g.pantryItemId!)!.inStock, isTrue);
      expect(app.pantry.items, hasLength(1));
    });
  });

  group('recipes', () {
    test('an unknown ingredient makes a pantry item, out of stock', () {
      final r = recipeNaming(['gochujang']);
      app.saveRecipe(r);

      final line = app.recipe(r.id)!.ingredients.single;
      expect(line.pantryItemId, isNotNull);
      final item = app.pantryItem(line.pantryItemId!)!;
      expect(item.name, 'gochujang');
      expect(item.inStock, isFalse);
    });

    test('a known ingredient links rather than duplicating', () {
      final rice = app.addPantryItem('sushi rice');
      app.saveRecipe(recipeNaming(['sushi rice']));
      expect(app.pantry.items, hasLength(1));
      expect(app.library.recipes.last.ingredients.single.pantryItemId, rice.id);
    });

    test('a branded line keeps its own macros and stays unlinked', () {
      app.saveRecipe(
        recipeNaming(['Heinz Ketchup'], branded: {'Heinz Ketchup'}),
      );
      expect(app.library.recipes.last.ingredients.single.pantryItemId, isNull);
      expect(app.pantry.items, isEmpty);
    });

    test('saving twice does not make a second item', () {
      final r = recipeNaming(['gochujang']);
      app.saveRecipe(r);
      app.saveRecipe(app.recipe(r.id)!);
      expect(app.pantry.items, hasLength(1));
    });

    test('a new ingredient is still missing, as it was before', () {
      final r = recipeNaming(['gochujang']);
      app.saveRecipe(r);
      final summary = app.coverage.summarise(app.recipe(r.id)!);
      expect(summary.missing, hasLength(1));
      expect(summary.have, 0);
    });
  });

  test('the grocery and the recipe end up on the same item', () {
    app.saveRecipe(recipeNaming(['gochujang']));
    final line = app.library.recipes.last.ingredients.single;
    final g = app.addGrocery('gochujang');
    expect(g.pantryItemId, line.pantryItemId);
    expect(app.pantry.items, hasLength(1));
  });
}
