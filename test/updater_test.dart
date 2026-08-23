import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recipe_book/update/release_check.dart';
import 'package:recipe_book/update/updater.dart';

/// The fetching half: everything the pure check cannot see — the network,
/// the status code, the bytes landing on disk. All of it through a fake
/// client, so nothing here touches the real internet.
void main() {
  final fixtureBody = File(
    'test/fixtures/github_release_0_8_0.json',
  ).readAsStringSync();

  group('check', () {
    test('a good response flows through to the pure check', () async {
      final updater = Updater(
        httpClient: MockClient((request) async {
          expect(request.url.host, 'api.github.com');
          return http.Response(fixtureBody, 200);
        }),
      );

      final result = await updater.check('0.7.1', UpdatePlatform.windows);

      expect(result, isA<UpdateAvailable>());
      expect(
        (result as UpdateAvailable).update.version,
        '0.8.0',
      );
    });

    test('a non-200 answer fails in plain words, not as up to date',
        () async {
      final updater = Updater(
        httpClient: MockClient(
          (_) async => http.Response('rate limited', 403),
        ),
      );

      final result = await updater.check('0.7.1', UpdatePlatform.windows);

      expect(result, isA<CheckFailed>());
      expect((result as CheckFailed).reason, contains('403'));
    });

    test('a dead network fails in plain words too', () async {
      final updater = Updater(
        httpClient: MockClient(
          (_) async => throw const SocketException('no route'),
        ),
      );

      final result = await updater.check('0.7.1', UpdatePlatform.windows);

      expect(result, isA<CheckFailed>());
    });

    test('a body that is not JSON is malformed, not current', () async {
      final updater = Updater(
        httpClient: MockClient(
          (_) async => http.Response('<html>moved</html>', 200),
        ),
      );

      final result = await updater.check('0.7.1', UpdatePlatform.windows);

      expect(result, isA<MalformedRelease>());
    });
  });

  group('download', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('rb_updater'));
    tearDown(() => dir.deleteSync(recursive: true));

    AvailableUpdate update(int size) => AvailableUpdate(
      version: '0.8.0',
      notes: '',
      artefact: Uri.parse('https://example.com/recipe-book-0.8.0-android.apk'),
      sizeBytes: size,
      publishedAt: DateTime.utc(2026),
    );

    test('streams the artefact to disk and reports progress', () async {
      final bytes = List<int>.generate(4096, (i) => i % 256);
      final updater = Updater(
        httpClient: MockClient(
          (_) async => http.Response.bytes(bytes, 200),
        ),
      );

      final seen = <int>[];
      final file = await updater.download(
        update(bytes.length),
        into: dir,
        onProgress: (received, total) => seen.add(received),
      );

      expect(file.readAsBytesSync(), bytes);
      expect(file.path, endsWith('recipe-book-0.8.0-android.apk'));
      expect(seen.last, bytes.length);
    });

    test('a failed download throws and leaves no partial file behind',
        () async {
      final updater = Updater(
        httpClient: MockClient((_) async => http.Response('gone', 404)),
      );

      await expectLater(
        updater.download(update(10), into: dir),
        throwsA(isA<DownloadFailure>()),
      );
      expect(dir.listSync(), isEmpty);
    });
  });

  test('the JSON contract the mocks answer with matches the fixture', () {
    // Guards the fixture staying a real GitHub release shape.
    final decoded = jsonDecode(fixtureBody) as Map<String, dynamic>;
    expect(decoded['tag_name'], 'v0.8.0');
    expect(decoded['assets'], isA<List<dynamic>>());
  });
}
