import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/state/share_intake.dart';

void main() {
  group('ShareIntake.extractUrl', () {
    test('takes a bare address', () {
      expect(
        ShareIntake.extractUrl('https://www.seriouseats.com/chicken-parm'),
        'https://www.seriouseats.com/chicken-parm',
      );
    });

    test('finds the address in what Chrome actually shares', () {
      // Chrome sends the page title and the address together.
      expect(
        ShareIntake.extractUrl(
          'Chicken Parmesan Recipe\nhttps://www.seriouseats.com/chicken-parm',
        ),
        'https://www.seriouseats.com/chicken-parm',
      );
    });

    test(
      'keeps the query string, which carries the recipe id on some sites',
      () {
        expect(
          ShareIntake.extractUrl(
            'Look at this https://example.com/r?id=42&x=1',
          ),
          'https://example.com/r?id=42&x=1',
        );
      },
    );

    test('drops sentence punctuation that is not part of the address', () {
      expect(
        ShareIntake.extractUrl('Try https://example.com/banana-bread.'),
        'https://example.com/banana-bread',
      );
      expect(
        ShareIntake.extractUrl('(https://example.com/oats)'),
        'https://example.com/oats',
      );
    });

    test('accepts http as well as https', () {
      expect(
        ShareIntake.extractUrl('http://example.com/x'),
        'http://example.com/x',
      );
    });

    test('returns null when there is no address to import', () {
      expect(ShareIntake.extractUrl(null), isNull);
      expect(ShareIntake.extractUrl(''), isNull);
      expect(ShareIntake.extractUrl('just some copied prose'), isNull);
      // A bare domain is not something the fetcher can use.
      expect(ShareIntake.extractUrl('seriouseats.com'), isNull);
    });
  });
}
