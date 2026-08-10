import '../data/models.dart';
import 'units.dart';

/// The five values, summed.
class Macros {
  const Macros({
    this.calories = 0,
    this.protein = 0,
    this.fat = 0,
    this.carbs = 0,
    this.sugar = 0,
  });

  final double calories;
  final double protein;
  final double fat;
  final double carbs;
  final double sugar;

  static const zero = Macros();

  Macros operator +(Macros o) => Macros(
        calories: calories + o.calories,
        protein: protein + o.protein,
        fat: fat + o.fat,
        carbs: carbs + o.carbs,
        sugar: sugar + o.sugar,
      );

  Macros scaled(double f) => Macros(
        calories: calories * f,
        protein: protein * f,
        fat: fat * f,
        carbs: carbs * f,
        sugar: sugar * f,
      );
}

/// Why a line contributed nothing.
enum LineGap {
  /// The line is not linked to a pantry item at all — saved recipe-only.
  notLinked,

  /// Linked, but that item has no macros entered yet.
  noMacros,

  /// Linked and has macros, but the amount cannot be reduced to the item's
  /// basis — "a handful of basil", or a count against a per-100 g item with no
  /// serving size to bridge them.
  notScalable,
}

/// One ingredient line's contribution, and whether it managed to make one.
class LineResult {
  const LineResult({
    required this.ingredient,
    required this.macros,
    required this.gap,
    required this.isEstimated,
  });

  final Ingredient ingredient;
  final Macros macros;

  /// Null when the line contributed properly.
  final LineGap? gap;
  final bool isEstimated;

  bool get counted => gap == null;
}

/// A recipe's — or one component's — calculated totals.
///
/// These are always the calculated values summed from linked pantry items. A
/// recipe's own listed figures are never mixed in here; they are shown only
/// during import, marked as about to be replaced.
class MacroTotals {
  const MacroTotals({
    required this.macros,
    required this.lines,
    required this.servings,
  });

  final Macros macros;
  final List<LineResult> lines;
  final int servings;

  Macros get perServing =>
      servings <= 0 ? macros : macros.scaled(1 / servings);

  /// Lines that could not be counted. These are flagged to the user rather
  /// than quietly treated as zero.
  List<LineResult> get gaps => lines.where((l) => l.gap != null).toList();

  /// Anything inheriting estimated values carries the flag through to here.
  bool get isEstimated => lines.any((l) => l.counted && l.isEstimated);

  bool get isComplete => gaps.isEmpty;
}

/// Applies the calculation rule. Construct it with the pantry, then ask it
/// about a recipe.
class MacroEngine {
  MacroEngine(Iterable<PantryItem> pantry)
      : _byId = {for (final p in pantry) p.id: p};

  final Map<String, PantryItem> _byId;

  PantryItem? item(String? id) => id == null ? null : _byId[id];

  /// Totals for the whole recipe.
  ///
  /// [servings] scales the result without touching the saved recipe — the
  /// serving stepper on the recipe view passes a different number here and
  /// nothing is written.
  MacroTotals forRecipe(Recipe recipe, {int? servings}) {
    final target = servings ?? recipe.servings;
    final factor = recipe.servings <= 0 ? 1.0 : target / recipe.servings;
    return _sum(recipe.ingredients, factor, target);
  }

  /// Totals for one component, scaled the same way.
  MacroTotals forComponent(
    Recipe recipe,
    String componentId, {
    int? servings,
  }) {
    final target = servings ?? recipe.servings;
    final factor = recipe.servings <= 0 ? 1.0 : target / recipe.servings;
    return _sum(recipe.ingredientsOf(componentId), factor, target);
  }

  MacroTotals _sum(List<Ingredient> lines, double factor, int servings) {
    var total = Macros.zero;
    final results = <LineResult>[];

    for (final line in lines) {
      final r = _line(line, factor);
      results.add(r);
      if (r.counted) total = total + r.macros;
    }

    return MacroTotals(macros: total, lines: results, servings: servings);
  }

