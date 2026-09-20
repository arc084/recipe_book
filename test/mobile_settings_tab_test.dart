import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:recipe_book/state/app_state.dart';
import 'package:recipe_book/state/nav.dart';
import 'package:recipe_book/sync/sync_service.dart';
import 'package:recipe_book/theme/app_theme.dart';
import 'package:recipe_book/ui/shell/mobile_shell.dart';

/// Settings as a tab of the phone's bar rather than a screen behind the
/// Library's chip.
void main() {
  late Directory dir;
  late AppState app;
  late NavController nav;
  late SyncService sync;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('rb_settings_tab');
    app = AppState(directory: dir);
    await app.load();
    nav = NavController();
    sync = SyncService(app);
  });

  tearDown(() async {
    await app.flush();
    dir.deleteSync(recursive: true);
  });

  Future<void> pumpShell(WidgetTester tester, {Size? size}) async {
    // A real phone's width, because the bar gained a fifth item and the point
    // is that five still fit.
    tester.view.physicalSize = size ?? const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<NavController>.value(value: nav),
          // Settings reports on pairing, so the shell needs this now too.
          // Held by the test rather than created by the provider: disposing
          // it as the widget goes lands mid-stop, which notifies afterwards.
          ChangeNotifierProvider<SyncService>.value(value: sync),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const MobileShell()),
      ),
    );
    await tester.pump();
    await tester.runAsync(app.flush);
    await tester.pumpAndSettle();
  }

  testWidgets('the bar carries Settings, and it opens the page', (
    tester,
  ) async {
    await pumpShell(tester);

    // Four tabs plus Settings, and the fifth is reachable without leaving the
    // bar. (The Library header's chip also says "Settings".)
    expect(find.text('Settings'), findsWidgets);

    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();

    expect(nav.tab, AppTab.settings);
    expect(find.textContaining('No account, no server'), findsOneWidget);
    // Still a tab, not a pushed screen: no back arrow.
    expect(find.byIcon(Icons.arrow_back), findsNothing);
  });

  testWidgets('the Library chip goes to the same tab', (tester) async {
    await pumpShell(tester);

    // The chip in the Library header, not the bar item below it.
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();

    expect(nav.tab, AppTab.settings);
    expect(find.textContaining('No account, no server'), findsOneWidget);
  });

  testWidgets('the bar still carries the other four', (tester) async {
    await pumpShell(tester);
    for (final label in ['Library', 'Pantry', 'Groceries', 'Plan']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });
}
