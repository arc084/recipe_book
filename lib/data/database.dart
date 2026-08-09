import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// The library database — stored recipes, and the lists that hang off them.
///
/// Kept deliberately separate from [PantryDatabase]: each has its own back up,
/// import and export, so a library can be replaced without touching the
/// pantry.
class LibraryDatabase {
  LibraryDatabase({
    List<Recipe>? recipes,
    List<MealType>? mealTypes,
    List<Aisle>? aisles,
    List<GroceryItem>? groceries,
    List<PlanEntry>? plan,
  })  : recipes = recipes ?? <Recipe>[],
        mealTypes = mealTypes ?? <MealType>[],
        aisles = aisles ?? <Aisle>[],
        groceries = groceries ?? <GroceryItem>[],
        plan = plan ?? <PlanEntry>[];

  final List<Recipe> recipes;
  final List<MealType> mealTypes;
  final List<Aisle> aisles;
  final List<GroceryItem> groceries;
  final List<PlanEntry> plan;

  factory LibraryDatabase.fromJson(Map<String, dynamic> j) => LibraryDatabase(
        recipes: [
          for (final r in (j['recipes'] as List? ?? []))
            Recipe.fromJson(r as Map<String, dynamic>),
        ],
        mealTypes: [
          for (final m in (j['mealTypes'] as List? ?? []))
            MealType.fromJson(m as Map<String, dynamic>),
        ],
        aisles: [
          for (final a in (j['aisles'] as List? ?? []))
            Aisle.fromJson(a as Map<String, dynamic>),
        ],
        groceries: [
          for (final g in (j['groceries'] as List? ?? []))
            GroceryItem.fromJson(g as Map<String, dynamic>),
        ],
        plan: [
          for (final p in (j['plan'] as List? ?? []))
            PlanEntry.fromJson(p as Map<String, dynamic>),
        ],
      );

  Map<String, dynamic> toJson() => {
        'schema': 1,
        'recipes': [for (final r in recipes) r.toJson()],
        'mealTypes': [for (final m in mealTypes) m.toJson()],
        'aisles': [for (final a in aisles) a.toJson()],
        'groceries': [for (final g in groceries) g.toJson()],
        'plan': [for (final p in plan) p.toJson()],
      };
}

/// The pantry database — ingredients, their macros and their other known names.
class PantryDatabase {
  PantryDatabase({
    List<PantryItem>? items,
    this.assumeStaples = true,
  }) : items = items ?? <PantryItem>[];

  final List<PantryItem> items;

  /// The Pantry tab's toggle: staples assumed on hand and excluded from
  /// missing-ingredient counts.
  bool assumeStaples;

  factory PantryDatabase.fromJson(Map<String, dynamic> j) => PantryDatabase(
        items: [
          for (final i in (j['items'] as List? ?? []))
            PantryItem.fromJson(i as Map<String, dynamic>),
        ],
        assumeStaples: j['assumeStaples'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'schema': 1,
        'assumeStaples': assumeStaples,
        'items': [for (final i in items) i.toJson()],
      };
}

/// Reads and writes one database file.
///
/// Writes go to a sibling `.tmp` first and are then renamed over the target, so
/// a crash mid-save cannot leave a half-written library behind.
class JsonStore<T> {
  JsonStore({
    required this.fileName,
    required this.decode,
    required this.encode,
  });

  final String fileName;
  final T Function(Map<String, dynamic>) decode;
  final Map<String, dynamic> Function(T) encode;

  File? _file;

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}data');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> file() async {
    if (_file != null) return _file!;
    final dir = await _dir();
    return _file = File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  /// Loads the file, or returns null when there is nothing saved yet.
  Future<T?> load() async {
    final f = await file();
    if (!await f.exists()) return null;
    final text = await f.readAsString();
    if (text.trim().isEmpty) return null;
    return decode(jsonDecode(text) as Map<String, dynamic>);
  }

  Future<void> save(T value) async {
    final f = await file();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(encode(value)),
      flush: true,
    );
    await tmp.rename(f.path);
  }

  /// Size on disk, for the Settings tab. Zero when nothing is saved yet.
  Future<int> sizeInBytes() async {
    final f = await file();
    return await f.exists() ? f.length() : 0;
  }

  /// Copies the database somewhere the user chose.
  Future<void> exportTo(String path) async {
    final f = await file();
    if (await f.exists()) await f.copy(path);
  }

  /// Replaces this database with a file the user chose, after checking it
  /// parses — a bad file leaves what is saved untouched.
  Future<T> importFrom(String path) async {
    final incoming = File(path);
    final text = await incoming.readAsString();
    final value = decode(jsonDecode(text) as Map<String, dynamic>);
    await save(value);
    return value;
  }
}

JsonStore<LibraryDatabase> libraryStore() => JsonStore(
      fileName: 'library.json',
      decode: LibraryDatabase.fromJson,
      encode: (d) => d.toJson(),
    );

JsonStore<PantryDatabase> pantryStore() => JsonStore(
      fileName: 'pantry.json',
      decode: PantryDatabase.fromJson,
      encode: (d) => d.toJson(),
    );
