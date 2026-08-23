import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/settings.dart';
import 'package:recipe_book/state/app_state.dart';

/// The autofill flag: on unless this device said otherwise, and remembered
/// across launches. Per-device on purpose — whether a device fills forms for
/// you is not something two devices need to agree on, so it lives in
/// settings.json and never syncs.
void main() {
  test('defaults on, including for settings saved before the flag existed', () {
    expect(AppSettings().autofillFromLabels, isTrue);
    expect(AppSettings.fromJson(const {}).autofillFromLabels, isTrue);
  });

  test('a device that turned it off stays off through the round trip', () {
    final s = AppSettings()..autofillFromLabels = false;
    expect(AppSettings.fromJson(s.toJson()).autofillFromLabels, isFalse);
  });

  test('the setter persists across a relaunch', () async {
    final dir = Directory.systemTemp.createTempSync('rb_autofill');
    try {
      final app = AppState(directory: dir);
      await app.load();
      app.setAutofillFromLabels(false);
      await app.flush();

      final relaunched = AppState(directory: dir);
      await relaunched.load();
      expect(relaunched.settings.autofillFromLabels, isFalse);
      await relaunched.flush();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
