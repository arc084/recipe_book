import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../data/database.dart';
import '../data/settings.dart';
import 'protocol.dart';

/// Something went wrong that the user needs told about in their own terms.
class SyncException implements Exception {
  const SyncException(this.message, {this.isPairingCode = false});

  final String message;

  /// True when the user simply mistyped the six digits, which deserves a
  /// different tone from a network failure.
  final bool isPairingCode;

  @override
  String toString() => message;
}

/// Who answered at an address.
class PeerGreeting {
  const PeerGreeting({
    required this.deviceId,
    required this.name,
    required this.platform,
    required this.isPairing,
    required this.clock,
    this.salt,
  });

  final String deviceId;
  final String name;
  final String platform;

  /// Whether a code is on offer right now.
  final bool isPairing;

  /// The challenge to answer the code against. Present only while an offer is
  /// open.
  final String? salt;

  /// The peer's idea of the time, so the two can be compared before anything
  /// is resolved by "newest".
  final DateTime clock;
}

/// What came back from an exchange.
class SyncExchange {
  const SyncExchange({
    required this.library,
    required this.pantry,
    required this.peerClock,
    this.wantedPhotos = const [],
  });

  final LibraryDatabase library;
  final PantryDatabase pantry;
  final DateTime peerClock;

  /// Hashes the peer holds a reference to but not the bytes of. It cannot dial
  /// us to ask, so we push these.
  final List<String> wantedPhotos;
}

/// The joining half of the conversation.
class SyncClient {
  SyncClient({
    required this.deviceId,
    required this.deviceName,
    required this.platform,
    http.Client? httpClient,
    DateTime Function()? now,
  }) : _http = httpClient ?? http.Client(),
       _now = now ?? DateTime.now;

  final String deviceId;
  final String deviceName;
  final String platform;
  final http.Client _http;
  final DateTime Function() _now;

  static const _timeout = Duration(seconds: 20);

  void close() => _http.close();

  /// Asks who is at [base]. Unsigned — it is how a device finds its peer
  /// before there is a key to sign with.
  Future<PeerGreeting> hello(Uri base) async {
    final response = await _get(base.replace(path: '/hello'));
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    if ((json['version'] as num?)?.toInt() != kProtocolVersion) {
      throw const SyncException(
        'That device is running a different version of Recipe Book. Update '
        'both and try again.',
      );
    }
    return PeerGreeting(
      deviceId: json['deviceId'] as String,
      name: json['name'] as String? ?? 'A device',
      platform: json['platform'] as String? ?? '',
      isPairing: json['pairing'] as bool? ?? false,
      salt: json['salt'] as String?,
      clock: DateTime.parse(json['now'] as String),
    );
  }

