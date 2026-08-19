import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

/// What was read off a page, before anything is written.
class ParsedRecipe {
  ParsedRecipe({
    required this.title,
    required this.ingredients,
    required this.steps,
    this.sourceUrl,
    this.totalMinutes,
    this.servings,
    this.listedCalories,
    this.imageUrl,
    Set<int>? uncertainIngredients,
  }) : uncertainIngredients = uncertainIngredients ?? <int>{};

  String title;
  List<ParsedIngredient> ingredients;
  List<String> steps;
  String? sourceUrl;
  int? totalMinutes;
  int? servings;

  /// The page's own calorie figure. Shown, but marked as about to be replaced
  /// — the calculated total from pantry macros is what gets stored.
  double? listedCalories;
  String? imageUrl;

  /// Indexes into [ingredients] the parser was not confident about. These are
  /// outlined in the review step and named in its footer.
  final Set<int> uncertainIngredients;
}

class ParsedIngredient {
  ParsedIngredient({
    required this.raw,
    this.quantity,
    this.unit = '',
    this.name = '',
  });

  /// The line exactly as the page wrote it.
  final String raw;
  double? quantity;
  String unit;
  String name;
}

/// Reads a recipe off a page.
///
/// Tries schema.org Recipe JSON-LD first, since that is what makes a site
/// parse reliably, and falls back to microdata and then to common markup.
abstract final class RecipeParser {
  static ParsedRecipe? parse(String source, {String? url}) {
    final document = html.parse(source);
    final parsed =
        _fromJsonLd(document) ??
        _fromMicrodata(document) ??
        _fromMarkup(document);
    if (parsed == null) return null;
    parsed.sourceUrl = url;
    return parsed;
  }

  // ── schema.org JSON-LD ──────────────────────────────────────────────────

  static ParsedRecipe? _fromJsonLd(dom.Document document) {
    for (final script in document.querySelectorAll(
      'script[type="application/ld+json"]',
    )) {
      try {
        final decoded = jsonDecode(script.text);
        final recipe = _findRecipeNode(decoded);
        if (recipe == null) continue;
        return _fromSchemaMap(recipe);
      } catch (_) {
        // A malformed block is not worth failing the whole import over.
        continue;
      }
    }
    return null;
  }

  /// JSON-LD arrives as an object, a list, or wrapped in an `@graph`.
  static Map<String, dynamic>? _findRecipeNode(Object? node) {
    if (node is List) {
      for (final child in node) {
        final found = _findRecipeNode(child);
        if (found != null) return found;
      }
      return null;
    }
    if (node is! Map) return null;
    final map = node.cast<String, dynamic>();

    final type = map['@type'];
    final types = type is List ? type.map((t) => '$t') : ['$type'];
    if (types.contains('Recipe')) return map;

    if (map['@graph'] != null) return _findRecipeNode(map['@graph']);
    return null;
  }

  static ParsedRecipe _fromSchemaMap(Map<String, dynamic> map) {
    final ingredientLines = _stringList(map['recipeIngredient']);
    final ingredients = [
      for (final line in ingredientLines) parseIngredientLine(line),
    ];

    final parsed = ParsedRecipe(
      title: '${map['name'] ?? 'Untitled recipe'}'.trim(),
      ingredients: ingredients,
      steps: _instructions(map['recipeInstructions']),
      totalMinutes:
          _duration(map['totalTime']) ??
          ((_duration(map['cookTime']) ?? 0) +
                  (_duration(map['prepTime']) ?? 0))
              .let((v) => v == 0 ? null : v),
      servings: _servings(map['recipeYield']),
      listedCalories: _calories(map['nutrition']),
      imageUrl: _image(map['image']),
    );

    for (var i = 0; i < ingredients.length; i++) {
      if (_isUncertain(ingredients[i])) {
        parsed.uncertainIngredients.add(i);
      }
    }
    return parsed;
  }

  static List<String> _stringList(Object? value) {
    if (value == null) return const [];
    if (value is String) return [value];
    if (value is List) {
      return [
        for (final v in value)
          if (v is String) v.trim() else if (v is Map) '${v['text'] ?? ''}',
      ].where((s) => s.trim().isNotEmpty).toList();
    }
    return const [];
  }

