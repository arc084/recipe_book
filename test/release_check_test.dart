import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/update/release_check.dart';

/// The pure half of the update check: parse a release, compare versions,
/// pick the artefact. Every case here has bitten someone in some updater
/// somewhere, which is why the comparison lives in its own file with no
/// network anywhere near it.
void main() {
  Map<String, dynamic> fixture() =>
      jsonDecode(
            File(
              'test/fixtures/github_release_0_8_0.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  /// A minimal release payload, so each case states only what it is about.
  Map<String, dynamic> release(String tag, {List<String>? assetNames}) => {
    'tag_name': tag,
    'body': 'notes',
    'published_at': '2026-08-30T18:00:00Z',
    'assets': [
      for (final name in assetNames ?? ['recipe-book-x-windows-x64.zip'])
        {
          'name': name,
          'size': 1000,
          'browser_download_url': 'https://example.com/$name',
        },
    ],
  };

  group('version comparison', () {
    test('0.10.0 is newer than 0.9.0, which a string comparison gets wrong',
        () {
      final result = checkRelease(
        '0.9.0',
        release('0.10.0'),
        UpdatePlatform.windows,
      );
      expect(result, isA<UpdateAvailable>());
    });

    test('a v-prefixed tag and the bare version are the same version', () {
      final result = checkRelease(
        '0.8.0',
        release('v0.8.0'),
        UpdatePlatform.windows,
      );
      expect(result, isA<UpToDate>());
    });

    test('an older release than the running build offers nothing', () {
      // A laptop running an unreleased local build is not told to downgrade.
      final result = checkRelease(
        '0.9.0',
        release('v0.8.0'),
        UpdatePlatform.windows,
      );
      expect(result, isA<UpToDate>());
    });
  });

  group('artefacts', () {
    test('offers the windows zip to windows', () {
      final result = checkRelease(
        '0.7.1',
        fixture(),
        UpdatePlatform.windows,
      );
      final update = (result as UpdateAvailable).update;
      expect(update.version, '0.8.0');
      expect(update.artefact.path, endsWith('windows-x64.zip'));
      expect(update.sizeBytes, 13371337);
      expect(update.notes, contains('Recipe editing on Android'));
      expect(update.publishedAt, DateTime.utc(2026, 8, 30, 18));
    });

    test('offers the apk to android', () {
      final result = checkRelease(
        '0.7.1',
        fixture(),
        UpdatePlatform.android,
      );
      final update = (result as UpdateAvailable).update;
      expect(update.artefact.path, endsWith('android.apk'));
      expect(update.sizeBytes, 24685000);
    });

    test('a release with nothing for this platform says so by name', () {
      // Not silently "up to date" — the release exists, the build is missing.
      final result = checkRelease(
        '0.7.1',
        release('v0.8.0', assetNames: ['recipe-book-0.8.0-android.apk']),
        UpdatePlatform.windows,
      );
      expect(result, isA<NotForThisPlatform>());
      expect((result as NotForThisPlatform).version, '0.8.0');
    });
  });

  group('malformed responses fail visibly', () {
    // A failed check that looks like "up to date" is worse than no button.
    test('an empty payload is malformed, not current', () {
      final result = checkRelease(
        '0.7.1',
        <String, dynamic>{},
        UpdatePlatform.windows,
      );
      expect(result, isA<MalformedRelease>());
    });

    test('a tag that is not a version is malformed', () {
      final result = checkRelease(
        '0.7.1',
        release('nightly'),
        UpdatePlatform.windows,
      );
      expect(result, isA<MalformedRelease>());
    });

    test('assets of the wrong shape are malformed', () {
      final result = checkRelease(
        '0.7.1',
        {'tag_name': 'v9.9.9', 'assets': 'gone wrong'},
        UpdatePlatform.windows,
      );
      expect(result, isA<MalformedRelease>());
    });
  });
}
