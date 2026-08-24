import 'dart:async';

import 'package:http/http.dart' as http;

import '../app_version.dart';
import 'label_lookup.dart';

/// The one call this app makes to the reference database: a product search,
/// fired only by the user tapping search in the macros editor. Nothing here
/// runs on launch or in the background — that is the same offline rule the
/// update check follows, and it is load-bearing.
class LabelClient {
  LabelClient({http.Client Function()? httpClient})
    : _httpClient = httpClient ?? http.Client.new;

  /// A factory rather than a client, so every search gets a fresh client it
  /// can close — and tests can hand in a fake.
  final http.Client Function() _httpClient;

  static final Uri _endpoint = Uri.parse(
    'https://world.openfoodfacts.org/cgi/search.pl',
  );

  /// Open Food Facts asks apps to identify themselves.
  static const String userAgent =
      'RecipeBook/$kAppVersion (https://github.com/arc084/recipe_book)';

  Future<List<LabelReference>> search(String terms) async {
    final uri = _endpoint.replace(
      queryParameters: {
        'search_terms': terms,
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page_size': '8',
        'fields':
            'product_name,brands,nutriments,serving_size,quantity,'
            'product_quantity,product_quantity_unit',
      },
    );

    final client = _httpClient();
    try {
      final response = await client
          .get(uri, headers: {'User-Agent': userAgent})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw LabelSearchException(
          'The reference database answered ${response.statusCode}.',
        );
      }
      return parseSearch(response.body);
    } on LabelSearchException {
      rethrow;
    } on TimeoutException {
      throw const LabelSearchException('The search took too long.');
    } catch (e) {
      // Whatever the transport threw, the user sees words, not a stack.
      throw LabelSearchException('The search could not get through: $e');
    } finally {
      client.close();
    }
  }
}
