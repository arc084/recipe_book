import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:recipe_book/state/app_state.dart';
import 'package:recipe_book/theme/app_theme.dart';
import 'package:recipe_book/ui/settings/cloud_folder_section.dart';

/// The cloud section on its own: the desktop offer, and the Android relay.
/// Platform is driven through defaultTargetPlatform so the Android branch
/// runs on this Linux machine.
void main() {
  late Directory dir;
  late AppState app;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('rb_cloud_section');
    app = AppState(directory: dir);
    await app.load();
  });

  tearDown(() async {
    await app.flush();
    dir.deleteSync(recursive: true);
  });

  /// Runs [body] with [platform] as the target platform, restored before the
  /// test ends — the binding's invariant check runs before tearDowns, so an
  /// addTearDown reset is too late, and the override must outlive every
  /// rebuild [body] causes, so resetting right after pumping is too early.
  Future<void> onPlatform(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  Future<void> pump(WidgetTester tester) async {
    // The setUp load armed debounced saves; run them in the real zone before
    // fake-time pumps can fire them (see drain in mobile_recipe_edit_test).
    await tester.runAsync(app.flush);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(child: const CloudFolderSection()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a desktop with no folder chosen is offered the picker', (
    tester,
  ) async {
    // flutter_test forces defaultTargetPlatform to android whatever the
    // host, so the desktop branch needs saying out loud.
    await onPlatform(TargetPlatform.linux, () async {
      await pump(tester);
      expect(find.text('Choose a folder'), findsOneWidget);
    });
  });
}