  LineResult _line(Ingredient line, double factor) {
    // A branded line keeps its own ingredient and is not drawn from the pantry
    // item it happens to resemble, so an unlinked branded line is simply a
    // line with nothing behind it yet.
    final pantryItem = item(line.pantryItemId);

    if (pantryItem == null) {
      return LineResult(
        ingredient: line,
        macros: Macros.zero,
        gap: LineGap.notLinked,
        isEstimated: line.isEstimated,
      );
    }

    if (!pantryItem.hasMacros) {
      return LineResult(
        ingredient: line,
        macros: Macros.zero,
        gap: LineGap.noMacros,
        isEstimated: line.isEstimated || pantryItem.isEstimated,
      );
    }

    final portions = _portions(line, pantryItem, factor);
    if (portions == null) {
      return LineResult(
        ingredient: line,
        macros: Macros.zero,
        gap: LineGap.notScalable,
        isEstimated: line.isEstimated || pantryItem.isEstimated,
      );
    }

    final macros = Macros(
      calories: (pantryItem.calories ?? 0) * portions,
      protein: (pantryItem.protein ?? 0) * portions,
      fat: (pantryItem.fat ?? 0) * portions,
      carbs: (pantryItem.carbs ?? 0) * portions,
      sugar: (pantryItem.sugar ?? 0) * portions,
    );

    return LineResult(
      ingredient: line,
      macros: macros,
      gap: null,
      isEstimated: line.isEstimated || pantryItem.isEstimated,
    );
  }

  /// How many of the item's basis portions the line calls for.
  ///
  /// The item states its five values against one of three bases; this works
  /// out how many of that basis the recipe's amount comes to, bridging between
  /// mass and volume through the item's own second measurement where it has
  /// one ("serving 30 g, which is 2 tbsp").
  double? _portions(Ingredient line, PantryItem p, double factor) {
    final wanted = toBase(line.quantity, line.unit);
    if (wanted == null) return null;

    final basis = _basisQuantity(p);
    if (basis == null || basis.amount == 0) return null;

    final converted = _convert(wanted, basis.dimension, p);
    if (converted == null) return null;

    return (converted / basis.amount) * factor;
  }

  /// The size of one basis portion, in its own base unit.
  Quantity? _basisQuantity(PantryItem p) {
    switch (p.basis) {
      case MacroBasis.per100g:
        return const Quantity(100, Dimension.mass);
      case MacroBasis.perServing:
        return toBase(p.servingAmount, p.servingUnit);
      case MacroBasis.perPack:
        return toBase(p.packAmount, p.packUnit ?? '');
    }
  }

  /// Converts [q] into [target], using the item's serving/alt pair as the
  /// bridge when the dimensions differ.
  double? _convert(Quantity q, Dimension target, PantryItem p) {
    if (q.dimension == target) return q.amount;

    final bridge = _bridge(p);
    if (bridge == null) return null;

    // `bridge` is how many base units of `serving` equal one base unit of
    // `alt` — e.g. 15 grams per millilitre-group for a 30 g / 2 tbsp item.
    final serving = toBase(p.servingAmount, p.servingUnit);
    final alt = toBase(p.altAmount, p.altUnit ?? '');
    if (serving == null || alt == null) return null;

    if (q.dimension == alt.dimension && target == serving.dimension) {
      return q.amount * bridge;
    }
    if (q.dimension == serving.dimension && target == alt.dimension) {
      return q.amount / bridge;
    }
    return null;
  }

