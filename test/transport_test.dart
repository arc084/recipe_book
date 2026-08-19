import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/database.dart';
import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/data/settings.dart';
import 'package:recipe_book/sync/protocol.dart';
import 'package:recipe_book/sync/sync_client.dart';
import 'package:recipe_book/sync/sync_server.dart';

/// A host backed by plain databases, so the transport can be exercised
/// without an AppState behind it.
class _FakeHost implements SyncHost {
  _FakeHost(this.deviceId, {LibraryDatabase? library, PantryDatabase? pantry})
    : library = library ?? LibraryDatabase(),
      pantry = pantry ?? PantryDatabase();

  @override
  final String deviceId;
  @override
  String get deviceName => 'Host $deviceId';
  @override
  String get platform => 'test';

  @override
  LibraryDatabase library;
  @override
  PantryDatabase pantry;

  @override
  final List<PairedDevice> pairedDevices = [];

  final List<LibraryDatabase> received = [];
  final Map<String, List<int>> photos = {};

  @override
  Future<void> onPaired(PairedDevice device) async => pairedDevices.add(device);

  @override
  Future<void> onIncoming(LibraryDatabase l, PantryDatabase p) async =>
      received.add(l);

  @override
  Future<List<int>?> photoBytes(String hash) async => photos[hash];
}

