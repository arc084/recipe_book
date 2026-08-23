import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/database.dart';
import 'package:recipe_book/data/migrations.dart';
import 'package:recipe_book/data/settings.dart';

void main() {
  test('a settings file with a byte-order mark still loads', () async {
    final dir = Directory.systemTemp.createTempSync('rb_bom');
    addTearDown(() => dir.deleteSync(recursive: true));

    // What every Windows editor and PowerShell 5.1's Out-File produce. A user
    // who opens settings.json in Notepad to check something and saves it would
    // hand the app exactly this.
    final f = File('${dir.path}${Platform.pathSeparator}settings.json');
    await f.writeAsString(
      '\uFEFF{"schema":1,"deviceId":"keep-me","themeMode":"dark"}',
    );

    final store = JsonStore<AppSettings>(
      fileName: 'settings.json',
      decode: AppSettings.fromJson,
      encode: (s) => s.toJson(),
      directory: dir,
    );

    final loaded = await store.load(
      MigrationContext(deviceId: '', now: DateTime.now().toUtc()),
    );

    // Silently losing this re-mints the device identity on every launch, which
    // for cloud sync means a fresh orphaned post in the user's folder each time.
    expect(loaded?.deviceId, 'keep-me');
  });
}
