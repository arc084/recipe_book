import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/database.dart';
import 'package:recipe_book/data/migrations.dart';
import 'package:recipe_book/state/app_state.dart';

/// Overlapping writes to one store.
///
/// Every save writes `<file>.tmp` and renames it into place. Two writers at
/// once therefore race on the same `.tmp`: the first rename takes the file,
/// the second finds nothing to rename and throws. The store queues saves so
/// this cannot happen — found the honest way, by a first-run `load()` whose
/// fire-and-forget seed save was still in flight when `flush()` started.
void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('rb_store'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('flush straight after a first-run load does not lose the race', () async {
    final app = AppState(directory: dir);
    await app.load();
    // The seed save is still in flight here. This used to throw
    // PathNotFoundException out of the second rename.
    await app.flush();

    expect(File('${dir.path}/library.json').existsSync(), isTrue);
    expect(File('${dir.path}/pantry.json').existsSync(), isTrue);
  });

  test('a burst of concurrent saves lands the last value', () async {
    final store = JsonStore<Map<String, dynamic>>(
      fileName: 'burst.json',
      decode: (j) => j,
      encode: (v) => v,
      directory: dir,
    );

    await Future.wait([
      for (var i = 1; i <= 20; i++) store.save({'n': i}),
    ]);

    final kept = await store.load(
      MigrationContext(deviceId: 'test', now: DateTime.now().toUtc()),
    );
    expect(kept?['n'], 20);
  });
}
