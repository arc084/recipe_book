import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/database.dart';
import 'package:recipe_book/data/migrations.dart';
import 'package:recipe_book/data/models.dart';

/// The real databases, copied out of the desktop app before any of this
/// existed. A synthetic fixture would not find the surprises.
Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

final ctx = MigrationContext(
  deviceId: 'test-device',
  now: DateTime.utc(2026, 8, 18, 12),
  fileModifiedAt: DateTime.utc(2026, 8, 1, 9, 30),
);

void main() {
  group('schema detection', () {
    test('an absent key means schema 1', () {
      expect(schemaOf(<String, dynamic>{}), 1);
    });

    test('reads the key when present', () {
      expect(schemaOf(<String, dynamic>{'schema': 2}), 2);
    });
  });

  group('migrating the real library', () {
    late Map<String, dynamic> before;
    late LibraryDatabase after;

    setUp(() {
      before = fixture('library_v1_real.json');
      after = LibraryDatabase.fromJson(migrateLibrary(before, ctx));
    });

    test('loses nothing', () {
      expect(after.recipes, hasLength((before['recipes'] as List).length));
      expect(after.mealTypes, hasLength((before['mealTypes'] as List).length));
      expect(after.aisles, hasLength((before['aisles'] as List).length));
      expect(after.groceries, hasLength((before['groceries'] as List).length));
      expect(after.plan, hasLength((before['plan'] as List).length));
      expect(after.recipes, isNotEmpty, reason: 'fixture should have data');
    });

    test('a recipe survives field for field, nested records included', () {
      final raw = (before['recipes'] as List).first as Map<String, dynamic>;
      final migrated = after.recipes.firstWhere((r) => r.id == raw['id']);

      expect(migrated.title, raw['title']);
      expect(migrated.mealTypeId, raw['mealTypeId']);
      expect(migrated.servings, raw['servings']);
      expect(migrated.tags, (raw['tags'] as List).cast<String>());
      expect(
        migrated.components,
        hasLength((raw['components'] as List).length),
      );
      expect(
        migrated.ingredients,
        hasLength((raw['ingredients'] as List).length),
      );
      expect(migrated.steps, hasLength((raw['steps'] as List).length));

      // Nested records are internal to a recipe and are deliberately unstamped.
      final rawLine =
          (raw['ingredients'] as List).first as Map<String, dynamic>;
      final line = migrated.ingredients.firstWhere(
        (i) => i.id == rawLine['id'],
      );
      expect(line.name, rawLine['name']);
      expect(line.quantity, (rawLine['quantity'] as num?)?.toDouble());
      expect(line.unit, rawLine['unit'] ?? '');
      expect(line.pantryItemId, rawLine['pantryItemId']);
    });

    test('every record is stamped at the file mtime, not now', () {
      // Stamping at `now` would mark each device's whole corpus at the moment
      // that device happened to launch, so a first reconciliation would be
      // decided by launch order rather than by anything the user did.
      for (final r in after.recipes) {
        expect(r.updatedAt, ctx.fileModifiedAt);
        expect(r.updatedBy, 'test-device');
      }
    });

    test(
      'records the migration point so backfilled stamps stay recognisable',
      () {
        expect(after.migratedAt, ctx.fileModifiedAt);
      },
    );

    test('starts with no tombstones', () {
      expect(after.tombstones, isEmpty);
    });

    test('is idempotent — a v2 file passes through untouched', () {
      final once = migrateLibrary(before, ctx);
      final twice = migrateLibrary(once, ctx);
      expect(jsonEncode(twice), jsonEncode(once));
    });

    test('round-trips back to JSON at the new schema', () {
      final out = after.toJson();
      expect(out['schema'], kSchemaVersion);
      final reread = LibraryDatabase.fromJson(out);
      expect(reread.recipes, hasLength(after.recipes.length));
      expect(reread.recipes.first.stamp, after.recipes.first.stamp);
    });
  });

  group('migrating the real pantry', () {
    late Map<String, dynamic> before;
    late PantryDatabase after;

    setUp(() {
      before = fixture('pantry_v1_real.json');
      after = PantryDatabase.fromJson(migratePantry(before, ctx));
    });

    test('loses nothing', () {
      expect(after.items, hasLength((before['items'] as List).length));
      expect(after.items, isNotEmpty);
    });

    test('keeps macros, aliases and stock state intact', () {
      final raw = (before['items'] as List)
          .cast<Map<String, dynamic>>()
          .firstWhere((i) => i['calories'] != null);
      final item = after.items.firstWhere((i) => i.id == raw['id']);
      expect(item.calories, (raw['calories'] as num).toDouble());
      expect(item.aliases, (raw['aliases'] as List? ?? []).cast<String>());
      expect(item.basis.name, raw['basis']);
      expect(item.inStock, raw['inStock'] ?? true);
    });

    test('prefers enteredOn over the file mtime where it is older', () {
      // It is the only real per-record edit evidence anywhere in schema 1.
      final withEntry = (before['items'] as List)
          .cast<Map<String, dynamic>>()
          .where((i) => i['enteredOn'] != null)
          .toList();
      expect(withEntry, isNotEmpty, reason: 'fixture should exercise this');
      for (final raw in withEntry) {
        final entered = DateTime.parse(raw['enteredOn'] as String).toUtc();
        final item = after.items.firstWhere((i) => i.id == raw['id']);
        final expected = entered.isBefore(ctx.backfillAt)
            ? entered
            : ctx.backfillAt;
        expect(item.updatedAt, expected);
      }
    });

    test('assumeStaples becomes a register', () {
      expect(after.registers['assumeStaples'], isNotNull);
      expect(after.registers['assumeStaples']!.value, before['assumeStaples']);
      expect(after.staplesAssumed, before['assumeStaples']);
    });

    test('is idempotent', () {
      final once = migratePantry(before, ctx);
      expect(jsonEncode(migratePantry(once, ctx)), jsonEncode(once));
    });
  });

  group('JsonStore', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('recipe_book_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('writes and reads back', () async {
      final store = libraryStore(directory: dir);
      final db = LibraryDatabase(
        mealTypes: [MealType(id: 'm', name: 'Dinner', order: 0)],
      );
      await store.save(db);
      final read = await store.load(ctx);
      expect(read!.mealTypes.single.name, 'Dinner');
    });

    test('returns null when there is nothing saved', () async {
      expect(await libraryStore(directory: dir).load(ctx), isNull);
    });

    test('migrates a schema-1 file on load and keeps a backup', () async {
      final f = File('${dir.path}${Platform.pathSeparator}library.json');
      f.writeAsStringSync(jsonEncode(fixture('library_v1_real.json')));

      final loaded = await libraryStore(directory: dir).load(ctx);
      expect(loaded!.recipes, isNotEmpty);
      expect(loaded.recipes.first.stamp.isEpoch, isFalse);

      // The pre-migration file is kept: this runs against data the user cannot
      // get back any other way, on first launch, with nobody watching.
      expect(File('${f.path}.v1.bak').existsSync(), isTrue);

      // The upgrade is paid once — what is on disk is now v2.
      final onDisk = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      expect(schemaOf(onDisk), kSchemaVersion);
    });

    test(
      'refuses a file from a newer build instead of downgrading it',
      () async {
        // Decoding it with today's fromJson would silently drop every unknown
        // field, and saving would then write that loss to disk.
        final f = File('${dir.path}${Platform.pathSeparator}library.json');
        f.writeAsStringSync(jsonEncode({'schema': 99, 'recipes': <dynamic>[]}));
        expect(
          () => libraryStore(directory: dir).load(ctx),
          throwsA(isA<SchemaTooNewException>()),
        );
      },
    );
  });
}