  static List<String> _instructions(Object? value) {
    if (value == null) return const [];
    if (value is String) {
      // Some sites put the whole method in one blob.
      return value
          .split(RegExp(r'(?:\r?\n)+|(?<=\.)\s{2,}'))
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    if (value is List) {
      final out = <String>[];
      for (final item in value) {
        if (item is String) {
          if (item.trim().isNotEmpty) out.add(item.trim());
        } else if (item is Map) {
          final type = '${item['@type']}';
          if (type == 'HowToSection') {
            out.addAll(_instructions(item['itemListElement']));
          } else {
            final text = '${item['text'] ?? item['name'] ?? ''}'.trim();
            if (text.isNotEmpty) out.add(text);
          }
        }
      }
      return out;
    }
    return const [];
  }

  /// ISO 8601 durations — PT1H20M.
  static int? _duration(Object? value) {
    if (value is! String) return null;
    final m = RegExp(r'P(?:.*?T)?(?:(\d+)H)?(?:(\d+)M)?').firstMatch(value);
    if (m == null) return null;
    final hours = int.tryParse(m.group(1) ?? '') ?? 0;
    final minutes = int.tryParse(m.group(2) ?? '') ?? 0;
    final total = hours * 60 + minutes;
    return total == 0 ? null : total;
  }

  static int? _servings(Object? value) {
    if (value == null) return null;
    final text = value is List ? '${value.firstOrNull ?? ''}' : '$value';
    final m = RegExp(r'(\d+)').firstMatch(text);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  static double? _calories(Object? nutrition) {
    if (nutrition is! Map) return null;
    final raw = '${nutrition['calories'] ?? ''}';
    final m = RegExp(r'([\d.]+)').firstMatch(raw);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  static String? _image(Object? value) {
    if (value is String) return value;
    if (value is List && value.isNotEmpty) return _image(value.first);
    if (value is Map) {
      final url = '${value['url'] ?? ''}';
      return url.isEmpty ? null : url;
    }
    return null;
  }

  // ── Microdata and plain markup ──────────────────────────────────────────

  static ParsedRecipe? _fromMicrodata(dom.Document document) {
    final scope = document.querySelector('[itemtype*="schema.org/Recipe"]');
    if (scope == null) return null;

    final lines = scope
        .querySelectorAll(
          '[itemprop="recipeIngredient"], [itemprop="ingredients"]',
        )
        .map((e) => e.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;

    return _assemble(
      title:
          scope.querySelector('[itemprop="name"]')?.text.trim() ??
          document.querySelector('title')?.text.trim() ??
          'Untitled recipe',
      ingredientLines: lines,
      steps: scope
          .querySelectorAll('[itemprop="recipeInstructions"]')
          .map((e) => e.text.trim())
          .where((s) => s.isNotEmpty)
          .toList(),
    );
  }

  static ParsedRecipe? _fromMarkup(dom.Document document) {
    final lines = document
        .querySelectorAll(
          '.ingredient, .ingredients li, [class*="ingredient"] li',
        )
        .map((e) => e.text.trim())
        .where((s) => s.isNotEmpty && s.length < 200)
        .toList();
    if (lines.isEmpty) return null;

    final steps = document
        .querySelectorAll(
          '.instruction, .instructions li, .directions li, '
          '[class*="instruction"] li, [class*="method"] li',
        )
        .map((e) => e.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    return _assemble(
      title:
          document.querySelector('h1')?.text.trim() ??
          document.querySelector('title')?.text.trim() ??
          'Untitled recipe',
      ingredientLines: lines,
      steps: steps,
    );
  }

  static ParsedRecipe _assemble({
    required String title,
    required List<String> ingredientLines,
    required List<String> steps,
  }) {
    final ingredients = [
      for (final line in ingredientLines) parseIngredientLine(line),
    ];
    final parsed = ParsedRecipe(
      title: title,
      ingredients: ingredients,
      steps: steps,
    );
    for (var i = 0; i < ingredients.length; i++) {
      if (_isUncertain(ingredients[i])) parsed.uncertainIngredients.add(i);
    }
    return parsed;
  }

  // ── Ingredient lines ────────────────────────────────────────────────────

  static const _fractions = <String, double>{
    '½': 0.5,
    '⅓': 1 / 3,
    '⅔': 2 / 3,
    '¼': 0.25,
    '¾': 0.75,
    '⅕': 0.2,
    '⅖': 0.4,
    '⅗': 0.6,
    '⅘': 0.8,
    '⅙': 1 / 6,
    '⅚': 5 / 6,
    '⅛': 0.125,
    '⅜': 0.375,
    '⅝': 0.625,
    '⅞': 0.875,
  };

  static const _knownUnits = <String>{
    'g',
    'gram',
    'grams',
    'kg',
    'mg',
    'oz',
    'ounce',
    'ounces',
    'lb',
    'lbs',
    'pound',
    'pounds',
    'ml',
    'l',
    'litre',
    'litres',
    'liter',
    'liters',
    'tsp',
    'teaspoon',
    'teaspoons',
    'tbsp',
    'tablespoon',
    'tablespoons',
    'cup',
    'cups',
    'pinch',
    'handful',
    'clove',
    'cloves',
    'can',
    'cans',
    'tin',
    'tins',
    'slice',
    'slices',
    'ball',
    'balls',
    'sprig',
    'sprigs',
    'stick',
    'sticks',
    'fillet',
    'fillets',
    'bunch',
    'bunches',
    'pack',
    'packs',
    'jar',
    'jars',
    'head',
    'heads',
    'piece',
    'pieces',
  };

  /// Splits "400 g canned tomatoes" into its three fields.
  ///
  /// Quantity, unit and name are kept separate from the moment the line is
  /// read, because collapsing them would break scaling and pantry matching
  /// later.
  static ParsedIngredient parseIngredientLine(String raw) {
    var text = raw.trim();
    // Strip a leading bullet or number-with-dot the page used for layout.
    text = text.replaceFirst(RegExp(r'^[•\-\*•]\s*'), '');

    final result = ParsedIngredient(raw: raw.trim());
    if (text.isEmpty) return result;

    var rest = text;
    double? quantity;

    // A leading number, which may be "1 1/2", "1½", "1.5" or a bare fraction.
    final numberMatch = RegExp(
      r'^(\d+\s*\d*/\d+|\d+[.,]?\d*|[½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])\s*'
      r'([½⅓⅔¼¾⅕⅖⅗⅘⅙⅚⅛⅜⅝⅞])?\s*',
    ).firstMatch(rest);

    if (numberMatch != null) {
      quantity = _number(numberMatch.group(1)!);
      final extraFraction = numberMatch.group(2);
      if (extraFraction != null && quantity != null) {
        quantity += _fractions[extraFraction] ?? 0;
      }
      rest = rest.substring(numberMatch.end).trim();

      // A range — "2-3 onions" — takes the lower number.
      final range = RegExp(r'^[–—-]\s*[\d.]+\s*').firstMatch(rest);
      if (range != null) rest = rest.substring(range.end).trim();
    }

    // A unit, if the next word is one we recognise.
    var unit = '';
    final wordMatch = RegExp(r'^([A-Za-z]+)\.?\s+').firstMatch(rest);
    if (wordMatch != null) {
      final candidate = wordMatch.group(1)!.toLowerCase();
      if (_knownUnits.contains(candidate)) {
        unit = candidate;
        rest = rest.substring(wordMatch.end).trim();
      }
    }

    // "of" after a unit is noise — "a pinch of salt".
    rest = rest.replaceFirst(RegExp(r'^of\s+'), '');

    result
      ..quantity = quantity
      ..unit = unit
      ..name = rest.trim();
    return result;
  }

  static double? _number(String raw) {
    final text = raw.trim();
    if (_fractions.containsKey(text)) return _fractions[text];

    // "1 1/2" or "1/2"
    final mixed = RegExp(r'^(\d+)\s+(\d+)/(\d+)$').firstMatch(text);
    if (mixed != null) {
      return int.parse(mixed.group(1)!) +
          int.parse(mixed.group(2)!) / int.parse(mixed.group(3)!);
    }
    final fraction = RegExp(r'^(\d+)/(\d+)$').firstMatch(text);
    if (fraction != null) {
      return int.parse(fraction.group(1)!) / int.parse(fraction.group(2)!);
    }
    return double.tryParse(text.replaceAll(',', '.'));
  }

  /// A line the parser is not sure it read correctly.
  static bool _isUncertain(ParsedIngredient line) {
    if (line.name.isEmpty) return true;
    // No quantity at all, and the text does not read like a "to taste" line.
    if (line.quantity == null &&
        line.unit.isEmpty &&
        !RegExp(
          r'to taste|as needed|for serving|garnish',
          caseSensitive: false,
        ).hasMatch(line.raw)) {
      return true;
    }
    // Suspiciously long — probably a sentence that was not an ingredient.
    if (line.name.length > 80) return true;
    return false;
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
