import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/sync/tombstone.dart';
import 'migrations.dart';
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
    List<Tombstone>? tombstones,
    this.migratedAt,
  }) : recipes = recipes ?? <Recipe>[],
       tombstones = tombstones ?? <Tombstone>[],
       mealTypes = mealTypes ?? <MealType>[],
       aisles = aisles ?? <Aisle>[],
       groceries = groceries ?? <GroceryItem>[],
       plan = plan ?? <PlanEntry>[];

  final List<Recipe> recipes;
  final List<MealType> mealTypes;
  final List<Aisle> aisles;
  final List<GroceryItem> groceries;
  final List<PlanEntry> plan;

  /// Deletions, kept so they can travel. A record simply missing on one side
  /// is indistinguishable from one the other side has not seen yet, so without
  /// these every delete would be undone by the next reconciliation.
  ///
  /// They live here rather than in a file of their own so that exporting this
  /// library and importing it elsewhere carries its deletions with it.
  final List<Tombstone> tombstones;

  /// When this file was brought up to the current schema, if it ever was.
  /// Every stamp at or below this was backfilled rather than observed.
  final DateTime? migratedAt;

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
    tombstones: _tombstones(j),
    migratedAt: DateTime.tryParse(j['migratedAt'] as String? ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'schema': kSchemaVersion,
    if (migratedAt != null) 'migratedAt': migratedAt!.toIso8601String(),
    'recipes': [for (final r in recipes) r.toJson()],
    'mealTypes': [for (final m in mealTypes) m.toJson()],
    'aisles': [for (final a in aisles) a.toJson()],
    'groceries': [for (final g in groceries) g.toJson()],
    'plan': [for (final p in plan) p.toJson()],
    'tombstones': [for (final t in tombstones) t.toJson()],
  };
}

/// The pantry database — ingredients, their macros and their other known names.
class PantryDatabase {
  PantryDatabase({
    List<PantryItem>? items,
    this.assumeStaples = true,
    List<Tombstone>? tombstones,
    Map<String, Register>? registers,
    this.migratedAt,
  }) : items = items ?? <PantryItem>[],
       tombstones = tombstones ?? <Tombstone>[],
       registers = registers ?? <String, Register>{};

  final List<PantryItem> items;

  /// See [LibraryDatabase.tombstones].
  final List<Tombstone> tombstones;

  /// Scalars that sync. [assumeStaples] has no id to merge on, so it resolves
  /// by stamp through here instead.
  final Map<String, Register> registers;

  final DateTime? migratedAt;

  /// The Pantry tab's toggle: staples assumed on hand and excluded from
  /// missing-ingredient counts.
  bool assumeStaples;

  factory PantryDatabase.fromJson(Map<String, dynamic> j) => PantryDatabase(
    items: [
      for (final i in (j['items'] as List? ?? []))
        PantryItem.fromJson(i as Map<String, dynamic>),
    ],
    assumeStaples: j['assumeStaples'] as bool? ?? true,
    tombstones: _tombstones(j),
    registers: _registers(j),
    migratedAt: DateTime.tryParse(j['migratedAt'] as String? ?? ''),
  );

  Map<String, dynamic> toJson() => {
    'schema': kSchemaVersion,
    if (migratedAt != null) 'migratedAt': migratedAt!.toIso8601String(),
    'assumeStaples': assumeStaples,
    'items': [for (final i in items) i.toJson()],
    'tombstones': [for (final t in tombstones) t.toJson()],
    'registers': {for (final e in registers.entries) e.key: e.value.toJson()},
  };

  /// The register wins over the plain field when it is present and newer —
  /// the field is kept in the JSON so an older build can still read the file.
  bool get staplesAssumed =>
      (registers['assumeStaples']?.value as bool?) ?? assumeStaples;
}

List<Tombstone> _tombstones(Map<String, dynamic> j) {
  final out = <Tombstone>[];
  for (final t in (j['tombstones'] as List? ?? [])) {
    if (t is! Map<String, dynamic>) continue;
    // A tombstone that will not parse is dropped rather than thrown on: losing
    // one deletion is far better than a library that refuses to open.
    final parsed = Tombstone.tryFromJson(t);
    if (parsed != null) out.add(parsed);
  }
  return out;
}

