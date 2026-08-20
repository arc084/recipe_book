import 'canonical_content.dart';
import 'stamp.dart';
import 'tombstone.dart';

/// One record, as the merge sees it: an identity, a stamp, and an opaque
/// payload. The merge never needs to understand a recipe — only whether two
/// copies differ and which is newer.
class StampedRecord {
  const StampedRecord({
    required this.kind,
    required this.id,
    required this.json,
    required this.stamp,
    required this.label,
  });

  final EntityKind kind;
  final String id;
  final Map<String, dynamic> json;
  final Stamp stamp;

  /// What to call it when asking the user — "Chicken Katsu", "Parmesan".
  final String label;

  StampedRecord withJson(Map<String, dynamic> json, {Stamp? stamp}) =>
      StampedRecord(
        kind: kind,
        id: json['id'] as String? ?? id,
        json: json,
        stamp: stamp ?? this.stamp,
        label: label,
      );
}

/// One database at one instant, in the shape the merge works on.
class DbSnapshot {
  const DbSnapshot({
    required this.entities,
    required this.tombstones,
    required this.registers,
    this.migratedAt,
  });

  final Map<String, StampedRecord> entities;
  final Map<String, Tombstone> tombstones;
  final Map<String, Register> registers;

  /// Every stamp at or below this was backfilled by a migration rather than
  /// observed. Null once the database has been written by a build that stamps.
  final DateTime? migratedAt;

  static const empty = DbSnapshot(entities: {}, tombstones: {}, registers: {});
}

/// Why two copies could not simply be reconciled.
enum ConflictReason {
  /// Both sides hold the record and their content differs.
  editEdit,

  /// One side deleted it, the other edited it after that delete.
  editDelete,
}

/// What to do about a tie.
///
/// There is no "keep both": it existed to serve a policy that no longer exists,
/// and on a tie it made *each* device the winner, so each minted a copy the
/// other had never seen and every exchange bred another one.
enum Resolution { takeLocal, takeRemote }

class Conflict {
  const Conflict({
    required this.kind,
    required this.id,
    required this.label,
    required this.reason,
    this.local,
    this.remote,
    this.localDelete,
    this.remoteDelete,
  });

  final EntityKind kind;
  final String id;
  final String label;
  final ConflictReason reason;

  /// Null when this side deleted the record.
  final StampedRecord? local;
  final StampedRecord? remote;
  final Tombstone? localDelete;
  final Tombstone? remoteDelete;
}

class MergeStats {
  MergeStats();

  final Map<EntityKind, int> added = {};
  final Map<EntityKind, int> updated = {};
  final Map<EntityKind, int> deleted = {};
  final Map<EntityKind, int> conflicted = {};

  void _bump(Map<EntityKind, int> counter, EntityKind kind) =>
      counter[kind] = (counter[kind] ?? 0) + 1;

  int get totalAdded => added.values.fold(0, (a, b) => a + b);
  int get totalUpdated => updated.values.fold(0, (a, b) => a + b);
  int get totalDeleted => deleted.values.fold(0, (a, b) => a + b);
  int get totalConflicted => conflicted.values.fold(0, (a, b) => a + b);
  bool get isEmpty => totalAdded == 0 && totalUpdated == 0 && totalDeleted == 0;
}

class MergePlan {
  const MergePlan({
    required this.result,
    required this.unresolved,
    required this.stats,
  });

  /// The merged database. Safe to apply as-is when [unresolved] is empty.
  final DbSnapshot result;

  /// Conflicts the policy would not settle on its own. Answer them and call
  /// [mergeDatabase] again with the answers — it replays rather than mutates,
  /// so abandoning a review leaves nothing half-applied.
  final List<Conflict> unresolved;

  final MergeStats stats;

  bool get isComplete => unresolved.isEmpty;
}

