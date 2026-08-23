import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/state/app_state.dart';
import 'package:recipe_book/ui/recipe/recipe_edit_controller.dart';

/// The edit model on its own — no widgets, no layout, either platform.
///
/// Everything here is behaviour the desktop and the phone must agree on,
/// which is the reason the controller exists.
void main() {
  late Directory dir;
  late AppState app;
  late Recipe stored;

  /// A two-component recipe, saved and restamped by the store, the way any
  /// recipe looks by the time an editor opens it.
  Recipe buildStored() {
    final r = Recipe(
      id: newId(),
      title: 'Chicken Katsu',
      mealTypeId: 'unused',
      servings: 2,
    );
    final cutlets = RecipeComponent(
      id: newId(),
      recipeId: r.id,
      name: 'Cutlets',
      order: 0,
    );
    final sauce = RecipeComponent(
      id: newId(),
      recipeId: r.id,
      name: 'Sauce',
      order: 1,
    );
    r.components.addAll([cutlets, sauce]);
    r.ingredients.addAll([
      Ingredient(
        id: newId(),
        componentId: cutlets.id,
        quantity: 400,
        unit: 'g',
        name: 'chicken breast',
        order: 0,
      ),
      Ingredient(
        id: newId(),
        componentId: cutlets.id,
        quantity: 100,
        unit: 'g',
        name: 'panko',
        order: 1,
      ),
      Ingredient(
        id: newId(),
        componentId: cutlets.id,
        quantity: 2,
        unit: '',
        name: 'eggs',
        order: 2,
      ),
      Ingredient(
        id: newId(),
        componentId: sauce.id,
        quantity: 3,
        unit: 'tbsp',
        name: 'ketchup',
        order: 0,
      ),
    ]);
    r.steps.addAll([
      RecipeStep(id: newId(), componentId: cutlets.id, text: 'Flatten', order: 0),
      RecipeStep(id: newId(), componentId: cutlets.id, text: 'Bread', order: 1),
      RecipeStep(id: newId(), componentId: cutlets.id, text: 'Fry', order: 2),
      RecipeStep(id: newId(), componentId: sauce.id, text: 'Stir', order: 0),
    ]);
    app.saveRecipe(r);
    return app.recipe(r.id)!;
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('rb_edit_ctrl');
    app = AppState(directory: dir);
    await app.load();
    stored = buildStored();
  });

  tearDown(() async {
    await app.flush();
    dir.deleteSync(recursive: true);
  });

  group('the draft', () {
    test('is a deep copy — editing it leaves the stored recipe alone', () {
      final c = RecipeEditController(stored);
      c.change(() => c.draft.title = 'Renamed');
      c.draft.ingredients.first.name = 'poked directly';

      expect(app.recipe(stored.id)!.title, 'Chicken Katsu');
      expect(app.recipe(stored.id)!.ingredients.first.name, 'chicken breast');
    });

    test('starts clean and marks dirty on any change', () {
      final c = RecipeEditController(stored);
      expect(c.isDirty, isFalse);
      c.change(() => c.draft.notes = 'crispier next time');
      expect(c.isDirty, isTrue);
    });

    test('notifies listeners on every mutation', () {
      final c = RecipeEditController(stored);
      var notified = 0;
      c.addListener(() => notified++);
      c.change(() => c.draft.title = 'A');
      c.addComponent('Garnish');
      c.addIngredient(c.draft.components.first.id);
      expect(notified, 3);
    });

    test('counts changed fields the way the footer states them', () {
      final c = RecipeEditController(stored);
      expect(c.changeCount, 0);
      c.change(() => c.draft.title = 'Renamed');
      c.change(() => c.draft.servings = 4);
      c.change(() => c.draft.ingredients.first.name = 'thigh');
      expect(c.changeCount, 3);
    });
  });

  group('structural edits', () {
    test('addComponent appends in order and carries the recipe id', () {
      final c = RecipeEditController(stored);
      final added = c.addComponent('Garnish');
      expect(added.recipeId, stored.id);
      expect(c.draft.orderedComponents.last.id, added.id);
      expect(c.isDirty, isTrue);
    });

    test('removeComponent takes its ingredients and steps with it', () {
      final c = RecipeEditController(stored);
      final cutlets = c.draft.orderedComponents.first;
      c.removeComponent(cutlets.id);

      expect(c.draft.components, hasLength(1));
      expect(
        c.draft.ingredients.where((i) => i.componentId == cutlets.id),
        isEmpty,
      );
      expect(c.draft.steps.where((s) => s.componentId == cutlets.id), isEmpty);
      // The other component is untouched.
      expect(c.draft.ingredients, hasLength(1));
      expect(c.draft.steps, hasLength(1));
    });

    test('an added ingredient keeps quantity, unit and name as three fields',
        () {
      final c = RecipeEditController(stored);
      final line = c.addIngredient(c.draft.orderedComponents.first.id);
      c.change(() {
        line.quantity = 400;
        line.unit = 'g';
        line.name = 'canned tomatoes';
      });
      c.saveAnyway(app);

      final saved = app
          .recipe(stored.id)!
          .ingredients
          .where((i) => i.id == line.id)
          .first;
      // Never collapsed into one string — scaling and pantry matching
      // depend on the three staying apart.
      expect(saved.quantity, 400);
      expect(saved.unit, 'g');
      expect(saved.name, 'canned tomatoes');
    });

    test('removeIngredient and removeStep drop exactly the one line', () {
      final c = RecipeEditController(stored);
      final gone = c.draft.ingredients[1];
      c.removeIngredient(gone.id);
      expect(c.draft.ingredients.where((i) => i.id == gone.id), isEmpty);
      expect(c.draft.ingredients, hasLength(3));

      final step = c.draft.steps[1];
      c.removeStep(step.id);
      expect(c.draft.steps.where((s) => s.id == step.id), isEmpty);
      expect(c.draft.steps, hasLength(3));
    });
  });

  group('reordering', () {
    test('moves a line within its component and renumbers from zero', () {
      final c = RecipeEditController(stored);
      final cutlets = c.draft.orderedComponents.first;

      c.reorderIngredient(cutlets.id, 0, 2);

      final names = c.draft.ingredientsOf(cutlets.id).map((i) => i.name);
      expect(names, ['panko', 'eggs', 'chicken breast']);
      expect(
        c.draft.ingredientsOf(cutlets.id).map((i) => i.order),
        [0, 1, 2],
      );
      expect(c.isDirty, isTrue);
    });

    test('leaves the other component alone', () {
      final c = RecipeEditController(stored);
      final cutlets = c.draft.orderedComponents.first;
      final sauce = c.draft.orderedComponents.last;

      c.reorderIngredient(cutlets.id, 2, 0);

      expect(c.draft.ingredientsOf(sauce.id).single.name, 'ketchup');
      expect(c.draft.ingredientsOf(sauce.id).single.order, 0);
    });

    test('reorders steps and the numbering follows', () {
      final c = RecipeEditController(stored);
      final cutlets = c.draft.orderedComponents.first;

      c.reorderStep(cutlets.id, 2, 0);

      expect(
        c.draft.stepsOf(cutlets.id).map((s) => s.text),
        ['Fry', 'Flatten', 'Bread'],
      );
      // Continuous numbering across components reads off orderedSteps.
      expect(
        c.draft.orderedSteps.map((s) => s.text),
        ['Fry', 'Flatten', 'Bread', 'Stir'],
      );
    });

    test('an out-of-range move is ignored, an over-long target clamps', () {
      final c = RecipeEditController(stored);
      final cutlets = c.draft.orderedComponents.first;
      final before = c.draft.ingredientsOf(cutlets.id).map((i) => i.name);

      c.reorderIngredient(cutlets.id, 9, 0);
      expect(c.draft.ingredientsOf(cutlets.id).map((i) => i.name), before);

      c.reorderIngredient(cutlets.id, 0, 9);
      expect(
        c.draft.ingredientsOf(cutlets.id).last.name,
        'chicken breast',
      );
    });
  });

  group('saving', () {
    test('writes the draft and comes back saved when nothing moved', () {
      final c = RecipeEditController(stored);
      c.change(() => c.draft.title = 'Renamed');

      expect(c.save(app), SaveOutcome.saved);
      expect(app.recipe(stored.id)!.title, 'Renamed');
      expect(c.isDirty, isFalse);
    });

    test('a save advances the stored stamp past the one it opened from', () {
      final c = RecipeEditController(stored);
      c.change(() => c.draft.title = 'Renamed');
      c.save(app);
      expect(app.recipe(stored.id)!.stamp > c.openedFrom, isTrue);
    });

    test('refuses when the stored recipe moved while the draft was open', () {
      final c = RecipeEditController(stored);
      c.change(() => c.draft.title = 'From the draft');

      // A sync lands mid-edit: someone else's version of the same recipe.
      final elsewhere = app.recipe(stored.id)!.copy()..title = 'From the sync';
      app.saveRecipe(elsewhere);

      expect(c.save(app), SaveOutcome.stale);
      // Refusing means refusing: the store still holds the other edit.
      expect(app.recipe(stored.id)!.title, 'From the sync');
    });

    test('refuses when the recipe was deleted while the draft was open', () {
      final c = RecipeEditController(stored);
      c.change(() => c.draft.title = 'Editing a ghost');
      app.deleteRecipe(stored.id);

      expect(c.save(app), SaveOutcome.stale);
      expect(app.recipe(stored.id), isNull);
    });

    test('saveAnyway is the keep-mine answer to a stale save', () {
      final c = RecipeEditController(stored);
      c.change(() => c.draft.title = 'From the draft');
      final elsewhere = app.recipe(stored.id)!.copy()..title = 'From the sync';
      app.saveRecipe(elsewhere);

      expect(c.save(app), SaveOutcome.stale);
      c.saveAnyway(app);
      expect(app.recipe(stored.id)!.title, 'From the draft');
    });

    test('discard leaves the store exactly as it was', () {
      final c = RecipeEditController(stored);
      c.change(() => c.draft.title = 'Never kept');
      final stampBefore = app.recipe(stored.id)!.stamp;

      c.discard();

      expect(c.isDirty, isFalse);
      expect(app.recipe(stored.id)!.title, 'Chicken Katsu');
      expect(app.recipe(stored.id)!.stamp, stampBefore);
    });
  });
}