Map<String, Register> _registers(Map<String, dynamic> j) {
  final raw = j['registers'];
  if (raw is! Map) return <String, Register>{};
  final out = <String, Register>{};
  for (final e in raw.entries) {
    final value = e.value;
    if (value is! Map<String, dynamic>) continue;
    final parsed = Register.tryFromJson(value);
    if (parsed != null) out['${e.key}'] = parsed;
  }
  return out;
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
    this.migrate,
    Directory? directory,
    // The field is private and the parameter is not, so they cannot share a
    // name and an initializing formal is not available here.
    // ignore: prefer_initializing_formals
  }) : _directory = directory;

  final String fileName;
  final T Function(Map<String, dynamic>) decode;
  final Map<String, dynamic> Function(T) encode;

  /// Brings an older file up to the current schema before [decode] ever sees
  /// it, so the model code only has to understand one shape.
  final Map<String, dynamic> Function(
    Map<String, dynamic> raw,
    MigrationContext ctx,
  )?
  migrate;

  /// Set in tests. `getApplicationSupportDirectory()` throws outside a real
  /// app, which is why this class had no coverage at all before.
  final Directory? _directory;

  File? _file;

  Future<Directory> _dir() async {
    final given = _directory;
    if (given != null) {
      if (!await given.exists()) await given.create(recursive: true);
      return given;
    }
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}data');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// When the file was last written. The migration backfill needs this: it is
  /// the only real evidence of when a schema-1 record was last touched.
  Future<DateTime?> modifiedAt() async {
    final f = await file();
    return await f.exists() ? (await f.lastModified()).toUtc() : null;
  }

  Future<File> file() async {
    if (_file != null) return _file!;
    final dir = await _dir();
    return _file = File('${dir.path}${Platform.pathSeparator}$fileName');
  }

  /// Loads the file, or returns null when there is nothing saved yet.
  ///
  /// Migrates first when the file is older than [kSchemaVersion], and re-saves
  /// once so the upgrade is paid exactly once. A file from a *newer* build is
  /// refused rather than silently downgraded.
  Future<T?> load(MigrationContext ctx) async {
    final f = await file();
    if (!await f.exists()) return null;
    final text = await f.readAsString();
    if (text.trim().isEmpty) return null;

    final raw = jsonDecode(text) as Map<String, dynamic>;
    final found = schemaOf(raw);
    if (found > kSchemaVersion) {
      throw SchemaTooNewException(found: found, supported: kSchemaVersion);
    }

    if (found < kSchemaVersion && migrate != null) {
      // Keep the pre-migration file. This runs against data the user cannot
      // get back any other way, and it runs on first launch after an update,
      // when nobody is watching.
      await _backUpOnce(f, found);
      final upgraded = migrate!(raw, ctx);
      final value = decode(upgraded);
      await save(value);
      return value;
    }

    return decode(raw);
  }

  /// Copies the file aside before its first migration, once per schema.
  Future<void> _backUpOnce(File f, int fromSchema) async {
    final backup = File('${f.path}.v$fromSchema.bak');
    if (await backup.exists()) return;
    await f.copy(backup.path);
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
  ///
  /// The version check matters more here than on [load]: without it a file
  /// written by a newer build is decoded by an older `fromJson`, loses every
  /// field it does not recognise, and that loss is immediately written to disk.
  Future<T> importFrom(String path, MigrationContext ctx) async {
    final incoming = File(path);
    final text = await incoming.readAsString();
    final raw = jsonDecode(text) as Map<String, dynamic>;

    final found = schemaOf(raw);
    if (found > kSchemaVersion) {
      throw SchemaTooNewException(found: found, supported: kSchemaVersion);
    }

    final value = decode(
      found < kSchemaVersion && migrate != null ? migrate!(raw, ctx) : raw,
    );
    await save(value);
    return value;
  }
}

JsonStore<LibraryDatabase> libraryStore({Directory? directory}) => JsonStore(
  fileName: 'library.json',
  decode: LibraryDatabase.fromJson,
  encode: (d) => d.toJson(),
  migrate: migrateLibrary,
  directory: directory,
);

JsonStore<PantryDatabase> pantryStore({Directory? directory}) => JsonStore(
  fileName: 'pantry.json',
  decode: PantryDatabase.fromJson,
  encode: (d) => d.toJson(),
  migrate: migratePantry,
  directory: directory,
);
