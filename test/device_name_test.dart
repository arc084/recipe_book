import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:recipe_book/state/app_state.dart';
import 'package:recipe_book/sync/sync_service.dart';
import 'package:recipe_book/theme/app_theme.dart';
import 'package:recipe_book/ui/mobile/mobile_plan.dart';
import 'package:recipe_book/ui/settings/settings_page.dart';
import 'package:recipe_book/ui/widgets/primitives.dart';

/// Two small things the phone and desktop share: which day the plan calls
/// today, and what this device is called on the other one.
void main() {
  late Directory dir;
  late AppState app;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('rb_device_name');
    app = AppState(directory: dir);
    await app.load();
  });

  tearDown(() async {
    await app.flush();
    dir.deleteSync(recursive: true);
  });

  Future<void> drain(WidgetTester tester) async {
    await tester.pump();
    await tester.runAsync(app.flush);
    await tester.pumpAndSettle();
  }

  group('renaming this device', () {
    test('takes a new name', () {
      expect(app.settings.deviceName, isNotEmpty);
      app.setDeviceName('Kitchen laptop');
      expect(app.settings.deviceName, 'Kitchen laptop');
    });

    test('trims, and refuses an empty one', () {
      app.setDeviceName('  Kitchen laptop  ');
      expect(app.settings.deviceName, 'Kitchen laptop');
      app.setDeviceName('   ');
      expect(app.settings.deviceName, 'Kitchen laptop');
    });

    test('survives a reload, and is not in the synced databases', () async {
      app.setDeviceName('Kitchen laptop');
      await app.flush();

      final reopened = AppState(directory: dir);
      await reopened.load();
      expect(reopened.settings.deviceName, 'Kitchen laptop');
      // settings.json is per-device; the library carries no device name.
      final library = File('${dir.path}/library.json').readAsStringSync();
      expect(library.contains('Kitchen laptop'), isFalse);
    });
  });

  testWidgets('Settings renames the device', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final sync = SyncService(app);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppState>.value(value: app),
          ChangeNotifierProvider<SyncService>.value(value: sync),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: SettingsPage()),
        ),
      ),
    );
    await drain(tester);

    expect(find.text('This device'), findsOneWidget);
    await tester.tap(find.widgetWithText(AppButton, 'Rename'));
    await drain(tester);

    await tester.enterText(find.byType(TextField).last, 'Kitchen laptop');
    await tester.tap(find.widgetWithText(AppButton, 'Save'));
    await drain(tester);

    expect(app.settings.deviceName, 'Kitchen laptop');
    expect(find.textContaining('Kitchen laptop'), findsWidgets);
  });

  testWidgets('the plan marks today wherever the strip sits', (tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: MobilePlanPage()),
        ),
      ),
    );
    await drain(tester);

    // Exactly one day in the strip is today, and it is today by the system
    // clock rather than by which day happens to be selected.
    expect(find.byKey(const Key('today-marker')), findsOneWidget);
    final todaysNumber = DateFormat('d').format(DateTime.now());
    expect(find.text(todaysNumber), findsWidgets);

    // Step to another week: nothing there is today.
    await tester.tap(find.byTooltip('Next week'));
    await drain(tester);
    expect(find.byKey(const Key('today-marker')), findsNothing);

    // And back again.
    await tester.tap(find.text('Back to today'));
    await drain(tester);
    expect(find.byKey(const Key('today-marker')), findsOneWidget);
  });
}
