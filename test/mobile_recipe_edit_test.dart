import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/state/app_state.dart';
import 'package:recipe_book/theme/app_theme.dart';
import 'package:recipe_book/ui/mobile/mobile_recipe_edit.dart';

/// The phone editor over the shared controller: the layout's own duties.
///
/// The edit model itself is covered in recipe_edit_controller_test.dart;
/// these tests cover what the phone adds — reaching the mutations through
/// touch, and the two ways off the screen.
void main() {
  late Directory dir;
  late AppState app;
  late Recipe stored;

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
    r.components.add(cutlets);
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
    ]);
    r.steps.add(
      RecipeStep(id: newId(), componentId: cutlets.id, text: 'Fry', order: 0),
    );
    app.saveRecipe(r);
    return app.recipe(r.id)!;
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('rb_mobile_edit');
    app = AppState(directory: dir);
    await app.load();
    stored = buildStored();
  });

  tearDown(() async {
    await app.flush();
    dir.deleteSync(recursive: true);
  });

  /// Pumps a host with a button that pushes the editor, so popping the page
  /// is observable the way it is in the app.
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      MobileRecipeEditPage.open(context, stored.id),
                  child: const Text('edit'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('edit'));
    await tester.pumpAndSettle();
  }

  /// Runs any debounced disk write to completion, outside the fake-async zone.
  ///
  /// The store saves through a 350 ms debounce timer. A widget test body runs
  /// under FakeAsync, so if a pumpAndSettle lets that timer fire, the write's
  /// file IO starts in a zone whose microtasks stop running when the body
  /// ends — the write never completes, and every later save, including
  /// tearDown's flush, queues behind it forever. So every save a test
  /// triggers is drained straight away: a zero-length pump to run pending
  /// continuations, the flush under runAsync where real IO works, then the
  /// screen settles with no timer left to fire.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(app.flush);
    await tester.pumpAndSettle();
  }

  testWidgets('adds an ingredient through the open component', (tester) async {
    await open(tester);

    // The first component starts open.
    await tester.tap(find.text('Add an ingredient'));
    await tester.pumpAndSettle();

    // The new line is the last row carrying the ingredient-name hint. (The
    // last *empty* TextField on the page is the notes box, not this row.)
    final nameFields = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == 'ingredient',
    );
    await tester.enterText(nameFields.last, 'eggs');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await drain(tester);

    final names = app.recipe(stored.id)!.ingredients.map((i) => i.name);
    expect(names, contains('eggs'));
    expect(app.recipe(stored.id)!.ingredients, hasLength(3));
  });

  testWidgets('drags an ingredient into a new order', (tester) async {
    await open(tester);

    // The handles are ordered: two ingredient rows, then the step row.
    final handles = find.byIcon(Icons.drag_indicator);
    expect(handles, findsNWidgets(3));

    // Drag the first ingredient below the second. A timed drag, because the
    // reorder logic tracks the pointer frame by frame — an instant drag ends
    // before the list has seen it move.
    await tester.timedDrag(
      handles.first,
      const Offset(0, 100),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await drain(tester);

    final r = app.recipe(stored.id)!;
    expect(
      r.ingredientsOf(r.components.first.id).map((i) => i.name),
      ['panko', 'chicken breast'],
    );
  });

  testWidgets('saves an edited title and leaves', (tester) async {
    await open(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Chicken Katsu'),
      'Katsu Curry',
    );
    await tester.pump();
    await tester.tap(find.text('Save'));
    await drain(tester);

    // Popped back to the host, and the store took the edit.
    expect(find.text('edit'), findsOneWidget);
    expect(app.recipe(stored.id)!.title, 'Katsu Curry');
  });

  testWidgets('backing out dirty asks, and discarding keeps the store',
      (tester) async {
    await open(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Chicken Katsu'),
      'Never kept',
    );
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.text('Leave without saving?'), findsOneWidget);
    await tester.tap(find.text('Discard the changes'));
    await tester.pumpAndSettle();

    expect(find.text('edit'), findsOneWidget);
    expect(app.recipe(stored.id)!.title, 'Chicken Katsu');
  });

  testWidgets('backing out clean just leaves', (tester) async {
    await open(tester);
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(find.text('edit'), findsOneWidget);
  });

  testWidgets('a save over a synced change opens the review', (tester) async {
    await open(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Chicken Katsu'),
      'From the draft',
    );
    await tester.pump();

    // A sync lands mid-edit.
    final elsewhere = app.recipe(stored.id)!.copy()..title = 'From the sync';
    app.saveRecipe(elsewhere);
    await drain(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('This recipe changed while you were editing'),
      findsOneWidget,
    );

    await tester.tap(find.text('Keep my edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await drain(tester);

    expect(find.text('edit'), findsOneWidget);
    expect(app.recipe(stored.id)!.title, 'From the draft');
  });

  testWidgets('the review can also take the synced version', (tester) async {
    await open(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Chicken Katsu'),
      'From the draft',
    );
    await tester.pump();
    final elsewhere = app.recipe(stored.id)!.copy()..title = 'From the sync';
    app.saveRecipe(elsewhere);
    await drain(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take the synced one'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await drain(tester);

    expect(find.text('edit'), findsOneWidget);
    expect(app.recipe(stored.id)!.title, 'From the sync');
  });
}
