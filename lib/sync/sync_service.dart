import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../data/settings.dart';
import '../domain/sync/conflict_summary.dart';
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

  /// A merge paused on genuine ties, waiting for the user to pick sides.
  ///
  /// Survives [stop] on purpose: answering replays the snapshots held inside
  /// it and applies locally -- no socket is needed -- and the peer converges
  /// on the next exchange, whenever that is.
  PendingReview? review;

  /// Who the review came from, so answering it can advance their watermarks
  /// the same way a clean session does.
  PairedDevice? _reviewPeer;

  /// Raises a review from a transport with no live peer behind it.
  ///
  /// The folder transport reads a snapshot someone wrote earlier, so there is
  /// nobody to talk back to — [_reviewPeer] stays null and `resolveWith` skips
  /// the watermark bookkeeping, which is peer-specific. Everything else, the
  /// screen included, is the same.
  void openReview({
    required List<Conflict> conflicts,
    required LibraryDatabase peerLibrary,
    required PantryDatabase peerPantry,
    required ReviewSource source,
  }) {
    review = PendingReview(
      conflicts: conflicts,
      source: source,
      peerLibrary: peerLibrary,
      peerPantry: peerPantry,
    );
    _reviewPeer = null;
    notifyListeners();
  }

  /// Drops an unanswered review. Nothing was applied when it was raised, so
  /// nothing is lost -- the same questions return on the next sync, which is
  /// exactly right for questions nobody answered.
  void cancelReview() {
    review = null;
    _reviewPeer = null;
    notifyListeners();
  }

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
    String fromDeviceId,
  ) async {
    _incomingFrom = fromDeviceId;
    // This runs with nobody in front of it — the phone may be in a pocket — so
    // it must never park a question here, where it would be unreachable. Take
    // everything uncontested and keep this device's copy on any tie; the
    // device that started the session has a user who can answer, and their
    // answer arrives re-stamped on the next exchange.
    await _mergeIn(l, p, deferTiesToLocal: true);
    // Both sides took part, so both sides record it. Without this the device
    // that was synced *to* reads "never exchanged" no matter how many times it
    // has been, and its watermarks never advance — so it would keep re-asking
    // about conflicts it has already settled. A deferred merge always applies,
    // so there is no conflicted case to guard against here.
    for (final peer in _app.settings.devices) {
      if (peer.id == _incomingFrom) _app.recordSync(peer, l, p);
    }
  }

  /// Which device the request being handled came from, so the exchange can be
  /// recorded against it.
  String? _incomingFrom;

  /// Ties this device kept its own copy of because nobody was here to ask.
  /// Reported back so the initiator knows the peer did not fully converge.
  int deferredTies = 0;

  @override
  Future<List<int>?> photoBytes(String hash) => _app.photoBytesByHash(hash);

  @override
  Future<List<String>> missingPhotoHashes() => _app.missingPhotoHashes();

  @override
  Future<void> storePhoto(String hash, List<int> bytes) =>
      _app.storePhotoBytes(hash, bytes);

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
      );

      // The newer copy wins, which only means anything if the two clocks agree
      // about what "now" is. Past the tolerance they do not, so refuse rather
      // than silently pick a winner by a timestamp measuring something else —
      // a merge resolved on a bad clock is worse than one that did not happen.
      final skew = exchange.peerClock.difference(DateTime.now().toUtc()).abs();
      if (skew > kClockSkewLimit) {
        throw SyncException(
          "These devices' clocks are ${skew.inMinutes} minutes apart, so "
          '"newest wins" would pick the wrong copy. Fix the time on one of '
          'them and sync again.',
        );
      }

      phase = SyncPhase.merging;
      notifyListeners();

      final outcome = await _mergeIn(
        exchange.library,
        exchange.pantry,
        peer: peer,
      );

      if (review == null) {
        await _fetchMissingPhotos(client, peer, base);
        await _pushWantedPhotos(client, peer, base, exchange.wantedPhotos);
        _app.recordSync(peer, exchange.library, exchange.pantry);
      }

      phase = review == null ? SyncPhase.done : SyncPhase.idle;
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
    final pending = review;
    if (pending == null) {
      throw StateError('There is nothing waiting to be resolved.');
    }
    final peer = _reviewPeer;
    final outcome = await _mergeIn(
      pending.peerLibrary,
      pending.peerPantry,
      answers: answers,
      // The records the user chose between are re-stamped as this device's own
      // edit, so the answer is newer than either copy that caused the question
      // and the peer settles on the next exchange without being asked.
      restamp: answers.keys.toSet(),
    );
    if (review == null && peer != null) {
      // An answered session counts as an exchange: without this the peer's
      // watermarks stall and the next session replays it all from scratch.
      _app.recordSync(peer, pending.peerLibrary, pending.peerPantry);
    }
    phase = review == null ? SyncPhase.done : SyncPhase.idle;
    notifyListeners();
    return outcome;
  }

  // ── Merging ─────────────────────────────────────────────────────────────

  Future<SyncOutcome> _mergeIn(
    LibraryDatabase incomingLibrary,
    PantryDatabase incomingPantry, {
    Map<String, Resolution> answers = const {},
    Set<String> restamp = const {},
    bool deferTiesToLocal = false,
    PairedDevice? peer,
  }) async {
    var plan = _app.planMerge(
      incomingLibrary,
      incomingPantry,
      answers: answers,
    );

    var unresolved = [...plan.library.unresolved, ...plan.pantry.unresolved];

    if (unresolved.isNotEmpty && deferTiesToLocal) {
      // Replay with every tie answered "keep mine". The merge already holds
      // this device's copy for a conflicted record, so nothing is lost — the
      // choice simply moves to the device with someone at it.
      final kept = {
        for (final c in unresolved) c.id: Resolution.takeLocal,
        ...answers,
      };
      plan = _app.planMerge(incomingLibrary, incomingPantry, answers: kept);
      unresolved = [...plan.library.unresolved, ...plan.pantry.unresolved];
      deferredTies = kept.length - answers.length;
    }

    if (unresolved.isNotEmpty) {
      review = PendingReview(
        conflicts: unresolved,
        source: NetworkPeer(peerName: peer?.name ?? 'the other device'),
        peerLibrary: incomingLibrary,
        peerPantry: incomingPantry,
      );
      _reviewPeer = peer;
      notifyListeners();
      return SyncOutcome(received: 0, sent: 0, conflicts: unresolved.length);
    }

    await _app.applyMerge(plan.library, plan.pantry, restamp: restamp);
    if (!deferTiesToLocal) {
      // This applied merge supersedes any question still open from an earlier
      // session over the same data. A deferred (incoming) merge does not: its
      // ties were kept-local without restamping, so they still stand.
      review = null;
      _reviewPeer = null;
    }

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

  /// Sends the peer the photographs it said it was missing.
  ///
  /// The other half of [_fetchMissingPhotos]: the host cannot dial us, so
  /// without this photos would only ever travel from host to initiator, and a
  /// picture taken on the phone would never reach the laptop.
  Future<void> _pushWantedPhotos(
    SyncClient client,
    PairedDevice peer,
    Uri base,
    List<String> wanted,
  ) async {
    for (final hash in wanted) {
      final bytes = await _app.photoBytesByHash(hash);
      if (bytes == null) continue;
      try {
        await client.pushPhoto(base, peer: peer, hash: hash, bytes: bytes);
      } on SyncException {
        // Same reasoning as fetching: a photo that will not go up is not
        // worth failing the sync over, and the next session retries.
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
