import 'package:uuid/uuid.dart';

import '../domain/sync/stamp.dart';

const _uuid = Uuid();

String newId() => _uuid.v4();

/// A fixed namespace for records that ship with the app.
///
/// Any constant uuid works; this one is arbitrary and must never change, or
/// every install's seed ids would shift and stop matching each other's.
const _seedNamespace = '9f1b0d3e-5a4c-4f2b-9c7e-2b6d8a1c3f04';

/// A stable id for a record that comes from the shipped seed.
///
/// The seed used to mint a fresh v4 uuid on every install, which meant two
/// devices held the same shipped recipes under different ids — so a sync saw
/// them as unrelated records and added both, duplicating the whole corpus.
/// Deriving the id from what the record *is* makes every install agree.
///
/// v5 is a hash of (namespace, name), so it is deterministic and cannot
/// collide with the v4 ids [newId] mints for the user's own records.
String seedId(String kind, String key) =>
    _uuid.v5(_seedNamespace, '$kind|$key');

/// [seedId] under a name the tests can reach without importing internals.
String seedIdFor(String kind, String key) => seedId(kind, key);

/// A record the merge treats as a syncable unit.
///
/// Every one of these carries when it last changed and which device changed
/// it. Without that, two copies of the same id are simply two copies — there
/// is no way to say which is current, so no way to resolve them.
///
/// A recipe's components, ingredients and steps deliberately do **not** mix
/// this in. A recipe syncs as one whole tree, because its `order` fields are
/// only meaningful as a set: merged record by record, two independent
/// reorderings produce duplicate positions and a method that reads out of
/// sequence.
mixin Stamped {
  String get id;

  /// Epoch until something stamps it, so a never-stamped record loses to any
  /// genuine edit rather than beating it.
  DateTime updatedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  String updatedBy = '';

  Stamp get stamp => Stamp(updatedAt, updatedBy);

  set stamp(Stamp s) {
    updatedAt = s.at;
    updatedBy = s.by;
  }

  /// Reads the stamp off JSON. Shaped for a cascade so the existing
  /// expression-bodied `fromJson` factories stay one expression:
  /// `MealType(...)..readStamp(j)`.
  void readStamp(Map<String, dynamic> j) =>
      stamp = Stamp.tryRead(j) ?? Stamp.epoch;
}

/// Orders anything with an `order` and an `id`.
///
/// The id is not decoration. Two devices that each reorder a list produce
/// duplicate `order` values once merged, and renormalising them would mean
/// either restamping the records — an endless ping-pong of "newer"
/// reorderings — or leaving the two devices' stored bytes different forever.
/// Breaking the tie on the id needs no writes and gives both sides the same
/// sequence.
int byOrderThenId(dynamic a, dynamic b) {
  final byOrder = (a.order as int).compareTo(b.order as int);
  return byOrder != 0 ? byOrder : (a.id as String).compareTo(b.id as String);
}

