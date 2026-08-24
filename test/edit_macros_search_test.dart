import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/labels/label_lookup.dart';
import 'package:recipe_book/state/app_state.dart';
import 'package:recipe_book/theme/app_theme.dart';
import 'package:recipe_book/ui/pantry/edit_macros.dart';

/// The dialog's half of label search: nothing fires without a tap, every
/// state is told apart, and the one setting decides whether picking a result
/// writes the form or only shows the card.
void main() {
  late Directory dir;
  late AppState app;
  late PantryItem item;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('rb_macros_search');
    app = AppState(directory: dir);
    await app.load();
    item = PantryItem(id: newId(), name: 'digestives');
    app.savePantryItem(item);
  });

  tearDown(() async {
    await app.flush();
    dir.deleteSync(recursive: true);
  });

  /// A full reference, the shape the parser produces from a healthy answer.
  LabelReference biscuit() => const LabelReference(
    name: 'Chocolate Digestive',
    brand: "McVitie's",
    caloriesPer100g: 495,
    proteinPer100g: 6.7,
    fatPer100g: 23.9,
    carbsPer100g: 62.5,
    sugarPer100g: 29.4,
    servingAmount: 33,
    servingUnit: 'g',
    packAmount: 500,
    packUnit: 'g',
  );

  Future<void> openDialog(
    WidgetTester tester,
    Future<List<LabelReference>> Function(String terms) search,
  ) async {
    // setUp's savePantryItem armed a debounced save. Run it to completion in
    // the real zone before any fake-time pump can fire it — a save started
    // under fake async never finishes and wedges tearDown's flush; see the
    // drain comment in mobile_recipe_edit_test.dart.
    await tester.runAsync(app.flush);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => EditMacrosDialog(item: item, search: search),
                  ),
                  child: const Text('macros'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('macros'));
    await tester.pumpAndSettle();
  }

  testWidgets('nothing fires on open; a tap searches and lists results', (
    tester,
  ) async {
    var calls = 0;
    await openDialog(tester, (terms) async {
      calls++;
      expect(terms, 'digestives'); // seeded with the item's name
      return [biscuit()];
    });
    expect(calls, 0);

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.textContaining('Chocolate Digestive'), findsWidgets);
  });

  testWidgets('nothing found is said plainly', (tester) async {
    await openDialog(tester, (_) async => const []);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing found'), findsOneWidget);
  });

  testWidgets('a failure is shown in words, never as empty results', (
    tester,
  ) async {
    await openDialog(tester, (_) async {
      throw const LabelSearchException('The reference database answered 503.');
    });
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.textContaining('503'), findsOneWidget);
    expect(find.textContaining('Nothing found'), findsNothing);
  });

  testWidgets('picking a result fills the form when autofill is on', (
    tester,
  ) async {
    await openDialog(tester, (_) async => [biscuit()]);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Chocolate Digestive').first);
    await tester.pumpAndSettle();

    // The reference card and its note sit at the top, already on screen.
    expect(find.textContaining('Per 100 g'), findsOneWidget);
    expect(find.textContaining('Filled into the form'), findsOneWidget);
    // So does the serving row the fill wrote.
    expect(find.widgetWithText(TextField, '33'), findsOneWidget);

    // The rest of the form sits below the dialog's lazy viewport — the list
    // only builds what is visible, so scroll each field in before asserting,
    // in document order: pack, then the five values.
    final scrollable = find
        .descendant(of: find.byType(Dialog), matching: find.byType(Scrollable))
        .first;
    for (final value in ['500', '495', '6.7']) {
      final field = find.widgetWithText(TextField, value);
      await tester.scrollUntilVisible(field, 100, scrollable: scrollable);
      expect(field, findsOneWidget);
    }
  });

  testWidgets('with autofill off the card shows and the form is untouched', (
    tester,
  ) async {
    app.setAutofillFromLabels(false);
    await openDialog(tester, (_) async => [biscuit()]);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Chocolate Digestive').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('Per 100 g'), findsOneWidget);
    expect(find.textContaining('Autofill is off'), findsOneWidget);

    // findsNothing over a lazy list proves nothing — scroll the calories
    // field into existence, then show it stayed empty.
    final scrollable = find
        .descendant(of: find.byType(Dialog), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      find.text('Calories'),
      100,
      scrollable: scrollable,
    );
    expect(find.widgetWithText(TextField, '495'), findsNothing);
    expect(find.widgetWithText(TextField, '33'), findsNothing);
  });
}
