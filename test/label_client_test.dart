import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recipe_book/labels/label_client.dart';
import 'package:recipe_book/labels/label_lookup.dart';

/// The plumbing half: one GET against Open Food Facts, identified, bounded,
/// and honest about failure. The offline rule lives in the caller — nothing
/// in this file runs unless the user tapped search.
void main() {
  const body =
      '{"count": 1, "products": [{"product_name": "Chocolate Digestive", '
      '"nutriments": {"energy-kcal_100g": 495}}]}';

  test('identifies the app and sends the search terms', () async {
    late http.Request seen;
    final client = LabelClient(
      httpClient: () => MockClient((request) async {
        seen = request;
        return http.Response(body, 200);
      }),
    );

    final refs = await client.search('digestive biscuits');

    expect(seen.url.host, 'world.openfoodfacts.org');
    expect(seen.url.queryParameters['search_terms'], 'digestive biscuits');
    expect(seen.url.queryParameters['json'], '1');
    expect(seen.headers['user-agent'], startsWith('RecipeBook/'));
    expect(seen.headers['user-agent'], contains('github.com'));
    expect(refs.single.name, 'Chocolate Digestive');
  });

  test('a non-200 answer is a visible failure', () {
    final client = LabelClient(
      httpClient: () => MockClient((_) async => http.Response('down', 503)),
    );
    expect(
      () => client.search('anything'),
      throwsA(
        isA<LabelSearchException>().having(
          (e) => e.message,
          'message',
          contains('503'),
        ),
      ),
    );
  });

  test('a network error is a visible failure, not a crash', () {
    final client = LabelClient(
      httpClient: () =>
          MockClient((_) async => throw http.ClientException('refused')),
    );
    expect(
      () => client.search('anything'),
      throwsA(isA<LabelSearchException>()),
    );
  });
}
