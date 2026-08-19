import 'stamp.dart';

/// The kinds of record the merge treats as a syncable unit.
///
/// A recipe's components, ingredients and steps are deliberately absent: a
/// recipe syncs as one whole tree, so those never need ids that agree across
/// devices.
enum EntityKind {
  recipe,
  mealType,
  aisle,
  grocery,
  planEntry,
  pantryItem;

  /// Defensive, in the same shape as the model enums: an unknown string from a
  /// newer build must not throw on load.
  static EntityKind? parse(String? s) {
    for (final k in EntityKind.values) {
      if (k.name == s) return k;
    }
    return null;
  }

  /// Which database this kind lives in. The two are merged separately.
  bool get isLibrary => this != EntityKind.pantryItem;
  bool get isPantry => this == EntityKind.pantryItem;
}

/// A record of a deletion.
///
/// Deletions have to be represented explicitly or they cannot travel: a record
/// simply missing on one side is indistinguishable from one the other side has
/// not seen yet, so without this every delete would be undone by the next
/// exchange.
///
/// These live in a top-level array of the database file they belong to, rather
/// than in a file of their own, so that exporting a library and importing it
/// elsewhere carries its deletions with it instead of resurrecting rows.
class Tombstone {
  const Tombstone({required this.kind, required this.id, required this.stamp});

  final EntityKind kind;

  /// The id of the record that was deleted.
  final String id;

  /// When it was deleted, and by which device.
  final Stamp stamp;

  static Tombstone? tryFromJson(Map<String, dynamic> j) {
    final kind = EntityKind.parse(j['kind'] as String?);
    final id = j['id'];
    final stamp = Stamp.tryRead(j);
    if (kind == null || id is! String || stamp == null) return null;
    return Tombstone(kind: kind, id: id, stamp: stamp);
  }

  Map<String, dynamic> toJson() {
    final j = <String, dynamic>{'kind': kind.name, 'id': id};
    stamp.writeInto(j);
    return j;
  }

  @override
  String toString() => 'Tombstone(${kind.name} $id @ $stamp)';
}

/// A single scalar that syncs, with the stamp that decides who wins.
///
/// `PantryDatabase.assumeStaples` is a bare bool rather than a record, so it
/// has no id to merge on and needs somewhere of its own to live. Registers
/// resolve by higher stamp and are never raised as a conflict — a modal over a
/// toggle would be absurd.
class Register {
  const Register(this.value, this.stamp);

  /// A JSON primitive: bool, num or String.
  final Object? value;
  final Stamp stamp;

  static Register? tryFromJson(Map<String, dynamic> j) {
    final stamp = Stamp.tryRead(j);
    if (stamp == null) return null;
    return Register(j['value'], stamp);
  }

  Map<String, dynamic> toJson() {
    final j = <String, dynamic>{'value': value};
    stamp.writeInto(j);
    return j;
  }

  /// Higher stamp wins. Silent by design.
  static Register max(Register a, Register b) => a.stamp >= b.stamp ? a : b;
}

/// Drops tombstones that every paired device has certainly seen.
///
/// Pure: the caller supplies the peers' watermarks and the current time, so
/// this is testable and so the merge itself never shrinks the tombstone set —
/// monotone growth inside the merge is what makes it a lattice join.
///
/// A tombstone is kept while any of these hold:
///   * some peer's last sync predates it, so that peer has not seen it yet;
///   * it is younger than the retention floor for its kind;
///   * its id is still named by a live cross-reference, mid-repair.
List<Tombstone> gcTombstones(
  Iterable<Tombstone> all, {
  required Iterable<DateTime> peerLastSync,
  required Set<String> liveReferencedIds,
  required DateTime now,
}) {
  // With no peers there is nobody left to inform, so only the retention floor
  // applies.
  DateTime? oldestPeer;
  for (final t in peerLastSync) {
    if (oldestPeer == null || t.isBefore(oldestPeer)) oldestPeer = t;
  }

  return [
    for (final t in all)
      if (_keep(t, oldestPeer, liveReferencedIds, now)) t,
  ];
}

bool _keep(
  Tombstone t,
  DateTime? oldestPeer,
  Set<String> liveReferencedIds,
  DateTime now,
) {
  if (liveReferencedIds.contains(t.id)) return true;
  if (oldestPeer != null && t.stamp.at.isAfter(oldestPeer)) return true;
  return t.stamp.at.isAfter(now.toUtc().subtract(retentionFor(t.kind)));
}

/// How long a deletion is remembered.
///
/// Groceries get a short window on purpose: `clearChecked` empties the list
/// wholesale and every cleared item leaves a tombstone, so at the same
/// retention as recipes they would quickly dominate the file.
Duration retentionFor(EntityKind kind) => kind == EntityKind.grocery
    ? const Duration(days: 14)
    : const Duration(days: 90);
