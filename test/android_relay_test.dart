import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/sync/cloud/android_relay.dart';

/// The one bit of Android path knowledge in the app: app-files directory in,
/// shared-media directory out. Strict on purpose — a layout it does not
/// recognise yields null, and the caller says so, rather than pointing a sync
/// app at a guess.
void main() {
  test('derives the media directory from the documented layout', () {
    expect(
      androidMediaRelay(
        '/storage/emulated/0/Android/data/com.example.recipe_book/files',
      ),
      '/storage/emulated/0/Android/media/com.example.recipe_book',
    );
  });

  test('tolerates a trailing slash', () {
    expect(
      androidMediaRelay(
        '/storage/emulated/0/Android/data/com.example.recipe_book/files/',
      ),
      '/storage/emulated/0/Android/media/com.example.recipe_book',
    );
  });

  test('an SD-card path yields null — the relay lives on primary storage', () {
    expect(
      androidMediaRelay(
        '/storage/A1B2-C3D4/Android/data/com.example.recipe_book/files',
      ),
      isNull,
    );
  });

  test('a path that is not an app-files directory yields null', () {
    expect(androidMediaRelay('/data/user/0/com.example/files'), isNull);
    expect(androidMediaRelay('/storage/emulated/0/Download'), isNull);
    expect(androidMediaRelay(''), isNull);
  });
}
