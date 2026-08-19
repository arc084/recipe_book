import '../../data/database.dart';
import '../../data/models.dart';
import 'merge.dart';
import 'tombstone.dart';

/// Converts between the app's databases and the shape [mergeDatabase] works
/// on.
///
/// The merge deliberately knows nothing about recipes or pantry items — it
/// sees ids, stamps and opaque payloads — so all the model-specific knowledge
/// lives here, in one place, and both directions sit next to each other where
/// a mismatch is obvious.
extension LibrarySnapshot on LibraryDatabase {
  DbSnapshot toSnapshot() {
    final entities = <String, StampedRecord>{};

    void add(
      EntityKind kind,
      Stamped e,
      Map<String, dynamic> json,
      String label,
    ) {
      entities[e.id] = StampedRecord(
        kind: kind,
        id: e.id,
        json: json,
        stamp: e.stamp,
        label: label,
      );
    }

    for (final r in recipes) {
      add(EntityKind.recipe, r, r.toJson(), r.title);
    }
    for (final m in mealTypes) {
      add(EntityKind.mealType, m, m.toJson(), m.name);
    }
    for (final a in aisles) {
      add(EntityKind.aisle, a, a.toJson(), a.name);
    }
    for (final g in groceries) {
      add(EntityKind.grocery, g, g.toJson(), g.name);
    }
    for (final p in plan) {
      add(EntityKind.planEntry, p, p.toJson(), p.slot.label);
    }

    return DbSnapshot(
      entities: entities,
      tombstones: {for (final t in tombstones) t.id: t},
      registers: const {},
      migratedAt: migratedAt,
    );
  }
}

extension PantrySnapshot on PantryDatabase {
  DbSnapshot toSnapshot() => DbSnapshot(
    entities: {
      for (final i in items)
        i.id: StampedRecord(
          kind: EntityKind.pantryItem,
          id: i.id,
          json: i.toJson(),
          stamp: i.stamp,
          label: i.name,
        ),
    },
    tombstones: {for (final t in tombstones) t.id: t},
    registers: registers,
    migratedAt: migratedAt,
  );
}

/// Rebuilds a library from a merged snapshot.
///
/// Records are read back through the same `fromJson` the files use, so
/// anything the merge carried through untouched is decoded exactly as it would
/// be on load — there is no second, divergent parsing path.
LibraryDatabase libraryFromSnapshot(DbSnapshot s) {
  final db = LibraryDatabase(
    tombstones: s.tombstones.values.toList(),
    migratedAt: s.migratedAt,
  );

  for (final record in s.entities.values) {
    switch (record.kind) {
      case EntityKind.recipe:
        db.recipes.add(Recipe.fromJson(record.json));
      case EntityKind.mealType:
        db.mealTypes.add(MealType.fromJson(record.json));
      case EntityKind.aisle:
        db.aisles.add(Aisle.fromJson(record.json));
      case EntityKind.grocery:
        db.groceries.add(GroceryItem.fromJson(record.json));
      case EntityKind.planEntry:
        db.plan.add(PlanEntry.fromJson(record.json));
      case EntityKind.pantryItem:
        // Wrong database. Dropping it is right: the two are merged separately
        // and a pantry item here would be a bug in the caller, not data.
        break;
    }
  }

  return db;
}

/// Rebuilds a pantry from a merged snapshot.
PantryDatabase pantryFromSnapshot(DbSnapshot s) {
  final db = PantryDatabase(
    tombstones: s.tombstones.values.toList(),
    registers: Map<String, Register>.from(s.registers),
    migratedAt: s.migratedAt,
  );

  for (final record in s.entities.values) {
    if (record.kind != EntityKind.pantryItem) continue;
    db.items.add(PantryItem.fromJson(record.json));
  }

  // The register is the value that syncs; keep the plain field in step so an
  // older build reading this file still sees the right thing.
  final assumed = s.registers['assumeStaples']?.value;
  if (assumed is bool) db.assumeStaples = assumed;

  return db;
}