/// Lets a `toJson` map take a record's stamp without restating the keys.
extension StampedJson on Map<String, dynamic> {
  Map<String, dynamic> withStamp(Stamped e) {
    e.stamp.writeInto(this);
    return this;
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Shared enums
// ═══════════════════════════════════════════════════════════════════════════

/// Where a pantry item is kept. Anything added lands in [pantry] until moved.
enum PantryGroup {
  fridge('Fridge'),
  pantry('Pantry'),
  freezer('Freezer');

  const PantryGroup(this.label);
  final String label;

  static PantryGroup parse(String? s) => PantryGroup.values.firstWhere(
    (g) => g.name == s,
    orElse: () => PantryGroup.pantry,
  );
}

/// What a pantry item's five macro values are stated against.
enum MacroBasis {
  per100g('per 100 g'),
  perServing('per serving'),
  perPack('per pack');

  const MacroBasis(this.label);
  final String label;

  static MacroBasis parse(String? s) => MacroBasis.values.firstWhere(
    (b) => b.name == s,
    orElse: () => MacroBasis.per100g,
  );
}

/// The four slots a day on the meal plan, in the order they appear.
enum MealSlot {
  breakfast('Breakfast'),
  lunch('Lunch'),
  dinner('Dinner'),
  snack('Snack');

  const MealSlot(this.label);
  final String label;

  static MealSlot parse(String? s) => MealSlot.values.firstWhere(
    (v) => v.name == s,
    orElse: () => MealSlot.dinner,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// library — stored recipes
// ═══════════════════════════════════════════════════════════════════════════

/// A user-defined meal type. Six ship by default; the ＋ in the Library adds
/// more. These are a recipe's category, and in the Library they act as filters.
class MealType with Stamped {
  MealType({required this.id, required this.name, required this.order});

  @override
  final String id;
  String name;
  int order;

  factory MealType.fromJson(Map<String, dynamic> j) => MealType(
    id: j['id'] as String,
    name: j['name'] as String,
    order: (j['order'] as num).toInt(),
  )..readStamp(j);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'order': order}.withStamp(this);
}

/// An ingredient line.
///
/// Quantity, unit and name stay three separate fields so serving scaling and
/// pantry matching keep working — never collapse them into one string.
class Ingredient {
  Ingredient({
    required this.id,
    required this.componentId,
    // Both optional: a line the recipe does not count — "a handful of basil"
    // — is a legitimate ingredient, not a malformed one.
    this.quantity,
    this.unit = '',
    required this.name,
    this.pantryItemId,
    this.isBranded = false,
    this.isEstimated = false,
    required this.order,
  });

  final String id;
  String componentId;

  /// Null for things a recipe does not count — "a handful of basil".
  double? quantity;
  String unit;
  String name;

  /// Set when this line draws its macros from a pantry item. Null means the
  /// line is recipe-only and is flagged rather than counted as zero.
  String? pantryItemId;

  /// A recipe naming a brand keeps its own ingredient and its own macros; it
  /// is listed on the pantry item but never linked to it.
  bool isBranded;

  /// Carried through to the recipe's totals when the values were taken from a
  /// similar product rather than this one.
  bool isEstimated;
  int order;

  Ingredient copy() => Ingredient(
    id: id,
    componentId: componentId,
    quantity: quantity,
    unit: unit,
    name: name,
    pantryItemId: pantryItemId,
    isBranded: isBranded,
    isEstimated: isEstimated,
    order: order,
  );

  factory Ingredient.fromJson(Map<String, dynamic> j) => Ingredient(
    id: j['id'] as String,
    componentId: j['componentId'] as String,
    quantity: (j['quantity'] as num?)?.toDouble(),
    unit: j['unit'] as String? ?? '',
    name: j['name'] as String,
    pantryItemId: j['pantryItemId'] as String?,
    isBranded: j['isBranded'] as bool? ?? false,
    isEstimated: j['isEstimated'] as bool? ?? false,
    order: (j['order'] as num).toInt(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'componentId': componentId,
    'quantity': quantity,
    'unit': unit,
    'name': name,
    'pantryItemId': pantryItemId,
    'isBranded': isBranded,
    'isEstimated': isEstimated,
    'order': order,
  };
}

/// A method step. Steps carry their component's heading but the numbering
/// shown to the user runs continuously across the whole recipe.
class RecipeStep {
  RecipeStep({
    required this.id,
    required this.componentId,
    required this.text,
    required this.order,
    this.timerMinutes,
  });

  final String id;
  String componentId;
  String text;
  int order;

  /// Lets cook mode offer a timer on the step that needs one.
  int? timerMinutes;

  RecipeStep copy() => RecipeStep(
    id: id,
    componentId: componentId,
    text: text,
    order: order,
    timerMinutes: timerMinutes,
  );

  factory RecipeStep.fromJson(Map<String, dynamic> j) => RecipeStep(
    id: j['id'] as String,
    componentId: j['componentId'] as String,
    text: j['text'] as String,
    order: (j['order'] as num).toInt(),
    timerMinutes: (j['timerMinutes'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'componentId': componentId,
    'text': text,
    'order': order,
    'timerMinutes': timerMinutes,
  };
}

/// A named part of a recipe — Cutlets, Breading, Fry & finish. Ingredients and
/// steps both group under these.
class RecipeComponent {
  RecipeComponent({
    required this.id,
    required this.recipeId,
    required this.name,
    required this.order,
  });

  final String id;
  String recipeId;
  String name;
  int order;

  RecipeComponent copy() =>
      RecipeComponent(id: id, recipeId: recipeId, name: name, order: order);

  factory RecipeComponent.fromJson(Map<String, dynamic> j) => RecipeComponent(
    id: j['id'] as String,
    recipeId: j['recipeId'] as String,
    name: j['name'] as String,
    order: (j['order'] as num).toInt(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'recipeId': recipeId,
    'name': name,
    'order': order,
  };
}

class Recipe with Stamped {
  Recipe({
    required this.id,
    required this.title,
    required this.mealTypeId,
    List<String>? tags,
    this.photoPath,
    this.photoHash,
    this.servings = 4,
    this.sourceUrl,
    this.notes = '',
    this.totalMinutes,
    this.timesCooked = 0,
    List<RecipeComponent>? components,
    List<Ingredient>? ingredients,
    List<RecipeStep>? steps,
  }) : tags = tags ?? <String>[],
       components = components ?? <RecipeComponent>[],
       ingredients = ingredients ?? <Ingredient>[],
       steps = steps ?? <RecipeStep>[];

  @override
  final String id;
  String title;
  String mealTypeId;
  List<String> tags;

  /// An absolute path to a file the user dropped. Null shows the placeholder —
  /// no stock imagery is ever substituted.
  ///
  /// This is **local**: it is built from this device's own storage directory,
  /// so it differs between a Windows install and an Android one by
  /// construction. It is never compared when reconciling and never taken from
  /// a peer — [photoHash] is what identifies the picture itself.
  String? photoPath;

  /// The photograph's content hash, which is the same on every device.
  String? photoHash;
  int servings;
  String? sourceUrl;
  String notes;
  int? totalMinutes;
  int timesCooked;

  final List<RecipeComponent> components;
  final List<Ingredient> ingredients;
  final List<RecipeStep> steps;

  List<RecipeComponent> get orderedComponents =>
      [...components]..sort(byOrderThenId);

  List<Ingredient> ingredientsOf(String componentId) =>
      ingredients.where((i) => i.componentId == componentId).toList()
        ..sort(byOrderThenId);

  List<RecipeStep> stepsOf(String componentId) =>
      steps.where((s) => s.componentId == componentId).toList()
        ..sort(byOrderThenId);

  /// Steps in the order they are cooked and numbered — component by component,
  /// one continuous run. Every screen that numbers a step uses this list so the
  /// numbers agree everywhere.
  List<RecipeStep> get orderedSteps => [
    for (final c in orderedComponents) ...stepsOf(c.id),
  ];

  /// The component a step belongs to, for the headings in the method column
  /// and in cook mode.
  RecipeComponent? componentOf(RecipeStep step) {
    for (final c in components) {
      if (c.id == step.componentId) return c;
    }
    return null;
  }

  /// A deep copy, so edit mode can be abandoned without touching what is saved.
  Recipe copy() => Recipe(
    id: id,
    title: title,
    mealTypeId: mealTypeId,
    tags: [...tags],
    photoPath: photoPath,
    photoHash: photoHash,
    servings: servings,
    sourceUrl: sourceUrl,
    notes: notes,
    totalMinutes: totalMinutes,
    timesCooked: timesCooked,
    components: [for (final c in components) c.copy()],
    ingredients: [for (final i in ingredients) i.copy()],
    steps: [for (final s in steps) s.copy()],
  );

  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
    id: j['id'] as String,
    title: j['title'] as String,
    mealTypeId: j['mealTypeId'] as String,
    tags: (j['tags'] as List?)?.cast<String>() ?? <String>[],
    photoPath: j['photoPath'] as String?,
    photoHash: j['photoHash'] as String?,
    servings: (j['servings'] as num?)?.toInt() ?? 4,
    sourceUrl: j['sourceUrl'] as String?,
    notes: j['notes'] as String? ?? '',
    totalMinutes: (j['totalMinutes'] as num?)?.toInt(),
    timesCooked: (j['timesCooked'] as num?)?.toInt() ?? 0,
    components: [
      for (final c in (j['components'] as List? ?? []))
        RecipeComponent.fromJson(c as Map<String, dynamic>),
    ],
    ingredients: [
      for (final i in (j['ingredients'] as List? ?? []))
        Ingredient.fromJson(i as Map<String, dynamic>),
    ],
    steps: [
      for (final s in (j['steps'] as List? ?? []))
        RecipeStep.fromJson(s as Map<String, dynamic>),
    ],
  )..readStamp(j);

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'mealTypeId': mealTypeId,
    'tags': tags,
    'photoPath': photoPath,
    'photoHash': photoHash,
    'servings': servings,
    'sourceUrl': sourceUrl,
    'notes': notes,
    'totalMinutes': totalMinutes,
    'timesCooked': timesCooked,
    'components': [for (final c in components) c.toJson()],
    'ingredients': [for (final i in ingredients) i.toJson()],
    'steps': [for (final s in steps) s.toJson()],
  }.withStamp(this);
}

/// A user-defined shop aisle. The order is the order the user walks the shop.
class Aisle with Stamped {
  Aisle({required this.id, required this.name, required this.order});

  @override
  final String id;
  String name;
  int order;

  factory Aisle.fromJson(Map<String, dynamic> j) => Aisle(
    id: j['id'] as String,
    name: j['name'] as String,
    order: (j['order'] as num).toInt(),
  )..readStamp(j);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'order': order}.withStamp(this);
}

/// A line on the shopping list.
///
/// Quantities arriving from several recipes combine into one line rather than
/// repeating the item, so [sources] is a list.
class GroceryItem with Stamped {
  GroceryItem({
    required this.id,
    required this.name,
    required this.aisleId,
    this.quantity = '',
    List<String>? sources,
    this.checked = false,
    this.pantryItemId,
  }) : sources = sources ?? <String>[];

  @override
  final String id;
  String name;
  String aisleId;

  /// Free text — "400 g", "2". Combined lines read "400 g + 1".
  String quantity;

  /// Which recipe each part came from, or "Added by hand".
  List<String> sources;
  bool checked;

  /// Set when the line came from, or matches, a pantry item — so checking it
  /// off can put it back in the pantry.
  String? pantryItemId;

  factory GroceryItem.fromJson(Map<String, dynamic> j) => GroceryItem(
    id: j['id'] as String,
    name: j['name'] as String,
    aisleId: j['aisleId'] as String,
    quantity: j['quantity'] as String? ?? '',
    sources: (j['sources'] as List?)?.cast<String>() ?? <String>[],
    checked: j['checked'] as bool? ?? false,
    pantryItemId: j['pantryItemId'] as String?,
  )..readStamp(j);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'aisleId': aisleId,
    'quantity': quantity,
    'sources': sources,
    'checked': checked,
    'pantryItemId': pantryItemId,
  }.withStamp(this);
}

/// One recipe in one slot on one day.
class PlanEntry with Stamped {
  PlanEntry({
    required this.id,
    required this.date,
    required this.slot,
    required this.recipeId,
  });

  @override
  final String id;

  /// Date only — the time part is always midnight.
  DateTime date;
  MealSlot slot;
  String recipeId;

  factory PlanEntry.fromJson(Map<String, dynamic> j) => PlanEntry(
    id: j['id'] as String,
    date: DateTime.parse(j['date'] as String),
    slot: MealSlot.parse(j['slot'] as String?),
    recipeId: j['recipeId'] as String,
  )..readStamp(j);

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String().split('T').first,
    'slot': slot.name,
    'recipeId': recipeId,
  }.withStamp(this);
}

// ═══════════════════════════════════════════════════════════════════════════
// pantry — ingredients and their macros
// ═══════════════════════════════════════════════════════════════════════════

/// An ingredient the user keeps, and the macros every other screen's numbers
/// are calculated from.
///
/// Macros belong here, not to a recipe's ingredient line. Changing one number
/// on this item updates every recipe drawing on it at once.
class PantryItem with Stamped {
  PantryItem({
    required this.id,
    required this.name,
    this.group = PantryGroup.pantry,
    List<String>? aliases,
    this.isStaple = false,
    this.inStock = true,
    this.brandLabel,
    this.servingAmount,
    this.servingUnit = 'g',
    this.altAmount,
    this.altUnit,
    this.packAmount,
    this.packUnit,
    this.basis = MacroBasis.per100g,
    this.calories,
    this.protein,
    this.fat,
    this.carbs,
    this.sugar,
    this.isEstimated = false,
    this.enteredOn,
  }) : aliases = aliases ?? <String>[];

  @override
  final String id;
  String name;
  PantryGroup group;

  /// "Also known as" — the loose names recipes use. An import matching any of
  /// these links to this item without asking.
  List<String> aliases;

  /// Staples are assumed on hand and excluded from missing-ingredient counts.
  bool isStaple;

  /// Whether the user actually has any right now.
  ///
  /// Being in the pantry and having some are two different things: running out
  /// of parmesan should make every recipe using it say so, without throwing
  /// away its macros, its other known names, or the fact that it belongs in
  /// the fridge. An item out of stock stays listed and counts as missing.
  bool inStock;

  /// The product this was read off, when the numbers came from a label.
  String? brandLabel;

  // Serving size comes first when the macros are written.
  double? servingAmount;
  String servingUnit;

  /// An optional second measurement, so a recipe can call for a spoonful.
  double? altAmount;
  String? altUnit;

  /// What the pack holds.
  double? packAmount;
  String? packUnit;

  /// What the five values below are stated against.
  MacroBasis basis;

  // Null means unknown. An ingredient with no macros is flagged, never counted
  // as zero.
  double? calories;
  double? protein;
  double? fat;
  double? carbs;
  double? sugar;

  /// Values taken from a similar product. Every recipe carrying them says so.
  bool isEstimated;
  DateTime? enteredOn;

  /// A ◦ on the chip means no macros yet.
  bool get hasMacros => calories != null;

  /// Every name this item answers to, for matching an imported ingredient.
  List<String> get allNames => <String>[name, ...aliases];

  bool matchesName(String candidate) {
    final c = candidate.trim().toLowerCase();
    return allNames.any((n) => n.trim().toLowerCase() == c);
  }

  PantryItem copy() => PantryItem(
    id: id,
    name: name,
    group: group,
    aliases: [...aliases],
    isStaple: isStaple,
    inStock: inStock,
    brandLabel: brandLabel,
    servingAmount: servingAmount,
    servingUnit: servingUnit,
    altAmount: altAmount,
    altUnit: altUnit,
    packAmount: packAmount,
    packUnit: packUnit,
    basis: basis,
    calories: calories,
    protein: protein,
    fat: fat,
    carbs: carbs,
    sugar: sugar,
    isEstimated: isEstimated,
    enteredOn: enteredOn,
  );

  factory PantryItem.fromJson(Map<String, dynamic> j) => PantryItem(
    id: j['id'] as String,
    name: j['name'] as String,
    group: PantryGroup.parse(j['group'] as String?),
    aliases: (j['aliases'] as List?)?.cast<String>() ?? <String>[],
    isStaple: j['isStaple'] as bool? ?? false,
    // Libraries written before stock was tracked list only what was on
    // hand, so an absent flag means in stock.
    inStock: j['inStock'] as bool? ?? true,
    brandLabel: j['brandLabel'] as String?,
    servingAmount: (j['servingAmount'] as num?)?.toDouble(),
    servingUnit: j['servingUnit'] as String? ?? 'g',
    altAmount: (j['altAmount'] as num?)?.toDouble(),
    altUnit: j['altUnit'] as String?,
    packAmount: (j['packAmount'] as num?)?.toDouble(),
    packUnit: j['packUnit'] as String?,
    basis: MacroBasis.parse(j['basis'] as String?),
    calories: (j['calories'] as num?)?.toDouble(),
    protein: (j['protein'] as num?)?.toDouble(),
    fat: (j['fat'] as num?)?.toDouble(),
    carbs: (j['carbs'] as num?)?.toDouble(),
    sugar: (j['sugar'] as num?)?.toDouble(),
    isEstimated: j['isEstimated'] as bool? ?? false,
    enteredOn: j['enteredOn'] == null
        ? null
        : DateTime.parse(j['enteredOn'] as String),
  )..readStamp(j);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'group': group.name,
    'aliases': aliases,
    'isStaple': isStaple,
    'inStock': inStock,
    'brandLabel': brandLabel,
    'servingAmount': servingAmount,
    'servingUnit': servingUnit,
    'altAmount': altAmount,
    'altUnit': altUnit,
    'packAmount': packAmount,
    'packUnit': packUnit,
    'basis': basis.name,
    'calories': calories,
    'protein': protein,
    'fat': fat,
    'carbs': carbs,
    'sugar': sugar,
    'isEstimated': isEstimated,
    'enteredOn': enteredOn?.toIso8601String(),
  }.withStamp(this);
}
