import 'dart:convert';
import 'dart:io';

import '../data/database.dart';
import '../data/settings.dart';
import 'protocol.dart';

/// What the host needs from the app, kept behind an interface so the server
/// can be exercised without an AppState behind it.
abstract class SyncHost {
  String get deviceId;
  String get deviceName;
  String get platform;

  LibraryDatabase get library;
  PantryDatabase get pantry;

  /// The devices already paired with, for looking up a signing key.
  List<PairedDevice> get pairedDevices;

  /// Called when a joining device presents a valid code.
  Future<void> onPaired(PairedDevice device);

  /// Called when a peer pushes its merged state.
  Future<void> onIncoming(LibraryDatabase library, PantryDatabase pantry);

  /// Bytes of a stored photo, by content hash. Null when we do not have it.
  Future<List<int>?> photoBytes(String hash);
}

/// Answers on the local network for one paired peer at a time.
///
/// Deliberately short-lived: it is started when the user opens the pairing or
/// sync sheet and stopped when they leave. The app is offline by design and a
/// socket listening in the background all day is out of character for it.
class SyncServer {
  SyncServer(this.host, {DateTime Function()? now})
    : _now = now ?? DateTime.now,
      _verifier = RequestVerifier(now: now);

  final SyncHost host;
  final DateTime Function() _now;
  final RequestVerifier _verifier;

  HttpServer? _server;
  PairingOffer? _offer;

  int get port => _server?.port ?? 0;
  bool get isRunning => _server != null;

  /// The code currently on offer, if any.
  PairingOffer? get offer => _offer;

  /// Starts listening on an ephemeral port.
  ///
  /// [address] is loopback in tests and any-IPv4 in the app.
  Future<int> start({InternetAddress? address, int port = 0}) async {
    if (_server != null) return _server!.port;
    final server = await HttpServer.bind(
      address ?? InternetAddress.anyIPv4,
      port,
      shared: true,
    );
    _server = server;
    server.listen(_handle, onError: (_) {});
    return server.port;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _offer = null;
  }

  /// Puts a fresh six-digit code on offer and returns it for display.
  PairingOffer openPairing() =>
      _offer = PairingOffer.fresh(now: _now().toUtc());

  void closePairing() => _offer = null;

  Future<void> _handle(HttpRequest request) async {
    try {
      final body = await _readBody(request);
      final path = request.uri.path;

      // Pairing is the one endpoint that cannot be signed — it is what
      // establishes the key everything else signs with.
      if (path == '/pair' && request.method == 'POST') {
        await _pair(request, body);
        return;
      }

      // Anyone can ask who is here; it is how a joining device finds the
      // right port. It says nothing a pairing code would not already reveal.
      if (path == '/hello' && request.method == 'GET') {
        final live = _offer?.isLive(_now().toUtc()) ?? false;
        await _json(request, {
          'version': kProtocolVersion,
          'deviceId': host.deviceId,
          'name': host.deviceName,
          'platform': host.platform,
          'pairing': live,
          // The salt is a challenge, not a secret: the joining device needs it
          // to answer, and handing it out costs nothing. What it buys is that
          // an eavesdropper cannot precompute the answers to all one million
          // codes ahead of time — they only get the salt once the offer is
          // already open and ticking.
          if (live) 'salt': _offer!.salt,
          'now': _now().toUtc().toIso8601String(),
        });
        return;
      }

      final failure = _verifier.verify(
        headers: {
          for (final h in [
            SyncHeaders.version,
            SyncHeaders.device,
            SyncHeaders.time,
            SyncHeaders.nonce,
            SyncHeaders.signature,
          ])
            h: request.headers.value(h) ?? '',
        },
        method: request.method,
        path: path,
        body: body,
        pskFor: _pskFor,
      );

      if (failure != null) {
        await _error(request, HttpStatus.unauthorized, failure.name);
        return;
      }

      switch (path) {
        case '/sync':
          await _sync(request, body);
        case _ when path.startsWith('/photo/'):
          await _photo(request, path.substring('/photo/'.length));
        default:
          await _error(request, HttpStatus.notFound, 'unknown endpoint');
      }
    } on Object catch (e) {
      await _error(request, HttpStatus.internalServerError, '$e');
    }
  }

  String? _pskFor(String deviceId) {
    for (final d in host.pairedDevices) {
      if (d.id == deviceId) return d.psk;
    }
    return null;
  }

  // ── Endpoints ─────────────────────────────────────────────────────────────

  Future<void> _pair(HttpRequest request, List<int> body) async {
    final offer = _offer;
    final now = _now().toUtc();

    if (offer == null || !offer.isLive(now)) {
      await _error(request, HttpStatus.forbidden, 'no code is on offer');
      return;
    }

    final json = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
    final joiner = json['deviceId'] as String?;
    final proof = json['proof'] as String?;
    if (joiner == null || proof == null) {
      await _error(request, HttpStatus.badRequest, 'malformed');
      return;
    }

    if (!offer.accepts(proof, now: now)) {
      // Say how many tries are left rather than leaving the user guessing why
      // it stopped working.
      await _error(
        request,
        HttpStatus.forbidden,
        'that code did not match · ${offer.attemptsLeft} left',
      );
      // Three wrong answers burn the code. A new one has to be shown.
      if (offer.attemptsLeft <= 0) _offer = null;
      return;
    }

    final psk = derivePsk(
      code: offer.code,
      salt: offer.salt,
      deviceA: host.deviceId,
      deviceB: joiner,
    );

    await host.onPaired(
      PairedDevice(
        id: joiner,
        name: json['name'] as String? ?? 'A device',
        platform: json['platform'] as String? ?? '',
        recipeCount: (json['recipeCount'] as num?)?.toInt() ?? 0,
        pantryCount: (json['pantryCount'] as num?)?.toInt() ?? 0,
        psk: psk,
        lastAddress: request.connectionInfo?.remoteAddress.address,
      ),
    );

    // Single use: the code is spent the moment it works.
    _offer = null;

    await _json(request, {
      'salt': offer.salt,
      'deviceId': host.deviceId,
      'name': host.deviceName,
      'platform': host.platform,
      'recipeCount': host.library.recipes.length,
      'pantryCount': host.pantry.items.length,
    });
  }

  /// The exchange. One request carries both databases in both directions:
  /// the peer's state comes in, ours goes back, and each side merges locally.
  Future<void> _sync(HttpRequest request, List<int> body) async {
    final json = jsonDecode(utf8.decode(body)) as Map<String, dynamic>;

    await host.onIncoming(
      LibraryDatabase.fromJson(json['library'] as Map<String, dynamic>),
      PantryDatabase.fromJson(json['pantry'] as Map<String, dynamic>),
    );

    await _json(request, {
      'now': _now().toUtc().toIso8601String(),
      'library': host.library.toJson(),
      'pantry': host.pantry.toJson(),
    });
  }

  Future<void> _photo(HttpRequest request, String hash) async {
    final bytes = await host.photoBytes(hash);
    if (bytes == null) {
      await _error(request, HttpStatus.notFound, 'no photo with that hash');
      return;
    }
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.binary
      ..add(bytes);
    await request.response.close();
  }

  // ── Plumbing ──────────────────────────────────────────────────────────────

  Future<List<int>> _readBody(HttpRequest request) async {
    final chunks = <int>[];
    await for (final chunk in request) {
      chunks.addAll(chunk);
    }
    return chunks;
  }

  Future<void> _json(HttpRequest request, Map<String, dynamic> body) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> _error(HttpRequest request, int status, String message) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode({'error': message}));
    await request.response.close();
  }
}