  /// Base units of the serving measurement per base unit of the alternate one.
  double? _bridge(PantryItem p) {
    final serving = toBase(p.servingAmount, p.servingUnit);
    final alt = toBase(p.altAmount, p.altUnit ?? '');
    if (serving == null || alt == null) return null;
    if (alt.amount == 0 || serving.dimension == alt.dimension) return null;
    return serving.amount / alt.amount;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Pantry coverage
// ═══════════════════════════════════════════════════════════════════════════

enum Coverage {
  /// The user has it.
  inPantry,

  /// A pantry item, but marked as run out. It keeps its macros and its other
  /// names; it just needs buying, so it counts as missing.
  outOfStock,

  /// Assumed on hand — salt, pepper, oil, sugar, flour — and excluded from
  /// missing counts.
  staple,

  /// Missing, but already on the shopping list.
  onList,

  /// Missing.
  missing,
}

class CoverageResult {
  const CoverageResult({
    required this.ingredient,
    required this.coverage,
    this.pantryItem,
  });

  final Ingredient ingredient;
  final Coverage coverage;
  final PantryItem? pantryItem;

  /// Whether the user actually has this.
  ///
  /// Something already on the shopping list is *not* in the pantry — it still
  /// has to be bought — so it counts against the "8 of 9 in pantry" figure and
  /// against the missing badge, even though its row reads "on your list".
  bool get countsAsMissing =>
      coverage == Coverage.missing ||
      coverage == Coverage.onList ||
      coverage == Coverage.outOfStock;

  /// Narrower: things that are not on the list yet either, and so are what
  /// "add the missing items to groceries" should actually add.
  bool get needsBuying =>
      coverage == Coverage.missing || coverage == Coverage.outOfStock;
}

/// Works out what the user has for a recipe.
class PantryCoverage {
  PantryCoverage({
    required Iterable<PantryItem> pantry,
    required Iterable<GroceryItem> groceries,
    required this.assumeStaples,
  })  : _pantry = pantry.toList(),
        _groceryNames = {
          for (final g in groceries)
            if (!g.checked) g.name.trim().toLowerCase(),
        };

  final List<PantryItem> _pantry;
  final Set<String> _groceryNames;

  /// The Pantry tab's toggle. When off, staples are counted like anything else.
  final bool assumeStaples;

  CoverageResult of(Ingredient line) {
    final linked = line.pantryItemId == null
        ? null
        : _pantry.where((p) => p.id == line.pantryItemId).firstOrNull;

    // An unlinked line may still name something the user has under one of its
    // other known names.
    final matched = linked ??
        _pantry.where((p) => p.matchesName(line.name)).firstOrNull;

    if (matched != null) {
      // Stock is checked before the staple assumption on purpose. Assuming
      // staples on hand is about not nagging over salt the user has never
      // thought to track; marking one run out is them saying they have none,
      // and stated beats assumed.
      if (!matched.inStock) {
        return CoverageResult(
          ingredient: line,
          coverage: Coverage.outOfStock,
          pantryItem: matched,
        );
      }
      if (matched.isStaple && assumeStaples) {
        return CoverageResult(
          ingredient: line,
          coverage: Coverage.staple,
          pantryItem: matched,
        );
      }
      return CoverageResult(
        ingredient: line,
        coverage: Coverage.inPantry,
        pantryItem: matched,
      );
    }

    if (_groceryNames.contains(line.name.trim().toLowerCase())) {
      return CoverageResult(ingredient: line, coverage: Coverage.onList);
    }

    return CoverageResult(ingredient: line, coverage: Coverage.missing);
  }

  List<CoverageResult> forRecipe(Recipe r) =>
      [for (final i in r.ingredients) of(i)];

  /// "8 of 9 in pantry" — the numerator counts what the user has on hand, and
  /// [missing] is everything they do not, listed or otherwise.
  ({
    int have,
    int total,
    List<CoverageResult> missing,
    List<CoverageResult> toBuy,
  }) summarise(Recipe r) {
    final all = forRecipe(r);
    final missing = all.where((c) => c.countsAsMissing).toList();
    return (
      have: all.length - missing.length,
      total: all.length,
      missing: missing,
      toBuy: all.where((c) => c.needsBuying).toList(),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
