/// Unit handling for scaling an ingredient line onto a pantry item's macros.
///
/// Everything reduces to one of three dimensions with a base unit: mass in
/// grams, volume in millilitres, count in whole items. A quantity that cannot
/// be reduced — "a handful", "to taste" — is deliberately not guessed at; the
/// caller flags the line instead of inventing a number for it.
library;

enum Dimension { mass, volume, count }

class Quantity {
  const Quantity(this.amount, this.dimension);

  /// In the dimension's base unit: grams, millilitres or whole items.
  final double amount;
  final Dimension dimension;
}

const _mass = <String, double>{
  'g': 1,
  'gram': 1,
  'grams': 1,
  'gr': 1,
  'kg': 1000,
  'kilo': 1000,
  'kilos': 1000,
  'kilogram': 1000,
  'kilograms': 1000,
  'mg': 0.001,
  'oz': 28.349523125,
  'ounce': 28.349523125,
  'ounces': 28.349523125,
  'lb': 453.59237,
  'lbs': 453.59237,
  'pound': 453.59237,
  'pounds': 453.59237,
};

const _volume = <String, double>{
  'ml': 1,
  'millilitre': 1,
  'millilitres': 1,
  'milliliter': 1,
  'milliliters': 1,
  'cl': 10,
  'dl': 100,
  'l': 1000,
  'litre': 1000,
  'litres': 1000,
  'liter': 1000,
  'liters': 1000,
  'tsp': 4.92892159375,
  'teaspoon': 4.92892159375,
  'teaspoons': 4.92892159375,
  'tbsp': 14.78676478125,
  'tablespoon': 14.78676478125,
  'tablespoons': 14.78676478125,
  'cup': 236.5882365,
  'cups': 236.5882365,
  'fl oz': 29.5735295625,
  'floz': 29.5735295625,
  'pint': 473.176473,
  'pints': 473.176473,
  'quart': 946.352946,
  'quarts': 946.352946,
};

/// Units that count whole things. An empty unit counts too — "4 chicken
/// cutlets" is written as quantity 4 with no unit.
const _count = <String>{
  '',
  'x',
  'piece',
  'pieces',
  'ball',
  'balls',
  'clove',
  'cloves',
  'can',
  'cans',
  'tin',
  'tins',
  'slice',
  'slices',
  'sprig',
  'sprigs',
  'stick',
  'sticks',
  'fillet',
  'fillets',
  'egg',
  'eggs',
  'unit',
  'units',
  'bag',
  'bags',
  'pack',
  'packs',
  'jar',
  'jars',
  'head',
  'heads',
  'bunch',
  'bunches',
};

/// Deliberately unmeasurable. These are recognised so the app can say "this
/// line cannot be scaled" rather than silently treating it as zero.
const unmeasurableUnits = <String>{
  'handful',
  'handfuls',
  'pinch',
  'pinches',
  'splash',
  'splashes',
  'glug',
  'glugs',
  'dash',
  'dashes',
  'drizzle',
  'to taste',
  'some',
};

String normaliseUnit(String unit) => unit.trim().toLowerCase();

bool isUnmeasurable(String unit) =>
    unmeasurableUnits.contains(normaliseUnit(unit));

/// Reduces [amount] of [unit] to its base unit, or null when the unit is not
/// one the app can reason about.
Quantity? toBase(double? amount, String unit) {
  if (amount == null) return null;
  final u = normaliseUnit(unit);
  if (isUnmeasurable(u)) return null;

  final m = _mass[u];
  if (m != null) return Quantity(amount * m, Dimension.mass);

  final v = _volume[u];
  if (v != null) return Quantity(amount * v, Dimension.volume);

  if (_count.contains(u)) return Quantity(amount, Dimension.count);

  // An unrecognised unit is treated as a count of whatever it names — "2
  // balls of mozzarella" behaves the same whether or not "ball" is listed.
  return Quantity(amount, Dimension.count);
}

/// Formats a number the way the design writes quantities: no trailing zeroes,
/// and common fractions left readable.
String formatAmount(double? value) {
  if (value == null) return '';
  if ((value - value.roundToDouble()).abs() < 0.0001) {
    return value.round().toString();
  }
  final oneDp = value.toStringAsFixed(1);
  if (double.parse(oneDp) == value) return oneDp;
  return value.toStringAsFixed(2);
}
