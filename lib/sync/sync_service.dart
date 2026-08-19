import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/settings.dart';
import '../domain/sync/merge.dart';
import '../state/app_state.dart';
import 'discovery.dart';
import 'protocol.dart';
import 'sync_client.dart';
import 'sync_server.dart';

/// Where a session got to, for the UI to narrate.
enum SyncPhase {
  idle,
  listening,
  connecting,
  exchanging,
  merging,
  done,
  failed,
}

/// What one completed exchange did.
class SyncOutcome {
  const SyncOutcome({
    required this.received,
    required this.sent,
    required this.conflicts,
    this.message,
  });

  final int received;
  final int sent;
  final int conflicts;
  final String? message;
}

/// Runs sync sessions and owns the sockets.
///
/// Both platforms can host and both can join — which device shows the code is
/// the user's choice, not the app's.
class SyncService extends ChangeNotifier implements SyncHost {
  SyncService(this._app);

  final AppState _app;

  SyncServer? _server;
  Discovery? _discovery;
  SyncClient? _client;

  SyncPhase phase = SyncPhase.idle;
  String? error;
  SyncOutcome? lastOutcome;

  /// Conflicts waiting on the user. The session pauses here rather than
  /// choosing for them.
  List<Conflict> pendingConflicts = const [];
  ({LibraryDatabase library, PantryDatabase pantry})? _pendingPeerState;

  // ── SyncHost ────────────────────────────────────────────────────────────

  @override
  String get deviceId => _app.settings.deviceId ?? '';
  @override
  String get deviceName => _app.settings.deviceName;
  @override
  String get platform => Platform.isAndroid ? 'android' : 'windows';
  @override
  LibraryDatabase get library => _app.library;
  @override
  PantryDatabase get pantry => _app.pantry;
  @override
  List<PairedDevice> get pairedDevices => _app.settings.devices;

  @override
  Future<void> onPaired(PairedDevice device) async {
    _app.rememberDevice(device);
    notifyListeners();
  }

  /// A peer pushed its state to us. We merge it exactly as if we had pulled
  /// it, so which device started the session changes nothing about the result.
  @override
  Future<void> onIncoming(
    LibraryDatabase l,
    PantryDatabase p,
    ConflictPolicy policy,
  ) async {
    await _mergeIn(l, p, policy: policy);
  }

  @override
  Future<List<int>?> photoBytes(String hash) => _app.photoBytesByHash(hash);

  // ── Hosting ─────────────────────────────────────────────────────────────

  /// Starts listening and shows a code for another device to type.
  Future<PairingOffer> offerPairing() async {
    final server = _server ??= SyncServer(this);
    final port = await server.start();
    final offer = server.openPairing();

    _discovery ??= Discovery(
      deviceId: deviceId,
      deviceName: deviceName,
      platform: platform,
    );
    await _discovery!.start(servingPort: port, pairing: true);

    phase = SyncPhase.listening;
    notifyListeners();
    return offer;
  }

  /// Starts listening so an already-paired device can reach us, without
  /// putting a code on offer.
  Future<int> startListening() async {
    final server = _server ??= SyncServer(this);
    final port = await server.start();
    _discovery ??= Discovery(
      deviceId: deviceId,
      deviceName: deviceName,
      platform: platform,
    );
    await _discovery!.start(servingPort: port);
    phase = SyncPhase.listening;
    notifyListeners();
    return port;
  }

  /// Looks for other devices without announcing anything.
  Future<Discovery> browse() async {
    final discovery = _discovery ??= Discovery(
      deviceId: deviceId,
      deviceName: deviceName,
      platform: platform,
    );
    await discovery.start();
    return discovery;
  }

  Future<void> stop() async {
    await _server?.stop();
    await _discovery?.stop();
    _client?.close();
    _server = null;
    _discovery = null;
    _client = null;
    if (phase == SyncPhase.listening) phase = SyncPhase.idle;
    notifyListeners();
  }

  // ── Joining ─────────────────────────────────────────────────────────────

  /// Types the six digits at a device that is showing them.
  Future<PairedDevice> pairWith(Uri base, String code) async {
    phase = SyncPhase.connecting;
    error = null;
    notifyListeners();

    try {
      final client = _clientFor();
      final greeting = await client.hello(base);
      if (!greeting.isPairing || greeting.salt == null) {
        throw const SyncException(
          'That device is not showing a code. Open Settings there and choose '
          'to pair.',
        );
      }

      final peer = await client.pair(
        base,
        code: code,
        salt: greeting.salt!,
        recipeCount: _app.library.recipes.length,
        pantryCount: _app.pantry.items.length,
      );

      _app.rememberDevice(peer);
      phase = SyncPhase.idle;
      notifyListeners();
      return peer;
    } on SyncException catch (e) {
      phase = SyncPhase.failed;
      error = e.message;
      notifyListeners();
      rethrow;
    }
  }

