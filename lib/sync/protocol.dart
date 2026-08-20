import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// The wire format version. Two devices on different versions refuse rather
/// than guess at each other's payloads.
const int kProtocolVersion = 1;

/// Where devices announce themselves. Broadcast, not multicast: multicast on
/// Android needs a `MulticastLock` and an extra permission, and broadcast
/// reaches everything on the same subnet just as well.
const int kDiscoveryPort = 41234;

/// How long a pairing code is good for. Long enough to walk across the room,
/// short enough that a shoulder-surfed code is worthless by the time it is
/// used.
const Duration kPairingWindow = Duration(minutes: 2);

/// How far apart two devices' clocks may be before a signed request is
/// rejected as a possible replay.
const Duration kClockTolerance = Duration(minutes: 2);

/// Beyond this the app refuses to resolve by "newest", because the timestamps
/// it would be comparing are not measuring the same thing.
const Duration kClockSkewLimit = Duration(minutes: 2);

/// Whether [host] is on the local network.
///
/// Sync is a local-network protocol, and it is deliberately unencrypted: a
/// self-signed certificate proves nothing, so the requests are signed instead.
/// That reasoning only holds on a LAN — a signed request to a public host would
/// still be a request to a public host — so this is what bounds it.
///
/// It lives here rather than in Android's network-security-config because that
/// file cannot express it: `<domain>` takes a hostname or a literal IP and has
/// no subnet syntax, so "private ranges only" was never sayable there.
bool isPrivateAddress(String host) {
  final h = host.trim().toLowerCase();
  if (h.isEmpty) return false;
  if (h == 'localhost' || h.endsWith('.local')) return true;

  // IPv6: loopback, unique-local (fc00::/7) and link-local (fe80::/10).
  if (h.contains(':')) {
    final v6 = h.replaceAll('[', '').replaceAll(']', '');
    return v6 == '::1' ||
        v6.startsWith('fc') ||
        v6.startsWith('fd') ||
        v6.startsWith('fe8') ||
        v6.startsWith('fe9') ||
        v6.startsWith('fea') ||
        v6.startsWith('feb');
  }

  final parts = h.split('.');
  if (parts.length != 4) return false;
  final octets = <int>[];
  for (final p in parts) {
    final n = int.tryParse(p);
    if (n == null || n < 0 || n > 255) return false;
    octets.add(n);
  }

  return switch (octets) {
    [10, _, _, _] => true,
    [127, _, _, _] => true,
    [169, 254, _, _] => true,
    [172, final b, _, _] when b >= 16 && b <= 31 => true,
    [192, 168, _, _] => true,
    _ => false,
  };
}

// ═══════════════════════════════════════════════════════════════════════════
// Signing
// ═══════════════════════════════════════════════════════════════════════════

/// Headers every signed request carries.
abstract final class SyncHeaders {
  static const device = 'x-rb-device';
  static const time = 'x-rb-time';
  static const nonce = 'x-rb-nonce';
  static const signature = 'x-rb-sig';
  static const version = 'x-rb-version';
}

/// Signs and verifies requests with the key two devices agreed at pairing.
///
/// The transport is plain HTTP: a self-signed certificate with no authority to
/// check it against proves nothing, so encrypting the channel would be
/// ceremony rather than security. What actually matters on a home network is
/// that a request came from the paired device and is not a replay, and that is
/// what this gives.
class RequestSigner {
  const RequestSigner(this.psk);

  final String psk;

  /// What gets signed: the method, the path, the timestamp, the nonce, and a
  /// hash of the body. Leaving the body out would let anything on the network
  /// swap one signed request's payload for another's.
  String signature({
    required String method,
    required String path,
    required String time,
    required String nonce,
    required List<int> body,
  }) {
    final digest = sha256.convert(body).toString();
    final material = '$method\n$path\n$time\n$nonce\n$digest';
    return Hmac(
      sha256,
      utf8.encode(psk),
    ).convert(utf8.encode(material)).toString();
  }

  Map<String, String> headersFor({
    required String deviceId,
    required String method,
    required String path,
    required List<int> body,
    DateTime? now,
    String? nonce,
  }) {
    final at = (now ?? DateTime.now().toUtc()).toIso8601String();
    final n = nonce ?? newNonce();
    return {
      SyncHeaders.version: '$kProtocolVersion',
      SyncHeaders.device: deviceId,
      SyncHeaders.time: at,
      SyncHeaders.nonce: n,
      SyncHeaders.signature: signature(
        method: method,
        path: path,
        time: at,
        nonce: n,
        body: body,
      ),
    };
  }
}

/// Rejects anything that is not a fresh, correctly-signed request from a
/// device we have paired with.
enum AuthFailure {
  unknownDevice,
  badSignature,
  staleTimestamp,
  replayedNonce,
  versionMismatch,
}

