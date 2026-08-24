import 'dart:convert';

/// One product's label, as the reference database states it.
///
/// Everything optional except the name: a crowdsourced label can be missing
/// any field, and a missing field fills nothing rather than guessing.
class LabelReference {
  const LabelReference({
    required this.name,
    this.brand,
    this.caloriesPer100g,
    this.proteinPer100g,
    this.fatPer100g,
    this.carbsPer100g,
    this.sugarPer100g,
    this.servingAmount,
    this.servingUnit,
    this.packAmount,
    this.packUnit,
  });

  final String name;
  final String? brand;
  final double? caloriesPer100g;
  final double? proteinPer100g;
  final double? fatPer100g;
  final double? carbsPer100g;
  final double? sugarPer100g;
  final double? servingAmount;
  final String? servingUnit;
  final double? packAmount;
  final String? packUnit;
}

/// A search that failed in a way the user must be shown.
///
/// Kept apart from an empty result on purpose: "nothing found" and "the
/// request broke" must never look alike — a failure disguised as no results
/// is the most misleading state this feature can produce.
class LabelSearchException implements Exception {
  const LabelSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A number with the unit it was stated in, pulled out of label prose.
class ParsedAmount {
  const ParsedAmount(this.amount, this.unit);

  final double amount;
  final String unit;
}

/// Reads a weight or volume out of strings like "30 g", "2 biscuits (33g)"
/// or "4 x 125 g". The *last* match wins, because compound servings put the
/// weight in a trailing parenthesis. "1 portion" yields nothing — a serving
/// with no unit cannot bridge to a per-100 g basis, so guessing would only
/// corrupt the scaling.
ParsedAmount? parseAmount(String? text) {
  if (text == null) return null;
  final matches = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(kg|ml|g|l)\b',
  ).allMatches(text.toLowerCase()).toList();
  if (matches.isEmpty) return null;
  final m = matches.last;
  return ParsedAmount(
    double.parse(m.group(1)!.replaceAll(',', '.')),
    m.group(2)!,
  );
}

/// Parses one Open Food Facts search response.
///
/// Malformed products are dropped, not thrown on — one bad crowdsourced
/// entry must not sink the whole result list. A malformed *payload* throws
/// [LabelSearchException] instead, so it can never masquerade as an empty
/// result.
List<LabelReference> parseSearch(String body) {
  final dynamic raw;
  try {
    raw = jsonDecode(body);
  } on FormatException {
    throw const LabelSearchException(
      'The reference database sent something unreadable.',
    );
  }
  if (raw is! Map<String, dynamic> || raw['products'] is! List) {
    throw const LabelSearchException(
      'The reference database sent something unreadable.',
    );
  }

  final out = <LabelReference>[];
  for (final p in raw['products'] as List) {
    if (p is! Map<String, dynamic>) continue;
    final name = (p['product_name'] as String?)?.trim();
    if (name == null || name.isEmpty) continue;

    final n = p['nutriments'];
    final nutriments = n is Map<String, dynamic>
        ? n
        : const <String, dynamic>{};
    final serving = parseAmount(p['serving_size'] as String?);
    final pack = _pack(p);

    out.add(
      LabelReference(
        name: name,
        brand: _brand(p['brands']),
        caloriesPer100g: _kcal(nutriments),
        proteinPer100g: _number(nutriments['proteins_100g']),
        fatPer100g: _number(nutriments['fat_100g']),
        carbsPer100g: _number(nutriments['carbohydrates_100g']),
        sugarPer100g: _number(nutriments['sugars_100g']),
        servingAmount: serving?.amount,
        servingUnit: serving?.unit,
        packAmount: pack?.amount,
        packUnit: pack?.unit,
      ),
    );
  }
  return out;
}

double? _number(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

/// kcal when stated; converted from kJ when that is all the label has.
/// Plenty of European entries carry only `energy_100g` (kJ), and dropping
/// them would silently hide exactly the products the user searched for.
double? _kcal(Map<String, dynamic> nutriments) {
  final kcal = _number(nutriments['energy-kcal_100g']);
  if (kcal != null) return kcal;
  final kj = _number(nutriments['energy_100g']);
  return kj == null ? null : kj / 4.184;
}

/// OFF's `brands` is a comma-separated list; the first is the label's own.
String? _brand(dynamic brands) {
  if (brands is! String) return null;
  final first = brands.split(',').first.trim();
  return first.isEmpty ? null : first;
}

/// Pack size: the structured pair when present, else parsed out of the
/// free-text `quantity`.
ParsedAmount? _pack(Map<String, dynamic> p) {
  final amount = _number(p['product_quantity']);
  if (amount != null) {
    final unit = p['product_quantity_unit'];
    return ParsedAmount(
      amount,
      unit is String && unit.trim().isNotEmpty ? unit.trim() : 'g',
    );
  }
  return parseAmount(p['quantity'] as String?);
}
