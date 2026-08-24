import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'release_check.dart';

/// A download that did not produce a file. The reason is already in plain
/// words, ready for the Settings row.
class DownloadFailure implements Exception {
  DownloadFailure(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

/// The user pressed cancel; nothing is wrong. Distinct from
/// [DownloadFailure] so the Settings row can fall quietly back to
/// "available" instead of showing an error that never happened.
class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

/// The fetching half of the update check: talk to the releases API, hand
/// the payload to [checkRelease], stream an artefact to disk.
///
/// Strictly on demand — nothing in here runs at launch, because the app is
/// offline by design and a silent background call would quietly break that.
class Updater {
  Updater({http.Client? httpClient, Uri? releasesUri})
    : _http = httpClient ?? http.Client(),
      _releasesUri =
          releasesUri ??
          Uri.parse(
            'https://api.github.com/repos/arc084/recipe_book/releases/latest',
          );

  final http.Client _http;
  final Uri _releasesUri;

  void close() => _http.close();

  /// Asks the releases API what the newest release is and compares it
  /// against [running]. Never throws: whatever goes wrong comes back as a
  /// [ReleaseCheck] outcome the Settings row can show.
  Future<ReleaseCheck> check(String running, UpdatePlatform platform) async {
    final http.Response response;
    try {
      response = await _http.get(
        _releasesUri,
        headers: const {'Accept': 'application/vnd.github+json'},
      );
    } on Exception catch (e) {
      return CheckFailed('Could not reach the releases API: $e');
    }
    if (response.statusCode != 200) {
      return CheckFailed(
        'The releases API answered ${response.statusCode}.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return const MalformedRelease('The response is not JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      return const MalformedRelease('The response is not a release object.');
    }
    return checkRelease(running, decoded, platform);
  }

  /// Streams [update]'s artefact into [into], reporting progress as
  /// (bytes received, bytes expected). Throws [DownloadFailure] rather than
  /// leaving a partial file behind.
  Future<File> download(
    AvailableUpdate update, {
    required Directory into,
    void Function(int received, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final http.StreamedResponse response;
    try {
      response = await _http.send(http.Request('GET', update.artefact));
    } on Exception catch (e) {
      throw DownloadFailure('The download could not start: $e');
    }
    if (response.statusCode != 200) {
      throw DownloadFailure(
        'The download answered ${response.statusCode}.',
      );
    }

    final total = response.contentLength ?? update.sizeBytes;
    final file = File(
      '${into.path}${Platform.pathSeparator}'
      '${update.artefact.pathSegments.last}',
    );
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        if (isCancelled?.call() ?? false) throw const DownloadCancelled();
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
        if (isCancelled?.call() ?? false) throw const DownloadCancelled();
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      // Half an artefact must not survive to be installed.
      await sink.close();
      if (file.existsSync()) file.deleteSync();
      if (e is DownloadCancelled) rethrow;
      throw DownloadFailure('The download broke off partway: $e');
    }
    return file;
  }
}
