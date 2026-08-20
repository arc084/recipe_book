import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/sync/protocol.dart';

/// Sync is unencrypted by design — signed rather than wrapped in TLS — and that
/// trade only holds on a local network. Android's network-security-config
/// cannot express "private ranges only" (its `<domain>` element has no subnet
/// syntax), so the rule lives in Dart and is pinned here.
void main() {
  group('isPrivateAddress', () {
    test('accepts the private IPv4 ranges', () {
      for (final host in [
        '10.0.0.1',
        '10.255.255.254',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.1.42',
        '169.254.10.1', // link-local, what you get with no DHCP
        '127.0.0.1',
      ]) {
        expect(isPrivateAddress(host), isTrue, reason: host);
      }
    });

    test('rejects public addresses', () {
      for (final host in [
        '8.8.8.8',
        '1.1.1.1',
        '172.15.0.1', // just below the private block
        '172.32.0.1', // just above it
        '192.169.1.1', // one off from 192.168
        '11.0.0.1',
        'example.com',
        'seriouseats.com',
      ]) {
        expect(isPrivateAddress(host), isFalse, reason: host);
      }
    });

    test('accepts local hostnames and IPv6 local addresses', () {
      expect(isPrivateAddress('localhost'), isTrue);
      expect(isPrivateAddress('kitchen-laptop.local'), isTrue);
      expect(isPrivateAddress('::1'), isTrue);
      expect(isPrivateAddress('fd00::1'), isTrue);
      expect(isPrivateAddress('fe80::1'), isTrue);
      expect(isPrivateAddress('2606:4700::1111'), isFalse);
    });

    test('rejects malformed input rather than guessing', () {
      for (final host in ['', '   ', '10.0.0', '10.0.0.256', '10.0.0.1.5']) {
        expect(isPrivateAddress(host), isFalse, reason: '"$host"');
      }
    });
  });
}
