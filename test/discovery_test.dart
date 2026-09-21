import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/sync/discovery.dart';
import 'package:recipe_book/sync/protocol.dart';
import 'package:recipe_book/data/database.dart';
import 'package:recipe_book/data/settings.dart';
import 'package:recipe_book/sync/sync_server.dart';

/// Enough of a host for a server that never serves a request here.
class _FakeHost implements SyncHost {
  @override
  String get deviceId => 'host';
  @override
  String get deviceName => 'Host';
  @override
  String get platform => 'test';
  @override
  LibraryDatabase library = LibraryDatabase();
  @override
  PantryDatabase pantry = PantryDatabase();
  @override
  final List<PairedDevice> pairedDevices = [];
  @override
  Future<void> onPaired(PairedDevice device) async {}
  @override
  Future<List<String>> missingPhotoHashes() async => const [];
  @override
  Future<void> storePhoto(String hash, List<int> bytes) async {}
  @override
  Future<void> onIncoming(
    LibraryDatabase l,
    PantryDatabase p,
    String fromDeviceId,
  ) async {}
  @override
  Future<List<int>?> photoBytes(String hash) async => null;
}

/// What a device says about itself on the network, and for how long.
void main() {
  group('a server only offers while the code is good', () {
    late DateTime clock;
    late SyncServer server;

    setUp(() {
      clock = DateTime.utc(2026, 1, 1, 12);
      server = SyncServer(_FakeHost(), now: () => clock);
    });

    test('nothing on offer to begin with', () {
      expect(server.isOffering, isFalse);
    });

    test('a fresh code is on offer', () {
      server.openPairing();
      expect(server.isOffering, isTrue);
    });

    test('an expired code is not', () {
      server.openPairing();
      clock = clock.add(kPairingWindow + const Duration(seconds: 1));
      expect(server.isOffering, isFalse);
    });

    test('a closed one is not', () {
      server.openPairing();
      server.closePairing();
      expect(server.isOffering, isFalse);
    });
  });

  test(
    'announcements report pairing as it stands, not as it started',
    () async {
      // Loopback rather than the subnet broadcast: a test cannot rely on a
      // network, and 127.0.0.1 comes straight back to the listener.
      // Loopback, and a port each: two sockets in one process cannot share
      // one, and the real broadcast address would not come back here.
      Discovery make({required bool announcing}) => Discovery(
        deviceId: announcing ? 'announcer' : 'listener',
        deviceName: announcing ? 'Announcer' : 'Listener',
        platform: 'test',
        broadcastAddress: InternetAddress.loopbackIPv4.address,
        announceEvery: const Duration(milliseconds: 60),
        port: announcing ? 41241 : 41240,
        sendToPort: 41240,
      );

      var pairing = true;
      final listener = make(announcing: false);
      final announcer = make(announcing: true);
      addTearDown(() async {
        await announcer.stop();
        await listener.stop();
      });

      await listener.start();
      final seen = <bool>[];
      final sub = listener.onFound.listen((d) => seen.add(d.isPairing));

      await announcer.start(servingPort: 4321, isPairing: () => pairing);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(seen, isNotEmpty, reason: 'no announcement arrived');
      expect(seen.every((x) => x), isTrue, reason: 'should all be pairing');

      // The code expires; the next announcement has to say so.
      pairing = false;
      seen.clear();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await sub.cancel();

      expect(seen, isNotEmpty, reason: 'announcements stopped');
      expect(seen.any((x) => x), isFalse, reason: 'still claiming a code');
    },
  );
}
