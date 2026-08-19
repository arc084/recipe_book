import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../data/settings.dart';
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

/// What to do about a conflict.
enum Resolution { takeLocal, takeRemote, keepBoth }

class Conflict {
  const Conflict({
    required this.kind,
    required this.id,
    required this.label,
    required this.reason,
    required this.suggested,
    this.local,
    this.remote,
    this.localDelete,
    this.remoteDelete,
  });

  final EntityKind kind;
  final String id;
  final String label;
  final ConflictReason reason;

  /// What the configured policy would do unaided — the option the review UI
  /// should preselect.
  final Resolution suggested;

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

/// Invents identity for the records "keep both" has to create.
///
/// **Every method must be a pure function of its arguments.** Both devices run
/// this merge independently over the same pair of records, and they have to
/// arrive at the *same* id for the copy. If they do not, each device mints a
/// copy the other has never seen, that copy syncs back, and every exchange
/// breeds another one. A timestamp or a random uuid here would be a bug that
/// only shows up on the third sync.
abstract class MergeMint {
  const MergeMint();

  String copyId(String originalId, Stamp loser);
  String nestedId(String newRecipeId, String originalNestedId);
  Stamp copyStamp(Stamp winner, Stamp loser);
}

class DeterministicMint extends MergeMint {
  const DeterministicMint();

  String _hash(String input) =>
      sha256.convert(utf8.encode(input)).toString().substring(0, 32);

  @override
  String copyId(String originalId, Stamp loser) =>
      'copy-${_hash('$originalId|$loser|keepBoth')}';

  @override
  String nestedId(String newRecipeId, String originalNestedId) =>
      'copy-${_hash('$newRecipeId|$originalNestedId')}';