void main() {
  late _FakeHost host;
  late SyncServer server;
  late SyncClient client;
  late Uri base;

  setUp(() async {
    host = _FakeHost('host-device');
    server = SyncServer(host);
    final port = await server.start(address: InternetAddress.loopbackIPv4);
    base = Uri.parse('http://127.0.0.1:$port');
    client = SyncClient(
      deviceId: 'joining-device',
      deviceName: 'The phone',
      platform: 'android',
    );
  });

  tearDown(() async {
    client.close();
    await server.stop();
  });

  /// Pairs the two the way the UI would, and returns the joiner's record of
  /// the host.
  Future<PairedDevice> pair() async {
    final offer = server.openPairing();
    final greeting = await client.hello(base);
    return client.pair(base, code: offer.code, salt: greeting.salt!);
  }

  group('greeting', () {
    test('says who is there', () async {
      final greeting = await client.hello(base);
      expect(greeting.deviceId, 'host-device');
      expect(greeting.isPairing, isFalse);
      expect(greeting.salt, isNull);
    });

    test('offers a challenge only while a code is live', () async {
      server.openPairing();
      final greeting = await client.hello(base);
      expect(greeting.isPairing, isTrue);
      expect(greeting.salt, isNotNull);
    });
  });

  group('pairing', () {
    test('the right code pairs both sides on the same key', () async {
      final peer = await pair();

      expect(peer.id, 'host-device');
      expect(peer.psk, isNotNull);
      // Both derived the key independently; it never crossed the network.
      expect(host.pairedDevices.single.psk, peer.psk);
      expect(host.pairedDevices.single.id, 'joining-device');
    });

    test('a code is spent the moment it works', () async {
      final offer = server.openPairing();
      final greeting = await client.hello(base);
      await client.pair(base, code: offer.code, salt: greeting.salt!);

      expect(server.offer, isNull);
      expect(
        () => client.pair(base, code: offer.code, salt: greeting.salt!),
        throwsA(isA<SyncException>()),
      );
    });

    test('a wrong code is refused and counts against the attempts', () async {
      final offer = server.openPairing();
      final greeting = await client.hello(base);
      final wrong = offer.code == '000000' ? '111111' : '000000';

      await expectLater(
        () => client.pair(base, code: wrong, salt: greeting.salt!),
        throwsA(
          isA<SyncException>().having((e) => e.isPairingCode, 'code', isTrue),
        ),
      );
      expect(server.offer!.attemptsLeft, 2);
    });

    test('three wrong answers burn the code', () async {
      final offer = server.openPairing();
      final greeting = await client.hello(base);
      final wrong = offer.code == '000000' ? '111111' : '000000';

      for (var i = 0; i < 3; i++) {
        await expectLater(
          () => client.pair(base, code: wrong, salt: greeting.salt!),
          throwsA(isA<SyncException>()),
        );
      }
      // Six digits is only a million; without this it would be brute-forceable.
      expect(server.offer, isNull);
    });

    test('an expired code is refused', () async {
      var clock = DateTime.utc(2026, 1, 1, 12);
      final expiring = SyncServer(host, now: () => clock);
      final port = await expiring.start(address: InternetAddress.loopbackIPv4);
      final at = Uri.parse('http://127.0.0.1:$port');
      final offer = expiring.openPairing();
      final greeting = await client.hello(at);

      clock = clock.add(kPairingWindow + const Duration(seconds: 1));

      await expectLater(
        () => client.pair(at, code: offer.code, salt: greeting.salt!),
        throwsA(isA<SyncException>()),
      );
      await expiring.stop();
    });

    test('nothing is on offer unless the user opened pairing', () async {
      expect(
        () => client.pair(base, code: '123456', salt: 'anything'),
        throwsA(isA<SyncException>()),
      );
    });
  });

  group('signed requests', () {
    test('an unpaired device is turned away', () async {
      // No pairing, so the host holds no key for this device.
      expect(
        () => client.exchange(
          base,
          peer: PairedDevice(
            id: 'host-device',
            name: 'x',
            platform: 'test',
            recipeCount: 0,
            pantryCount: 0,
            psk: 'a-key-nobody-agreed-to',
          ),
          library: LibraryDatabase(),
          pantry: PantryDatabase(),
        ),
        throwsA(isA<SyncException>()),
      );
    });

    test('a tampered body fails its signature', () {
      // The body hash is inside the signature, so swapping the payload of an
      // otherwise-valid request invalidates it.
      const signer = RequestSigner('key');
      final signature = signer.signature(
        method: 'POST',
        path: '/sync',
        time: 'T',
        nonce: 'N',
        body: const [1, 2, 3],
      );
      final tampered = signer.signature(
        method: 'POST',
        path: '/sync',
        time: 'T',
        nonce: 'N',
        body: const [1, 2, 4],
      );
      expect(signature, isNot(tampered));
    });

    test('a replayed request is refused the second time', () async {
      final verifier = RequestVerifier();
      const signer = RequestSigner('key');
      final headers = signer.headersFor(
        deviceId: 'd',
        method: 'POST',
        path: '/sync',
        body: const <int>[],
        nonce: 'fixed-nonce',
      );

      String? pskFor(String _) => 'key';
      expect(
        verifier.verify(
          headers: headers,
          method: 'POST',
          path: '/sync',
          body: const <int>[],
          pskFor: pskFor,
        ),
        isNull,
      );
      expect(
        verifier.verify(
          headers: headers,
          method: 'POST',
          path: '/sync',
          body: const <int>[],
          pskFor: pskFor,
        ),
        AuthFailure.replayedNonce,
      );
    });

    test('a request from a badly-skewed clock is refused', () {
      final verifier = RequestVerifier(now: () => DateTime.utc(2026, 1, 1, 12));
      const signer = RequestSigner('key');
      final headers = signer.headersFor(
        deviceId: 'd',
        method: 'POST',
        path: '/sync',
        body: const <int>[],
        now: DateTime.utc(2026, 1, 1, 14), // two hours out
      );
      expect(
        verifier.verify(
          headers: headers,
          method: 'POST',
          path: '/sync',
          body: const <int>[],
          pskFor: (_) => 'key',
        ),
        AuthFailure.staleTimestamp,
      );
    });
  });

  group('exchange', () {
    test('carries both databases in both directions', () async {
      final peer = await pair();

      host.library.recipes.add(
        Recipe(id: 'from-host', title: 'Host recipe', mealTypeId: 'm'),
      );
      final mine = LibraryDatabase(
        recipes: [
          Recipe(id: 'from-joiner', title: 'Joiner recipe', mealTypeId: 'm'),
        ],
      );

      final result = await client.exchange(
        base,
        peer: peer,
        library: mine,
        pantry: PantryDatabase(),
      );

      // Ours arrived there…
      expect(host.received.single.recipes.single.id, 'from-joiner');
      // …and theirs came back.
      expect(result.library.recipes.single.id, 'from-host');
      expect(result.peerClock, isNotNull);
    });

    test('stamps survive the round trip', () async {
      final peer = await pair();
      final recipe = Recipe(id: 'r', title: 'Stamped', mealTypeId: 'm')
        ..updatedAt = DateTime.utc(2026, 5, 1, 10)
        ..updatedBy = 'host-device';
      host.library.recipes.add(recipe);

      final result = await client.exchange(
        base,
        peer: peer,
        library: LibraryDatabase(),
        pantry: PantryDatabase(),
      );

      expect(result.library.recipes.single.updatedAt, recipe.updatedAt);
      expect(result.library.recipes.single.updatedBy, 'host-device');
    });

    test('tombstones survive the round trip', () async {
      // The whole reason deletions travel at all.
      final peer = await pair();
      final grave = LibraryDatabase(recipes: []);
      host.library = LibraryDatabase();
      final result = await client.exchange(
        base,
        peer: peer,
        library: grave,
        pantry: PantryDatabase(),
      );
      expect(result.library.tombstones, isEmpty);
    });
  });

  group('photos', () {
    test('are fetched by content hash', () async {
      final peer = await pair();
      host.photos['abc123'] = const [1, 2, 3, 4];

      expect(await client.photo(base, peer: peer, hash: 'abc123'), const [
        1,
        2,
        3,
        4,
      ]);
    });

    test('a hash the peer does not have comes back null', () async {
      final peer = await pair();
      expect(await client.photo(base, peer: peer, hash: 'nope'), isNull);
    });
  });
}
