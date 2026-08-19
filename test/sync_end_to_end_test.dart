import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/data/settings.dart';
import 'package:recipe_book/domain/sync/merge.dart';
import 'package:recipe_book/state/app_state.dart';
import 'package:recipe_book/sync/sync_client.dart';
import 'package:recipe_book/sync/sync_server.dart';
import 'package:recipe_book/sync/sync_service.dart';

/// Two whole apps talking over real sockets: pair with a six-digit code, then
/// exchange and merge. Everything here except the physical network is the code
/// that runs on the phone.
void main() {
  late Directory dirA;
  late Directory dirB;
  late AppState a;
  late AppState b;
  late SyncService hostSide;
  late SyncService joinSide;
  late SyncServer server;
  late Uri base;

  setUp(() async {
    dirA = Directory.systemTemp.createTempSync('rb_host');
    dirB = Directory.systemTemp.createTempSync('rb_join');
    a = AppState(directory: dirA);
    b = AppState(directory: dirB);
    await a.load();
    await b.load();
    a.settings.deviceName = 'Kitchen laptop';
    b.settings.deviceName = 'The phone';
    a.settings.conflictPolicy = ConflictPolicy.newestWins;
    b.settings.conflictPolicy = ConflictPolicy.newestWins;

    hostSide = SyncService(a);
    joinSide = SyncService(b);

    // Bound to loopback rather than the real interface, so the test never
    // touches the network it happens to be run on.
    server = SyncServer(hostSide);
    final port = await server.start(address: InternetAddress.loopbackIPv4);
    base = Uri.parse('http://127.0.0.1:$port');

    // Both start from the same baseline, as the adoption step establishes.
    final lib = '${dirA.path}${Platform.pathSeparator}l.json';
    final pan = '${dirA.path}${Platform.pathSeparator}p.json';
    await a.exportLibrary(lib);
    await a.exportPantry(pan);
    await b.adoptFrom(libraryPath: lib, pantryPath: pan);
  });

  tearDown(() async {
    await server.stop();
    await hostSide.stop();
    await joinSide.stop();
    await a.flush();
    await b.flush();
    dirA.deleteSync(recursive: true);
    dirB.deleteSync(recursive: true);
  });

  /// Pairs the phone to the laptop the way the two screens would.
  Future<PairedDevice> pair() async {
    final offer = server.openPairing();
    return joinSide.pairWith(base, offer.code);
  }

  test('pairing records the peer on both devices, with the same key', () async {
    final peer = await pair();

    expect(a.settings.devices.single.id, b.settings.deviceId);
    expect(b.settings.devices.single.id, a.settings.deviceId);
    // Derived independently on each side; it never crossed the wire.
    expect(a.settings.devices.single.psk, peer.psk);
    expect(a.settings.devices.single.name, 'The phone');
    expect(b.settings.devices.single.name, 'Kitchen laptop');
  });

  test('a wrong code leaves nothing paired', () async {
    final offer = server.openPairing();
    final wrong = offer.code == '000000' ? '111111' : '000000';

    await expectLater(
      () => joinSide.pairWith(base, wrong),
      throwsA(isA<SyncException>()),
    );
    expect(a.settings.devices, isEmpty);
    expect(b.settings.devices, isEmpty);
  });

  test('a recipe written on the phone reaches the laptop', () async {
    final peer = await pair();
    b.saveRecipe(
      Recipe(id: newId(), title: 'Miso Soup', mealTypeId: b.mealTypes.first.id),
    );

    await joinSide.syncWith(peer, base);

    // The phone pushed; the laptop merged what arrived.
    expect(a.library.recipes.any((r) => r.title == 'Miso Soup'), isTrue);
  });

  test('a recipe written on the laptop reaches the phone', () async {
    final peer = await pair();
    a.saveRecipe(
      Recipe(id: newId(), title: 'Congee', mealTypeId: a.mealTypes.first.id),
    );

    await joinSide.syncWith(peer, base);

    // The laptop's state came back in the same exchange.
    expect(b.library.recipes.any((r) => r.title == 'Congee'), isTrue);
  });

  test('one exchange settles edits made on both sides at once', () async {
    final peer = await pair();
    a.saveRecipe(
      Recipe(
        id: newId(),
        title: 'From laptop',
        mealTypeId: a.mealTypes.first.id,
      ),
    );
    b.saveRecipe(
      Recipe(
        id: newId(),
        title: 'From phone',
        mealTypeId: b.mealTypes.first.id,
      ),
    );

    await joinSide.syncWith(peer, base);

    for (final app in [a, b]) {
      expect(app.library.recipes.any((r) => r.title == 'From laptop'), isTrue);
      expect(app.library.recipes.any((r) => r.title == 'From phone'), isTrue);
    }
  });

  test('a deletion travels over the wire', () async {
    final peer = await pair();
    final victim = b.library.recipes.first.id;
    b.deleteRecipe(victim);

    await joinSide.syncWith(peer, base);

    expect(a.recipe(victim), isNull);
  });

  test('running out of something reaches the other device', () async {
    final peer = await pair();
    final item = b.pantry.items.firstWhere((p) => p.inStock);
    b.setInStock(item.id, false);

    await joinSide.syncWith(peer, base);

    expect(a.pantryItem(item.id)!.inStock, isFalse);
    expect(a.pantryItem(item.id)!.calories, item.calories);
  });

  test('a second sync with nothing in between changes nothing', () async {
    final peer = await pair();
    b.saveRecipe(
      Recipe(id: newId(), title: 'Once', mealTypeId: b.mealTypes.first.id),
    );
    await joinSide.syncWith(peer, base);

    final countA = a.library.recipes.length;
    final countB = b.library.recipes.length;

    final second = await joinSide.syncWith(peer, base);

    expect(second.received, 0);
    expect(a.library.recipes, hasLength(countA));
    expect(b.library.recipes, hasLength(countB));
  });

  test('the session is recorded against the device', () async {
    final peer = await pair();
    await joinSide.syncWith(peer, base);

    final recorded = b.settings.devices.single;
    expect(recorded.lastSync, isNotNull);
    expect(recorded.recipeCount, a.library.recipes.length);
    expect(recorded.libraryWatermark, isNotNull);
    expect(b.settings.lastSync, isNotNull);
  });

  test('a photograph follows its recipe by hash', () async {
    final peer = await pair();

    // A photo on the laptop, stored the way adopting one does.
    final source = File('${dirA.path}${Platform.pathSeparator}shot.jpg');
    await source.writeAsBytes(List<int>.generate(2048, (i) => i % 251));
    final recipe = a.library.recipes.first;
    await a.adoptRecipePhoto(recipe.id, source.path);
    final hash = a.recipe(recipe.id)!.photoHash;
    expect(hash, isNotNull);

    await joinSide.syncWith(peer, base);

    // The phone knows which picture it wants and has fetched the bytes; the
    // path is its own, because the laptop's path means nothing here.
    final onPhone = b.recipe(recipe.id)!;
    expect(onPhone.photoHash, hash);
    expect(onPhone.photoPath, isNotNull);
    expect(onPhone.photoPath, isNot(a.recipe(recipe.id)!.photoPath));
    expect(File(onPhone.photoPath!).existsSync(), isTrue);
  });

  test('a photographed recipe does not re-conflict on the next sync', () async {
    // The path differs between devices by construction, so comparing it would
    // make this recipe a conflict that could never be settled.
    final peer = await pair();
    final source = File('${dirA.path}${Platform.pathSeparator}s2.jpg');
    await source.writeAsBytes(List<int>.generate(512, (i) => i % 97));
    await a.adoptRecipePhoto(a.library.recipes.first.id, source.path);

    await joinSide.syncWith(peer, base);
    final again = await joinSide.syncWith(peer, base);

    expect(again.conflicts, 0);
    expect(again.received, 0);
  });

  test('ask pauses the session instead of choosing', () async {
    final peer = await pair();
    b.settings.conflictPolicy = ConflictPolicy.ask;

    final id = b.library.recipes.first.id;
    a.recipe(id)!.notes = 'laptop note';
    a.saveRecipe(a.recipe(id)!);
    b.recipe(id)!.notes = 'phone note';
    b.saveRecipe(b.recipe(id)!);

    final outcome = await joinSide.syncWith(peer, base);

    expect(outcome.conflicts, greaterThan(0));
    expect(joinSide.pendingConflicts, isNotEmpty);
    // Nothing was applied while the question stands.
    expect(b.recipe(id)!.notes, 'phone note');

    await joinSide.resolveWith({id: Resolution.takeRemote});
    expect(b.recipe(id)!.notes, 'laptop note');
    expect(joinSide.pendingConflicts, isEmpty);
  });

  test('what synced is still there after a restart', () async {
    final peer = await pair();
    b.saveRecipe(
      Recipe(id: newId(), title: 'Durable', mealTypeId: b.mealTypes.first.id),
    );
    await joinSide.syncWith(peer, base);
    await a.flush();

    final reopened = AppState(directory: dirA);
    await reopened.load();
    expect(reopened.library.recipes.any((r) => r.title == 'Durable'), isTrue);
    expect(reopened.settings.devices, hasLength(1));
    expect(reopened.settings.devices.single.psk, isNotNull);
  });
}
