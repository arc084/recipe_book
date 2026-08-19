import '../domain/sync/stamp.dart';
import '../domain/sync/tombstone.dart';

/// The schema the current build reads and writes.
///
/// 1 — the original files: records with ids and nothing else.
/// 2 — every record carries `updatedAt`/`updatedBy`, and the envelope carries
///     tombstones and registers, so the two devices can be reconciled.
const int kSchemaVersion = 2;

/// The version a file claims. Schema 1 predates the key, so its absence means 1.
int schemaOf(Map<String, dynamic> raw) => (raw['schema'] as num?)?.toInt() ?? 1;

/// Refuses a file written by a newer build rather than quietly discarding
/// every field this build does not know about.
class SchemaTooNewException implements Exception {
  const SchemaTooNewException({required this.found, required this.supported});

  final int found;
  final int supported;

  @override
  String toString() =>
      'This file was written by a newer version of Recipe Book '
      '(format $found; this build reads $supported). Update the app and try '
      'again — nothing has been changed.';
}

/// What a migration needs from the outside world, passed in so the migration
/// functions stay pure and testable.
class MigrationContext {
  const MigrationContext({
    required this.deviceId,
    required this.now,
    this.fileModifiedAt,
  });

  final String deviceId;
  final DateTime now;

  /// When the file was last written. This is the backfill's best evidence of
  /// when its records were last touched.
  final DateTime? fileModifiedAt;

  /// The time every backfilled record is stamped at.
  ///
  /// The file's own mtime, **not** `now`. Stamping at `now` would mark each
  /// device's whole corpus at the moment that device happened to launch, so
  /// the first reconciliation would be decided by launch order rather than by
  /// anything the user did.
  DateTime get backfillAt => (fileModifiedAt ?? now).toUtc();
}

// ═══════════════════════════════════════════════════════════════════════════
// 1 → 2
// ═══════════════════════════════════════════════════════════════════════════

/// Brings `library.json` up to the current schema. Pure `Map` → `Map`.
///
/// Idempotent: a file already at [kSchemaVersion] is returned untouched.
Map<String, dynamic> migrateLibrary(
  Map<String, dynamic> raw,
  MigrationContext ctx,
) {
  if (schemaOf(raw) >= kSchemaVersion) return raw;

  final out = Map<String, dynamic>.from(raw);
  final base = Stamp(ctx.backfillAt, ctx.deviceId);

  for (final key in const [
    'recipes',
    'mealTypes',
    'aisles',
    'groceries',
    'plan',
  ]) {
    out[key] = _stampEach(out[key], (_) => base);
  }

  return _finishEnvelope(out, ctx);
}

/// Brings `pantry.json` up to the current schema.
Map<String, dynamic> migratePantry(
  Map<String, dynamic> raw,
  MigrationContext ctx,
) {
  if (schemaOf(raw) >= kSchemaVersion) return raw;

  final out = Map<String, dynamic>.from(raw);
  final base = Stamp(ctx.backfillAt, ctx.deviceId);

  out['items'] = _stampEach(out['items'], (item) {
    // `enteredOn` is the one piece of real per-record edit evidence anywhere in
    // schema 1 — it is written when macros are saved. Where it exists and
    // predates the file's mtime, it is the better answer.
    final entered = DateTime.tryParse(item['enteredOn'] as String? ?? '');
    if (entered == null) return base;
    final at = entered.toUtc();
    return Stamp(at.isBefore(base.at) ? at : base.at, ctx.deviceId);
  });

  // `assumeStaples` is a bare bool with no id, so it syncs as a register.
  out['registers'] = <String, dynamic>{
    'assumeStaples': Register(raw['assumeStaples'] ?? true, base).toJson(),
  };

  return _finishEnvelope(out, ctx);
}

/// Stamps every record in a list, leaving any that already carry one alone.
List<dynamic> _stampEach(
  Object? list,
  Stamp Function(Map<String, dynamic> record) stampFor,
) {
  if (list is! List) return const [];
  return [
    for (final entry in list)
      if (entry is Map<String, dynamic>) _stamped(entry, stampFor) else entry,
  ];
}

Map<String, dynamic> _stamped(
  Map<String, dynamic> record,
  Stamp Function(Map<String, dynamic>) stampFor,
) {
  if (Stamp.tryRead(record) != null) return record;
  final out = Map<String, dynamic>.from(record);
  stampFor(record).writeInto(out);
  return out;
}

Map<String, dynamic> _finishEnvelope(
  Map<String, dynamic> out,
  MigrationContext ctx,
) {
  out['schema'] = kSchemaVersion;
  // Nothing was deleted before deletions were recorded, so there is nothing to
  // backfill here — but the key must exist so later writes have somewhere to go.
  out['tombstones'] ??= <dynamic>[];
  out['registers'] ??= <String, dynamic>{};
  // Remembered so a later reconciliation can tell a real edit from a
  // backfilled one: every stamp at or below this was invented, not observed.
  out['migratedAt'] = ctx.backfillAt.toIso8601String();
  out['writtenBy'] = ctx.deviceId;
  return out;
}
