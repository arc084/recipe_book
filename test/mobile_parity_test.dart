import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/state/app_state.dart';
import 'package:recipe_book/theme/app_theme.dart';
import 'package:recipe_book/ui/mobile/mobile_groceries.dart';
import 'package:recipe_book/ui/mobile/mobile_pantry.dart';
import 'package:recipe_book/ui/mobile/mobile_plan.dart';

/// What the phone used to only show and can now change: an item's other
/// names, a grocery's name and aisle, and where a planned meal sits.
///
/// Each mutation is already covered where AppState is tested; these check
/// that the phone's sheets actually reach them.
void main() {
  late Directory dir;
  late AppState app;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('rb_mobile_parity');
    app = AppState(directory: dir);
    await app.load();
  });

  tearDown(() async {
    await app.flush();
    dir.deleteSync(recursive: true);
  });

  /// Runs any debounced disk write to completion outside the fake-async zone,
  /// then lets the screen settle — see the same helper in
  /// mobile_recipe_edit_test.dart for why a widget test that saves needs it.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(app.flush);
    await tester.pumpAndSettle();
  }

  Future<void> pump(WidgetTester tester, Widget page) async {
    // Wider than a phone. The test font draws every glyph as a full em
    // square, so labels that fit on a real 412dp screen overflow here, and
    // these tests are about what the sheets reach, not about layout.
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // Arrangement done before pumping queued saves of its own.
    await tester.runAsync(app.flush);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: page),
        ),
      ),
    );
    await drain(tester);
  }

  Recipe recipeUsing(String title, PantryItem item) {
    final r = Recipe(id: newId(), title: title, mealTypeId: 'x', servings: 1);
    final c = RecipeComponent(
      id: newId(),
      recipeId: r.id,
      name: 'Main',
      order: 0,
    );
    r.components.add(c);
    r.ingredients.add(
      Ingredient(
        id: newId(),
        componentId: c.id,
        quantity: 1,
        unit: '',
        name: item.name,
        order: 0,
        pantryItemId: item.id,
      ),
    );
    app.saveRecipe(r);
    return app.recipe(r.id)!;
  }

  group('grocery summaries', () {
    test('runningLow needs three planned meals drawing on an item', () {
      final butter = app.addPantryItem('Test butter');
      final monday = DateTime(2026, 9, 14);
      for (var i = 0; i < 2; i++) {
        app.setPlan(
          monday.add(Duration(days: i)),
          MealSlot.dinner,
          recipeUsing('Dish $i', butter).id,
        );
      }
      expect(app.runningLow(now: monday), isNot(contains(butter)));

      app.setPlan(
        monday.add(const Duration(days: 4)),
        MealSlot.dinner,
        recipeUsing('Dish 2', butter).id,
      );
      expect(app.runningLow(now: monday), contains(butter));

      // Already waiting on the list, so not suggested again.
      app.addGrocery('Test butter');
      expect(app.runningLow(now: monday), isNot(contains(butter)));
    });

    test('renaming a grocery drops the recipe it came from', () {
      app.library.groceries.clear();
      final pantry = app.addPantryItem('Test chicken');
      final g = app.addGrocery(
        'Test chicken',
        source: 'Katsu',
        pantryItemId: pantry.id,
      );

      // Case only: still the same thing the recipe asked for.
      app.renameGrocery(g.id, 'test Chicken');
      expect(g.sources, ['Katsu']);
      expect(g.pantryItemId, pantry.id);

      app.renameGrocery(g.id, 'Tofu');
      expect(g.name, 'Tofu');
      expect(g.sources, ['Added by hand']);
      expect(g.pantryItemId, isNull);
      expect(app.groceriesByRecipe(), isEmpty);
    });

    test('groceriesByRecipe counts lines per source, ignoring hand-added', () {
      app.library.groceries.clear();
      app.addGrocery('a', source: 'Katsu');
      app.addGrocery('b', source: 'Katsu');
      app.addGrocery('c', source: 'Curry');
      app.addGrocery('d');
      expect(app.groceriesByRecipe(), {'Katsu': 2, 'Curry': 1});
    });
  });

  testWidgets('pantry: add and remove another name', (tester) async {
    final item = app.addPantryItem('Chocolate chips');
    await pump(tester, MobilePantryItemPage(itemId: item.id));

    await tester.ensureVisible(find.text('＋ add'));
    await tester.tap(find.text('＋ add'));
    await drain(tester);
    await tester.enterText(find.byType(TextField).last, 'choc chips');
    await tester.tap(find.text('Add'));
    await drain(tester);
    expect(app.pantryItem(item.id)!.aliases, contains('choc chips'));

    await tester.ensureVisible(find.text('choc chips'));
    await tester.tap(find.text('choc chips'));
    await drain(tester);
    await tester.tap(find.text('Remove this name'));
    await drain(tester);
    expect(app.pantryItem(item.id)!.aliases, isNot(contains('choc chips')));
  });

  testWidgets('groceries: rename, then move into a new category', (
    tester,
  ) async {
    app.library.groceries.clear();
    final g = app.addGrocery('lemns');
    await pump(tester, const MobileGroceriesPage());

    await tester.longPress(find.text('lemns'));
    await drain(tester);
    await tester.tap(find.text('Rename…'));
    await drain(tester);
    await tester.enterText(find.byType(TextField).last, 'lemons');
    await tester.tap(find.text('Save'));
    await drain(tester);
    expect(app.library.groceries.single.name, 'lemons');

    await tester.longPress(find.text('lemons'));
    await drain(tester);
    await tester.tap(find.text('Move to another category…'));
    await drain(tester);
    await tester.tap(find.text('New category…'));
    await drain(tester);
    await tester.enterText(find.byType(TextField).last, 'Citrus');
    await tester.tap(find.text('Add'));
    await drain(tester);

    final citrus = app.aisles.singleWhere((a) => a.name == 'Citrus');
    expect(
      app.library.groceries.singleWhere((x) => x.id == g.id).aisleId,
      citrus.id,
    );
  });

  testWidgets('plan: move to an empty slot, then swap with a filled one', (
    tester,
  ) async {
    final today = app.dayOnly(DateTime.now());
    final a = app.library.recipes[0];
    final b = app.library.recipes[1];
    for (final slot in MealSlot.values) {
      app.clearPlan(today, slot);
    }
    app.setPlan(today, MealSlot.breakfast, a.id);
    app.setPlan(today, MealSlot.dinner, b.id);
    await pump(tester, const MobilePlanPage());

    Future<void> openMove(String title) async {
      final card = find.ancestor(
        of: find.text(title),
        matching: find.byType(InkWell),
      );
      await tester.tap(
        find.descendant(
          of: card.first,
          matching: find.byIcon(Icons.more_horiz),
        ),
      );
      await drain(tester);
      await tester.tap(find.text('Move or swap…'));
      await drain(tester);
    }

    await openMove(a.title);
    await tester.tap(find.text('Empty — move it here').first); // lunch
    await drain(tester);
    expect(app.planAt(today, MealSlot.breakfast), isNull);
    expect(app.planAt(today, MealSlot.lunch)!.recipeId, a.id);

    await openMove(a.title);
    await tester.tap(find.text('Swap with ${b.title}'));
    await drain(tester);
    expect(app.planAt(today, MealSlot.lunch)!.recipeId, b.id);
    expect(app.planAt(today, MealSlot.dinner)!.recipeId, a.id);
  });
}
