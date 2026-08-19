import 'dart:io';

import 'package:flutter/services.dart';

/// Receives pages shared into the app from Android's share sheet.
///
/// The phone's usual way into an import is the share sheet rather than the
/// Library's ＋, so this is the front door for step 1 — but it still only
/// *starts* the import. Nothing is written to the library until step 3, the
/// same as every other route in.
class ShareIntake {
  ShareIntake({required this.onUrl});

  static const _channel = MethodChannel('recipe_book/share');

  /// Called with an address to import. Returns true when it was taken; false
  /// means the app was busy and the link should be held.
  final bool Function(String url) onUrl;

  String? _held;

  /// True when a shared link is waiting for a better moment.
  bool get hasHeldLink => _held != null;

  /// Starts listening, and collects anything that arrived before Dart was up.
  Future<void> start() async {
    // Only Android declares the intent filter; the desktop takes a drop or a
    // typed address instead.
    if (!Platform.isAndroid) return;

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedText') {
        _offer(call.arguments as String?);
      }
    });

    try {
      final initial = await _channel.invokeMethod<String>(
        'getInitialSharedText',
      );
      _offer(initial);
    } on MissingPluginException {
      // Running somewhere without the host side attached.
    }
  }

  /// Retries a link that was held back, e.g. once cook mode has ended.
  void flush() {
    final held = _held;
    if (held == null) return;
    _held = null;
    _offer(held);
  }

  void _offer(String? raw) {
    final url = extractUrl(raw);
    if (url == null) return;
    if (!onUrl(url)) _held = url;
  }

  /// Pulls the address out of shared text.
  ///
  /// Browsers rarely share a bare link — Chrome sends the page title and the
  /// address together, and some apps append tracking blurb — so this takes the
  /// first http(s) address it finds rather than requiring the whole string to
  /// be a URL.
  static String? extractUrl(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'https?://[^\s<>"]+').firstMatch(raw);
    if (match == null) return null;

    // Trailing punctuation from a sentence is not part of the address.
    var url = match.group(0)!;
    while (url.isNotEmpty && '.,;:)]}!?'.contains(url[url.length - 1])) {
      url = url.substring(0, url.length - 1);
    }
    return url.isEmpty ? null : url;
  }
}