/// Reconciles two snapshots of the same database.
///
/// Pure: no clock, no randomness, no I/O. Identical inputs always produce an
/// identical plan, which is what makes syncing twice a genuine no-op and what
/// makes the property tests meaningful.
/// The newer copy wins. The only thing the merge ever asks about is a **tie**:
/// two copies carrying an identical stamp whose content differs, which the
/// timestamps cannot settle. Answer those and call this again with the answers
/// — it replays rather than mutates, so abandoning a review leaves nothing
/// half-applied.
MergePlan mergeDatabase(
  DbSnapshot local,
  DbSnapshot remote, {
  Map<String, Resolution> answers = const {},
}) {
  final entities = <String, StampedRecord>{};
  final unresolved = <Conflict>[];
  final stats = MergeStats();

  // Tombstones union unconditionally, and the earlier stamp wins so both sides
  // agree on when a thing died. Monotone growth is what makes this a lattice
  // join; only GC ever shrinks the set, and it runs outside the merge.
  final tombstones = <String, Tombstone>{...local.tombstones};
  for (final entry in remote.tombstones.entries) {
    final mine = tombstones[entry.key];
    tombstones[entry.key] = mine == null
        ? entry.value
        : (mine.stamp <= entry.value.stamp ? mine : entry.value);
  }

  final ids = <String>{
    ...local.entities.keys,
    ...remote.entities.keys,
    ...tombstones.keys,
  };

  for (final id in ids) {
    final mine = local.entities[id];
    final theirs = remote.entities[id];
    final grave = tombstones[id];

    // ── Neither side still holds it ────────────────────────────────────────
    if (mine == null && theirs == null) continue;

    // ── Deleted somewhere ──────────────────────────────────────────────────
    if (grave != null) {
      final survivor = _laterOf(mine, theirs);
      if (survivor == null) continue;

      if (survivor.stamp < grave.stamp) {
        // The surviving copy predates the delete, so the delete is simply news
        // the other side has not had yet.
        if (mine != null) stats._bump(stats.deleted, survivor.kind);
        continue;
      }

      // Edited strictly after the delete: the edit is newer, so it wins and the
      // record comes back. Only an exact tie has to be asked about.
      final resolution =
          answers[id] ??
          (survivor.stamp > grave.stamp ? Resolution.takeLocal : null);

      if (resolution == null) {
        unresolved.add(
          Conflict(
            kind: survivor.kind,
            id: id,
            label: survivor.label,
            reason: ConflictReason.editDelete,
            local: mine,
            remote: theirs,
            localDelete: local.tombstones[id],
            remoteDelete: remote.tombstones[id],
          ),
        );
        // Hold the record until it is answered; dropping it here would lose an
        // edit if the user never finishes the review.
        entities[id] = survivor;
        stats._bump(stats.conflicted, survivor.kind);
        continue;
      }

      // Keeping the edit resurrects the record; the tombstone goes with it.
      final keep = switch (resolution) {
        Resolution.takeRemote => theirs ?? survivor,
        Resolution.takeLocal => mine ?? survivor,
      };
      entities[id] = keep.withJson(preserveLocalFields(keep.json, mine?.json));
      tombstones.remove(id);
      if (mine == null) stats._bump(stats.added, keep.kind);
      continue;
    }

    // ── Only one side has it ───────────────────────────────────────────────
    if (theirs == null) {
      entities[id] = mine!;
      continue;
    }
    if (mine == null) {
      // Nothing local to preserve, but strip the peer's own paths: they name
      // directories that do not exist here.
      entities[id] = theirs.withJson(preserveLocalFields(theirs.json, null));
      stats._bump(stats.added, theirs.kind);
      continue;
    }

    // ── Both sides have it ─────────────────────────────────────────────────
    // Three outcomes, and only the last one ever reaches the user:
    //   stamps differ           -> the newer wins, silently
    //   stamps tie, same content-> nothing to do
    //   stamps tie, content differs -> a question
    if (mine.stamp != theirs.stamp) {
      entities[id] = mine.stamp > theirs.stamp
          ? mine
          : theirs.withJson(preserveLocalFields(theirs.json, mine.json));
      if (theirs.stamp > mine.stamp) stats._bump(stats.updated, theirs.kind);
      continue;
    }

    if (sameContent(mine.kind, mine.json, theirs.json)) {
      entities[id] = mine;
      continue;
    }

    // A genuine tie. Both devices reach this line together and neither stamp
    // can break it, so it is the user's call.
    final resolution = answers[id];
    if (resolution == null) {
      unresolved.add(
        Conflict(
          kind: mine.kind,
          id: id,
          label: mine.label,
          reason: ConflictReason.editEdit,
          local: mine,
          remote: theirs,
        ),
      );
      // Hold this device's copy until it is answered, so abandoning the review
      // loses nothing.
      entities[id] = mine;
      stats._bump(stats.conflicted, mine.kind);
      continue;
    }

    final winner = switch (resolution) {
      Resolution.takeLocal => mine,
      Resolution.takeRemote => theirs,
    };
    entities[id] = identical(winner, mine)
        ? winner
        : winner.withJson(preserveLocalFields(winner.json, mine.json));
    if (!identical(winner, mine)) stats._bump(stats.updated, winner.kind);
  }

  // Registers resolve by stamp and are never raised as a conflict — a modal
  // dialog over a toggle would be absurd.
  final registers = <String, Register>{...local.registers};
  for (final entry in remote.registers.entries) {
    final mine = registers[entry.key];
    registers[entry.key] = mine == null
        ? entry.value
        : Register.max(mine, entry.value);
  }

  return MergePlan(
    result: DbSnapshot(
      entities: entities,
      tombstones: tombstones,
      registers: registers,
      migratedAt: local.migratedAt,
    ),
    unresolved: unresolved,
    stats: stats,
  );
}

/// The copy that should stand against a tombstone.
///
/// Symmetric on purpose. On a stamp tie the two devices call this with the
/// arguments the other way round, so anything positional would have each keep
/// its own and never agree; the canonical content is the one thing both see
/// identically, so that is what breaks it.
StampedRecord? _laterOf(StampedRecord? a, StampedRecord? b) {
  if (a == null) return b;
  if (b == null) return a;
  if (a.stamp != b.stamp) return a.stamp > b.stamp ? a : b;
  return compareContent(a.kind, a.json, b.json) >= 0 ? a : b;
}