  /// One millisecond past the winner, authored by the losing device. Strictly
  /// above both inputs so the copy is not immediately overwritten, and derived
  /// rather than clock-read so both devices agree.
  @override
  Stamp copyStamp(Stamp winner, Stamp loser) =>
      Stamp(winner.at.add(const Duration(milliseconds: 1)), loser.by);
}

/// Reconciles two snapshots of the same database.
///
/// Pure: no clock, no randomness, no I/O. Identical inputs always produce an
/// identical plan, which is what makes syncing twice a genuine no-op and what
/// makes the property tests meaningful.
MergePlan mergeDatabase(
  DbSnapshot local,
  DbSnapshot remote, {
  required ConflictPolicy policy,
  Map<String, Resolution> answers = const {},
  MergeMint mint = const DeterministicMint(),

  /// Names the peer, only so a keep-both copy can say where it came from.
  String remoteLabel = 'the other device',
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

      if (survivor.stamp <= grave.stamp) {
        // The surviving copy predates the delete, so the delete is simply news
        // the other side has not had yet.
        if (mine != null) stats._bump(stats.deleted, survivor.kind);
        continue;
      }

      // Edited after it was deleted somewhere else. Someone has to choose.
      final resolution =
          answers[id] ??
          _autoResolveDelete(policy: policy, edit: survivor, grave: grave);

      if (resolution == null) {
        unresolved.add(
          Conflict(
            kind: survivor.kind,
            id: id,
            label: survivor.label,
            reason: ConflictReason.editDelete,
            suggested: Resolution.takeLocal,
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

      if (resolution == Resolution.keepBoth ||
          resolution == Resolution.takeLocal ||
          resolution == Resolution.takeRemote) {
        // Keep-both's premise is that nothing is thrown away, so an edit that
        // raced a delete is resurrected rather than dropped.
        final keep = switch (resolution) {
          Resolution.takeRemote => theirs ?? survivor,
          Resolution.takeLocal => mine ?? survivor,
          Resolution.keepBoth => survivor,
        };
        entities[id] = keep;
        tombstones.remove(id);
        if (mine == null) stats._bump(stats.added, keep.kind);
      }
      continue;
    }

    // ── Only one side has it ───────────────────────────────────────────────
    if (theirs == null) {
      entities[id] = mine!;
      continue;
    }
    if (mine == null) {
      entities[id] = theirs;
      stats._bump(stats.added, theirs.kind);
      continue;
    }

    // ── Both sides have it ─────────────────────────────────────────────────
    if (mine.stamp == theirs.stamp) {
      entities[id] = mine;
      continue;
    }

    if (sameContent(mine.kind, mine.json, theirs.json)) {
      // Same thing, differently stamped. Converging on the higher stamp is
      // what stops this pair oscillating on every future exchange.
      entities[id] = mine.stamp >= theirs.stamp ? mine : theirs;
      continue;
    }

    final resolution =
        answers[id] ?? _autoResolve(policy, mine.stamp, theirs.stamp);
    if (resolution == null) {
      unresolved.add(
        Conflict(
          kind: mine.kind,
          id: id,
          label: mine.label,
          reason: ConflictReason.editEdit,
          suggested: mine.stamp >= theirs.stamp
              ? Resolution.takeLocal
              : Resolution.takeRemote,
          local: mine,
          remote: theirs,
        ),
      );
      entities[id] = mine;
      stats._bump(stats.conflicted, mine.kind);
      continue;
    }

    final winner = switch (resolution) {
      Resolution.takeLocal => mine,
      Resolution.takeRemote => theirs,
      Resolution.keepBoth => mine.stamp >= theirs.stamp ? mine : theirs,
    };
    final loser = identical(winner, mine) ? theirs : mine;

    entities[id] = winner;
    if (!identical(winner, mine)) stats._bump(stats.updated, winner.kind);

    if (resolution == Resolution.keepBoth && _canKeepBoth(mine.kind)) {
      final copy = _materialiseCopy(loser, winner, mint, remoteLabel);
      entities[copy.id] = copy;
      stats._bump(stats.added, copy.kind);
    }
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

StampedRecord? _laterOf(StampedRecord? a, StampedRecord? b) {
  if (a == null) return b;
  if (b == null) return a;
  return a.stamp >= b.stamp ? a : b;
}

/// What the policy decides on its own. Null means the user has to be asked.
Resolution? _autoResolve(ConflictPolicy policy, Stamp mine, Stamp theirs) =>
    switch (policy) {
      ConflictPolicy.ask => null,
      ConflictPolicy.newestWins =>
        mine >= theirs ? Resolution.takeLocal : Resolution.takeRemote,
      ConflictPolicy.keepBoth => Resolution.keepBoth,
    };

Resolution? _autoResolveDelete({
  required ConflictPolicy policy,
  required StampedRecord edit,
  required Tombstone grave,
}) => switch (policy) {
  ConflictPolicy.ask => null,
  ConflictPolicy.newestWins =>
    edit.stamp > grave.stamp ? Resolution.takeLocal : null,
  ConflictPolicy.keepBoth => Resolution.keepBoth,
};

/// Keep-both only makes sense where a duplicate is useful.
///
/// Two "Dinner" categories or two "Produce" aisles are worse than losing a
/// rename, and two plan entries in the same slot would break the assumption of
/// one recipe per slot that the meal plan reads on. Those four take the newest
/// instead, and Settings says so.
bool _canKeepBoth(EntityKind kind) =>
    kind == EntityKind.recipe || kind == EntityKind.pantryItem;

/// Builds the second copy that keep-both promises.
StampedRecord _materialiseCopy(
  StampedRecord loser,
  StampedRecord winner,
  MergeMint mint,
  String remoteLabel,
) {
  final newId = mint.copyId(winner.id, loser.stamp);
  final json = Map<String, dynamic>.from(loser.json)..['id'] = newId;
  final from = loser.stamp.by == winner.stamp.by ? 'copy' : 'from $remoteLabel';

  if (loser.kind == EntityKind.recipe) {
    json['title'] = '${loser.json['title']} ($from)';
    _remintRecipeInternals(json, newId, mint);
  } else {
    json['name'] = '${loser.json['name']} ($from)';
    // The copy deliberately loses its other known names: two pantry items both
    // answering to "parmesan" would make name matching — and so import linking
    // and clearing the shopping list — depend on which one was found first.
    json['aliases'] = <String>[];
  }

  final stamp = mint.copyStamp(winner.stamp, loser.stamp);
  stamp.writeInto(json);

  return StampedRecord(
    kind: loser.kind,
    id: newId,
    json: json,
    stamp: stamp,
    label: (json['title'] ?? json['name']) as String,
  );
}

/// Re-mints a copied recipe's components, ingredients and steps so the copy
/// does not share sub-record ids with the original.
void _remintRecipeInternals(
  Map<String, dynamic> json,
  String newRecipeId,
  MergeMint mint,
) {
  final componentIds = <String, String>{};

  json['components'] = [
    for (final c in (json['components'] as List? ?? []))
      if (c is Map<String, dynamic>)
        () {
          final old = c['id'] as String;
          final fresh = mint.nestedId(newRecipeId, old);
          componentIds[old] = fresh;
          return Map<String, dynamic>.from(c)
            ..['id'] = fresh
            ..['recipeId'] = newRecipeId;
        }(),
  ];

  for (final key in const ['ingredients', 'steps']) {
    json[key] = [
      for (final e in (json[key] as List? ?? []))
        if (e is Map<String, dynamic>)
          Map<String, dynamic>.from(e)
            ..['id'] = mint.nestedId(newRecipeId, e['id'] as String)
            ..['componentId'] =
                componentIds[e['componentId']] ?? e['componentId'],
    ];
  }
}
