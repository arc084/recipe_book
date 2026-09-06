import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/state/app_state.dart';
import 'package:recipe_book/theme/app_theme.dart';
import 'package:recipe_book/ui/cook/cook_mode.dart';

/// The confirmation card is cook mode's signal that a spoken word was heard
/// correctly, so it is only worth anything while it stays rare and true. A
/// button press is not a spoken word and must not claim to be one.
Recipe _recipe() => Recipe(
  id: 'r1',
  title: 'Onion soup',
  mealTypeId: 'm1',
  components: [
    RecipeComponent(id: 'c1', recipeId: 'r1', name: 'Soup', order: 0),
  ],
  steps: [
    RecipeStep(
      id: 's1',
      componentId: 'c1',
      text: 'Slice the onions.',
      order: 0,
    ),
    RecipeStep(
      id: 's2',
      componentId: 'c1',
      text: 'Sweat them slowly.',
      order: 1,
    ),
    RecipeStep(id: 's3', componentId: 'c1', text: 'Add the stock.', order: 2),
  ],
);

/// The library is filled in directly rather than through [AppState.saveRecipe],
/// which would leave a debounced write pending on a real directory.
Future<AppState> _pumpCookMode(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final app = AppState();
  app.library.recipes.add(_recipe());

  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: const CookModeScreen(recipeId: 'r1'),
      ),
    ),
  );
  await tester.pump();
  // Disposes the screen so its ticker does not outlive the test.
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  return app;
}

/// The card is the only thing wearing either of these icons.
Finder get _card => find.byWidgetPredicate(
  (w) =>
      w is Icon &&
      (w.icon == Icons.graphic_eq || w.icon == Icons.keyboard_outlined),
);

void main() {
  group('cook mode confirmation card', () {
    testWidgets('a button press says nothing about hearing', (tester) async {
      await _pumpCookMode(tester);

      await tester.tap(find.text('Next'));
      await tester.pump();
      expect(find.textContaining('Heard'), findsNothing);
      expect(_card, findsNothing);
      expect(find.text('Step 2 of 3'), findsOneWidget);

      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(find.textContaining('Heard'), findsNothing);
      expect(find.text('Step 1 of 3'), findsOneWidget);

      await tester.tap(find.text('Start a timer'));
      await tester.pump();
      expect(find.textContaining('Heard'), findsNothing);
      expect(_card, findsNothing);
    });

    testWidgets(
      'a key press echoes the key without claiming to have heard it',
      (tester) async {
        await _pumpCookMode(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(find.text('space / → — moved to step 2'), findsOneWidget);
        expect(find.textContaining('Heard'), findsNothing);
        expect(_card, findsOneWidget);
      },
    );
  });
}