  /// Presents the six digits and, if they are right, comes away with a key.
  ///
  /// The code never crosses the network — only a salted hash of it — and the
  /// key is derived independently on both sides rather than sent.
  Future<PairedDevice> pair(
    Uri base, {
    required String code,
    required String salt,
    int recipeCount = 0,
    int pantryCount = 0,
  }) async {
    final response = await _post(
      base.replace(path: '/pair'),
      jsonEncode({
        'deviceId': deviceId,
        'name': deviceName,
        'platform': platform,
        'proof': pairingProof(code: code, salt: salt),
        'recipeCount': recipeCount,
        'pantryCount': pantryCount,
      }),
    );

    if (response.statusCode == HttpStatus.forbidden) {
      final message =
          (jsonDecode(response.body) as Map<String, dynamic>)['error'];
      throw SyncException('$message', isPairingCode: true);
    }
    if (response.statusCode != HttpStatus.ok) {
      throw SyncException('Pairing failed (${response.statusCode}).');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return PairedDevice(
      id: json['deviceId'] as String,
      name: json['name'] as String? ?? 'A device',
      platform: json['platform'] as String? ?? '',
      recipeCount: (json['recipeCount'] as num?)?.toInt() ?? 0,
      pantryCount: (json['pantryCount'] as num?)?.toInt() ?? 0,
      psk: derivePsk(
        code: code,
        salt: json['salt'] as String,
        deviceA: deviceId,
        deviceB: json['deviceId'] as String,
      ),
      lastAddress: base.host,
    );
  }

  /// Sends this device's state and receives the peer's.
  Future<SyncExchange> exchange(
    Uri base, {
    required PairedDevice peer,
    required LibraryDatabase library,
    required PantryDatabase pantry,
  }) async {
    final body = jsonEncode({
      'library': library.toJson(),
      'pantry': pantry.toJson(),
    });

    final response = await _post(base.replace(path: '/sync'), body, peer: peer);

    if (response.statusCode == HttpStatus.unauthorized) {
      throw const SyncException(
        'That device would not accept this one. Unpair and pair again.',
      );
    }
    if (response.statusCode != HttpStatus.ok) {
      throw SyncException('The exchange failed (${response.statusCode}).');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return SyncExchange(
      library: LibraryDatabase.fromJson(
        json['library'] as Map<String, dynamic>,
      ),
      pantry: PantryDatabase.fromJson(json['pantry'] as Map<String, dynamic>),
      peerClock: DateTime.parse(json['now'] as String),
      wantedPhotos: [
        for (final h in (json['wantPhotos'] as List? ?? [])) h as String,
      ],
    );
  }

  /// Fetches a photograph by content hash. Null when the peer does not have it.
  Future<List<int>?> photo(
    Uri base, {
    required PairedDevice peer,
    required String hash,
  }) async {
    final path = '/photo/$hash';
    final signer = RequestSigner(peer.psk!);
    final response = await _http
        .get(
          base.replace(path: path),
          headers: signer.headersFor(
            deviceId: deviceId,
            method: 'GET',
            path: path,
            body: const <int>[],
            now: _now().toUtc(),
          ),
        )
        .timeout(_timeout);
    return response.statusCode == HttpStatus.ok ? response.bodyBytes : null;
  }

  /// Sends a photograph the peer asked for, named by its content hash.
  Future<void> pushPhoto(
    Uri base, {
    required PairedDevice peer,
    required String hash,
    required List<int> bytes,
  }) async {
    final path = '/photo/$hash';
    final signer = RequestSigner(peer.psk!);
    await _wrap(
      () => _http.put(
        base.replace(path: path),
        headers: {
          'content-type': 'application/octet-stream',
          ...signer.headersFor(
            deviceId: deviceId,
            method: 'PUT',
            path: path,
            body: bytes,
            now: _now().toUtc(),
          ),
        },
        body: bytes,
      ),
    );
  }

  // ── Plumbing ──────────────────────────────────────────────────────────────

  Future<http.Response> _get(Uri url) {
    _requirePrivate(url);
    return _wrap(() => _http.get(url));
  }

  Future<http.Response> _post(Uri url, String body, {PairedDevice? peer}) {
    _requirePrivate(url);
    final bytes = utf8.encode(body);
    final headers = <String, String>{'content-type': 'application/json'};
    if (peer?.psk != null) {
      headers.addAll(
        RequestSigner(peer!.psk!).headersFor(
          deviceId: deviceId,
          method: 'POST',
          path: url.path,
          body: bytes,
          now: _now().toUtc(),
        ),
      );
    }
    return _wrap(() => _http.post(url, headers: headers, body: bytes));
  }

  /// Refuses to dial anything that is not on the local network.
  ///
  /// Sync is unencrypted by design — signed rather than wrapped in TLS — and
  /// that trade only holds on a LAN. Android's network-security-config cannot
  /// express this restriction, so it is enforced here, where a test can prove
  /// it.
  void _requirePrivate(Uri url) {
    if (!isPrivateAddress(url.host)) {
      throw SyncException(
        'Sync only talks to devices on your own network, and ${url.host} is '
        'not one.',
      );
    }
  }

  /// Turns socket failures into something worth showing a user.
  Future<http.Response> _wrap(Future<http.Response> Function() send) async {
    try {
      return await send().timeout(_timeout);
    } on SocketException {
      throw const SyncException(
        'Could not reach that device. Check both are on the same Wi-Fi.',
      );
    } on HttpException {
      throw const SyncException('The connection dropped mid-exchange.');
    }
  }
}
