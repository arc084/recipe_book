import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/state/app_state.dart';
import 'package:recipe_book/sync/cloud/cloud_folder.dart';
import 'package:recipe_book/sync/cloud/cloud_sync.dart';
import 'package:recipe_book/sync/cloud/device_post.dart';

/// Cloud sync end to end, with a temp directory standing in for the folder a
/// provider keeps in step. No network, no provider account, no phone — which is
/// the point of the folder-as-mailbox design.
void main() {
  late Directory dirA, dirB, dirC, cloudDir;
  late AppState a, b, c;
  late CloudFolder cloud;

  CloudSync syncFor(AppState app) => CloudSync(app, CloudFolder(cloudDir));

  setUp(() async {
    dirA = Directory.systemTemp.createTempSync('rb_cloud_a');
    dirB = Directory.systemTemp.createTempSync('rb_cloud_b');
    dirC = Directory.systemTemp.createTempSync('rb_cloud_c');
    cloudDir = Directory.systemTemp.createTempSync('rb_cloud_folder');
    cloud = CloudFolder(cloudDir);

    a = AppState(directory: dirA);
    b = AppState(directory: dirB);
    c = AppState(directory: dirC);
    await a.load();
    await b.load();
    await c.load();

    // Everyone starts from A's library, the way adopting a baseline does, so
    // the seeded corpora share ids instead of colliding as duplicates.
    final lib = '${dirA.path}${Platform.pathSeparator}lib.json';
    final pan = '${dirA.path}${Platform.pathSeparator}pan.json';
    await a.exportLibrary(lib);
    await a.exportPantry(pan);
    await b.adoptFrom(libraryPath: lib, pantryPath: pan);
    await c.adoptFrom(libraryPath: lib, pantryPath: pan);
  });

  tearDown(() async {
    // Saves are debounced, so a pending timer would fire into a directory that
    // no longer exists.
    await a.flush();
    await b.flush();
    await c.flush();
    for (final d in [dirA, dirB, dirC, cloudDir]) {
      d.deleteSync(recursive: true);
    }
  });

  group('the folder as a mailbox', () {
    test('each device writes only its own file', () async {
      await syncFor(a).run();
      await syncFor(b).run();

      final names = cloud.devices
          .listSync()
          .map((e) => e.path.split(Platform.pathSeparator).last)
          .toList();

      expect(names, hasLength(2));
      expect(names, contains('${a.settings.deviceId}.json'));
      expect(names, contains('${b.settings.deviceId}.json'));
      // No shared file means the provider is never asked to arbitrate, which
      // is the whole reason for this layout.
      expect(names, isNot(contains('library.json')));
    });

    test('an edit on one device reaches another', () async {
      final r = a.library.recipes.first;
      r.title = 'Chicken Katsu';
      a.saveRecipe(r);

      await syncFor(a).run();
      final outcome = await syncFor(b).run();

      expect(outcome.conflicts, 0);
      expect(b.recipe(r.id)!.title, 'Chicken Katsu');
    });

    test('three devices converge through one folder', () async {
      final fromA = a.library.recipes.first..title = 'Named on A';
      a.saveRecipe(fromA);
      await syncFor(a).run();

      await syncFor(b).run();
      final onB = b.addPantryItem('sumac');
      await syncFor(b).run();

      await syncFor(c).run();

      expect(c.recipe(fromA.id)!.title, 'Named on A');
      expect(c.pantryItem(onB.id), isNotNull, reason: 'B reached C via A');
    });

    test('syncing twice moves nothing the second time', () async {
      final r = a.library.recipes.first..title = 'Once';
      a.saveRecipe(r);
      await syncFor(a).run();
      await syncFor(b).run();

      final second = await syncFor(b).run();
      expect(second.received, 0);
      expect(second.conflicts, 0);
      expect(second.isEmpty, isTrue);
    });

    test('a delete propagates and stays deleted', () async {
      final id = a.library.recipes.first.id;
      a.deleteRecipe(id);

      await syncFor(a).run();
      await syncFor(b).run();
      expect(b.recipe(id), isNull);

      // The tombstone has to survive a round trip, or B's next post would
      // hand the recipe back to A as news.
      await syncFor(b).run();
      await syncFor(a).run();
      expect(a.recipe(id), isNull, reason: 'it must not come back');
    });
  });

  group('groceries and the meal plan', () {
    // These are in EntityKind and on the wire but had no coverage on either
    // transport, which is exactly where a bug would sit unnoticed.
    test('a grocery item crosses', () async {
      a.addGrocery('sumac', quantity: '1 jar');
      await syncFor(a).run();
      await syncFor(b).run();

      expect(
        b.library.groceries.where((g) => g.name == 'sumac'),
        hasLength(1),
      );
    });

    test('checking an item off crosses', () async {
      final item = a.addGrocery('capers');
      await syncFor(a).run();
      await syncFor(b).run();

      a.toggleGrocery(item.id);
      await syncFor(a).run();
      await syncFor(b).run();

      final onB = b.library.groceries.firstWhere((g) => g.id == item.id);
      expect(onB.checked, isTrue);
    });

    test('a planned meal crosses', () async {
      final day = DateTime.utc(2026, 8, 24);
      final recipeId = a.library.recipes.first.id;
      a.setPlan(day, MealSlot.dinner, recipeId);

      await syncFor(a).run();
      await syncFor(b).run();

      expect(b.planAt(day, MealSlot.dinner)?.recipeId, recipeId);
    });

    test('clearing a slot crosses', () async {
      final day = DateTime.utc(2026, 8, 25);
      a.setPlan(day, MealSlot.lunch, a.library.recipes.first.id);
      await syncFor(a).run();
      await syncFor(b).run();

      a.clearPlan(day, MealSlot.lunch);
      await syncFor(a).run();
      await syncFor(b).run();

      expect(b.planAt(day, MealSlot.lunch), isNull);
    });
  });

  group('a folder is not a database', () {
    test('a half-written post is skipped, not fatal', () async {
      await syncFor(a).run();
      // Exactly what a reader sees when another device is mid-write, or the
      // provider is mid-download.
      await File(
        '${cloud.devices.path}${Platform.pathSeparator}truncated.json',
      ).writeAsString('{"postVersion":1,"deviceId":"x","lib');

      final outcome = await syncFor(b).run();
      expect(outcome.skipped, hasLength(1));
      expect(outcome.skipped.single.fileName, 'truncated.json');
      // The good post still landed.
      expect(outcome.devicesRead, 1);
    });

    test('a post from a newer build is refused, not half-read', () async {
      await cloud.ensure();
      await File(
        '${cloud.devices.path}${Platform.pathSeparator}future.json',
      ).writeAsString(jsonEncode({'postVersion': kPostVersion + 1}));

      final outcome = await syncFor(b).run();
      expect(outcome.skipped, hasLength(1));
      expect(outcome.skipped.single.error, isA<PostTooNewException>());
    });

    test('a .part file is never read as a post', () async {
      await cloud.ensure();
      await File(
        '${cloud.devices.path}${Platform.pathSeparator}x.json.part',
      ).writeAsString('not json at all');

      final outcome = await syncFor(b).run();
      expect(outcome.skipped, isEmpty, reason: 'in-progress writes are ignored');
    });

    test('an unreachable folder is reported, not thrown', () async {
      final gone = Directory('${cloudDir.path}${Platform.pathSeparator}nope');
      final outcome = await CloudSync(a, CloudFolder(gone)).run();
      expect(outcome.unavailable, isTrue);
    });

    test('forgetting a device removes only its post', () async {
      await syncFor(a).run();
      await syncFor(b).run();
      await cloud.forget(a.settings.deviceId!);

      final read = await cloud.readOthers('nobody');
      expect(read.posts, hasLength(1));
      expect(read.posts.single.deviceId, b.settings.deviceId);
    });
  });

  group('device identity', () {
    test('survives a restart, so the folder does not fill with orphans',
        () async {
      final first = a.settings.deviceId;
      await a.flush();

      final again = AppState(directory: dirA);
      await again.load();

      expect(again.settings.deviceId, first);
      await again.flush();
    });
  });
}