class RequestVerifier {
  RequestVerifier({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Nonces already spent, with the time they were seen so they can be
  /// forgotten once they are too old to be replayed anyway.
  final Map<String, DateTime> _seen = {};

  /// Returns null when the request is good, or why it was refused.
  AuthFailure? verify({
    required Map<String, String> headers,
    required String method,
    required String path,
    required List<int> body,
    required String? Function(String deviceId) pskFor,
  }) {
    final version = int.tryParse(headers[SyncHeaders.version] ?? '');
    if (version != kProtocolVersion) return AuthFailure.versionMismatch;

    final deviceId = headers[SyncHeaders.device];
    final time = headers[SyncHeaders.time];
    final nonce = headers[SyncHeaders.nonce];
    final signature = headers[SyncHeaders.signature];
    if (deviceId == null ||
        time == null ||
        nonce == null ||
        signature == null) {
      return AuthFailure.badSignature;
    }

    final psk = pskFor(deviceId);
    if (psk == null) return AuthFailure.unknownDevice;

    final at = DateTime.tryParse(time);
    if (at == null) return AuthFailure.staleTimestamp;
    final now = _now().toUtc();
    if (at.difference(now).abs() > kClockTolerance) {
      return AuthFailure.staleTimestamp;
    }

    _forgetOldNonces(now);
    if (_seen.containsKey(nonce)) return AuthFailure.replayedNonce;

    final expected = RequestSigner(psk).signature(
      method: method,
      path: path,
      time: time,
      nonce: nonce,
      body: body,
    );
    if (!constantTimeEquals(expected, signature)) {
      return AuthFailure.badSignature;
    }

    _seen[nonce] = now;
    return null;
  }

  void _forgetOldNonces(DateTime now) {
    // Anything older than the tolerance window would already be refused for
    // its timestamp, so remembering it buys nothing.
    _seen.removeWhere((_, at) => now.difference(at) > kClockTolerance * 2);
  }
}

/// Compares without leaking how much of the value matched through timing.
bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

final _random = Random.secure();

String newNonce() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  return base64Url.encode(bytes);
}

/// A fresh salt for a pairing offer.
String newSalt() {
  final bytes = List<int>.generate(24, (_) => _random.nextInt(256));
  return base64Url.encode(bytes);
}

/// Six digits, from a cryptographic source.
String newPairingCode() => List.generate(6, (_) => _random.nextInt(10)).join();

// ═══════════════════════════════════════════════════════════════════════════
// Pairing
// ═══════════════════════════════════════════════════════════════════════════

/// What the joining device sends to prove it was shown the code.
///
/// The code itself never goes over the wire — only this. Salting it means a
/// listener cannot precompute the answers for all million codes in advance.
String pairingProof({required String code, required String salt}) =>
    sha256.convert(utf8.encode('$salt|$code')).toString();

/// The key both devices end up holding.
///
/// Derived, not transmitted: each side computes it from what it already knows,
/// so the secret never crosses the network at all. Sorting the two device ids
/// makes the inputs identical on both sides regardless of who called whom.
String derivePsk({
  required String code,
  required String salt,
  required String deviceA,
  required String deviceB,
}) {
  final ids = [deviceA, deviceB]..sort();
  return Hmac(
    sha256,
    utf8.encode('$salt|$code'),
  ).convert(utf8.encode('recipe-book-psk|${ids.join('|')}')).toString();
}

/// A pairing code that is live right now.
///
/// Held in memory only and never written to disk: it is worth something for
/// two minutes and nothing afterwards, and a code in a file outlives its
/// usefulness by a long way.
class PairingOffer {
  PairingOffer({
    required this.code,
    required this.salt,
    required this.expiresAt,
    this.attemptsLeft = 3,
  });

  factory PairingOffer.fresh({DateTime? now}) => PairingOffer(
    code: newPairingCode(),
    salt: newSalt(),
    expiresAt: (now ?? DateTime.now().toUtc()).add(kPairingWindow),
  );

  final String code;
  final String salt;
  final DateTime expiresAt;

  /// Six digits is a million possibilities — thin on its own. The expiry, the
  /// attempt limit and single use are what make it hold up, and none of them
  /// is optional.
  int attemptsLeft;

  bool isLive(DateTime now) => attemptsLeft > 0 && now.isBefore(expiresAt);

  Duration remaining(DateTime now) {
    final left = expiresAt.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// Checks a joining device's proof, spending an attempt whether or not it
  /// was right.
  bool accepts(String proof, {required DateTime now}) {
    if (!isLive(now)) return false;
    attemptsLeft--;
    return constantTimeEquals(pairingProof(code: code, salt: salt), proof);
  }
}
