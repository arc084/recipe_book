import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/state/app_state.dart';
import 'package:recipe_book/theme/app_theme.dart';
import 'package:recipe_book/ui/mobile/mobile_pantry.dart';

/// The pantry's three corrections: Pantry leads the groups, one ingredient is
/// one row, and stock is a double tap rather than a screen.
void main() {
  late Directory dir;
  late AppState app;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('rb_pantry_polish');
    app = AppState(directory: dir);
    await app.load();
    // The seeded pantry holds forty-odd ingredients, basil and butter among
    // them; these tests want to know exactly what is on screen.
    app.pantry.items.clear();
  });

  tearDown(() async {
    await app.flush();
    dir.deleteSync(recursive: true);
  });

  /// See mobile_parity_test.dart: a widget test that saves has to run the
  /// debounced write outside the fake-async zone or everything after it hangs.
  Future<void> drain(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(app.flush);
    await tester.pumpAndSettle();
  }

  Future<void> pumpPantry(WidgetTester tester) async {
    // Wide, because the test font draws every glyph as a full em square.
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(app.flush);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MobilePantryPage()),
        ),
      ),
    );
    await drain(tester);
  }

  test('Pantry is the first group the screens list', () {
    expect(PantryGroup.values.first, PantryGroup.pantry);
    // The stored value is the name, so the order is free to change.
    expect(PantryGroup.parse('fridge'), PantryGroup.fridge);
  });

  group('one ingredient, one row', () {
    test('adding a name already in the pantry returns that item', () {
      final first = app.addPantryItem('Chocolate chips');
      final again = app.addPantryItem('chocolate chips  ');
      expect(again.id, first.id);
      expect(
        app.pantry.items.where((i) => i.matchesName('Chocolate chips')),
        hasLength(1),
      );
    });

    test('an alias counts as the same ingredient', () {
      final item = app.addPantryItem('Chocolate chips');
      app.addAlias(item.id, 'choc chips');
      expect(app.addPantryItem('choc chips').id, item.id);
    });

    test('a different ingredient is still its own row', () {
      final a = app.addPantryItem('Chocolate chips');
      final b = app.addPantryItem('Chocolate');
      expect(b.id, isNot(a.id));
    });
  });

  testWidgets('the box searches and ＋ adds', (tester) async {
    app.addPantryItem('Basil');
    app.addPantryItem('Butter');
    await pumpPantry(tester);

    expect(find.text('Basil'), findsOneWidget);
    expect(find.text('Butter'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'bas');
    await drain(tester);
    expect(find.text('Basil'), findsOneWidget);
    expect(find.text('Butter'), findsNothing);

    // Nothing matching says so, and ＋ is the way out of it.
    await tester.enterText(find.byType(TextField).first, 'oregano');
    await drain(tester);
    expect(find.textContaining('Nothing here called'), findsOneWidget);

    await tester.tap(find.text('＋'));
    await drain(tester);
    expect(
      app.pantry.items.where((i) => i.matchesName('oregano')),
      hasLength(1),
    );
    // And opens it, as adding always has.
    expect(find.text('ALSO KNOWN AS'), findsOneWidget);
  });

  testWidgets('＋ on a name already there opens it rather than repeating it', (
    tester,
  ) async {
    final basil = app.addPantryItem('Basil');
    await pumpPantry(tester);

    await tester.enterText(find.byType(TextField).first, 'basil');
    await drain(tester);
    await tester.tap(find.text('＋'));
    await drain(tester);

    expect(app.pantry.items.where((i) => i.matchesName('Basil')), hasLength(1));
    expect(find.text('Basil is already in your pantry'), findsOneWidget);
    expect(app.pantryItem(basil.id), isNotNull);
  });

  testWidgets('double-tapping a chip marks it run out, and back', (
    tester,
  ) async {
    final basil = app.addPantryItem('Basil');
    await pumpPantry(tester);

    // The chip, not the "needs macros" banner above it, which names the same
    // item.
    final chip = find.descendant(
      of: find.byType(LongPressDraggable<String>),
      matching: find.text('Basil'),
    );

    Future<void> doubleTap() async {
      await tester.tap(chip);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(chip);
      await drain(tester);
    }

    await doubleTap();
    expect(app.pantryItem(basil.id)!.inStock, isFalse);

    await doubleTap();
    expect(app.pantryItem(basil.id)!.inStock, isTrue);
    // Never left the pantry screen for either of them.
    expect(find.text('ALSO KNOWN AS'), findsNothing);
  });
}