  /// One full session with an already-paired device.
  ///
  /// Sends this device's state, takes back the peer's, merges locally, and
  /// fetches any photograph the merge left us referencing but not holding.
  Future<SyncOutcome> syncWith(PairedDevice peer, Uri base) async {
    phase = SyncPhase.connecting;
    error = null;
    pendingConflicts = const [];
    notifyListeners();

    try {
      final client = _clientFor();

      phase = SyncPhase.exchanging;
      notifyListeners();

      final exchange = await client.exchange(
        base,
        peer: peer,
        library: _app.library,
        pantry: _app.pantry,
        policy: _app.settings.conflictPolicy,
      );

      // Resolving by "newest" is only meaningful if the two clocks agree about
      // what "now" is. Say so rather than silently picking a winner by a
      // timestamp that is measuring something else.
      final skew = exchange.peerClock.difference(DateTime.now().toUtc()).abs();
      final forceReview =
          skew > kClockSkewLimit &&
          _app.settings.conflictPolicy == ConflictPolicy.newestWins;

      phase = SyncPhase.merging;
      notifyListeners();

      final outcome = await _mergeIn(
        exchange.library,
        exchange.pantry,
        forceReview: forceReview,
        skew: skew,
      );

      if (pendingConflicts.isEmpty) {
        await _fetchMissingPhotos(client, peer, base);
        _app.recordSync(peer, exchange.library, exchange.pantry);
      }

      phase = pendingConflicts.isEmpty ? SyncPhase.done : SyncPhase.idle;
      lastOutcome = outcome;
      notifyListeners();
      return outcome;
    } on SyncException catch (e) {
      phase = SyncPhase.failed;
      error = e.message;
      notifyListeners();
      rethrow;
    }
  }

  /// Finishes a session the user had to answer questions on.
  Future<SyncOutcome> resolveWith(Map<String, Resolution> answers) async {
    final peerState = _pendingPeerState;
    if (peerState == null) {
      throw StateError('There is nothing waiting to be resolved.');
    }
    final outcome = await _mergeIn(
      peerState.library,
      peerState.pantry,
      answers: answers,
    );
    phase = pendingConflicts.isEmpty ? SyncPhase.done : SyncPhase.idle;
    notifyListeners();
    return outcome;
  }

  // ── Merging ─────────────────────────────────────────────────────────────

  Future<SyncOutcome> _mergeIn(
    LibraryDatabase incomingLibrary,
    PantryDatabase incomingPantry, {
    Map<String, Resolution> answers = const {},
    bool forceReview = false,
    Duration skew = Duration.zero,
    ConflictPolicy? policy,
  }) async {
    final plan = _app.planMerge(
      incomingLibrary,
      incomingPantry,
      answers: answers,
      forceReview: forceReview,
      policy: policy,
    );

    final unresolved = [...plan.library.unresolved, ...plan.pantry.unresolved];
    if (unresolved.isNotEmpty) {
      // Hold the peer's state so the answers can be replayed against exactly
      // the same inputs — the merge is a function, so this is a replay rather
      // than a half-applied mutation.
      _pendingPeerState = (library: incomingLibrary, pantry: incomingPantry);
      pendingConflicts = unresolved;
      notifyListeners();
      return SyncOutcome(
        received: 0,
        sent: 0,
        conflicts: unresolved.length,
        message: forceReview
            ? 'These devices\' clocks are ${skew.inMinutes} minutes apart, so '
                  '"newest wins" would not mean much. Have a look instead.'
            : null,
      );
    }

    await _app.applyMerge(plan.library, plan.pantry);
    _pendingPeerState = null;
    pendingConflicts = const [];

    return SyncOutcome(
      received: plan.library.stats.totalAdded + plan.pantry.stats.totalAdded,
      sent: 0,
      conflicts: 0,
    );
  }

  /// Pulls down any photograph a merged recipe names but this device does not
  /// hold. Photos travel by content hash, never by path — the paths differ by
  /// construction between a Windows install and an Android one.
  Future<void> _fetchMissingPhotos(
    SyncClient client,
    PairedDevice peer,
    Uri base,
  ) async {
    for (final hash in await _app.missingPhotoHashes()) {
      try {
        final bytes = await client.photo(base, peer: peer, hash: hash);
        if (bytes != null) await _app.storePhotoBytes(hash, bytes);
      } on SyncException {
        // A photo that will not come down is not worth failing the sync over;
        // the recipe still shows its placeholder and the next sync retries.
      }
    }
  }

  SyncClient _clientFor() => _client ??= SyncClient(
    deviceId: deviceId,
    deviceName: deviceName,
    platform: platform,
  );

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
