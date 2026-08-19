import 'dart:convert';

import 'tombstone.dart';

/// Fields that must never take part in comparing two copies of a record.
///
/// `photoPath` is the important one. It is an absolute path built from the
/// app's own storage directory and a timestamp, so it differs between a
/// Windows install and an Android one *by construction* — comparing it would
/// make every photographed recipe a conflict that can never be settled, no
/// matter which side won last time. `photoHash` is compared in its place.
const _nonPortable = <String>{'photoPath', 'updatedAt', 'updatedBy'};

/// Lists whose order carries no meaning, so two devices that added the same
/// members in a different sequence still compare equal.
const _unorderedStringLists = <String>{'tags', 'aliases', 'sources'};

/// Lists of records that carry their own `order` field. They are sorted by
/// `(order, id)` — the same total order every consumer uses — so that two
/// devices holding the same recipe compare equal regardless of how the JSON
/// happened to be written.
const _orderedRecordLists = <String>{'components', 'ingredients', 'steps'};

/// A record's content, with everything that is not content stripped out and
/// every list put in a fixed order.
///
/// This does two jobs at once. It stops the user being asked to resolve a
/// difference that is not one, and it is what lets "same content, different
/// stamp" settle on the higher stamp instead of oscillating forever.
Object? canonicalContent(EntityKind kind, Map<String, dynamic> json) =>
    _canonical(json);

/// Whether two copies of a record hold the same thing.
bool sameContent(
  EntityKind kind,
  Map<String, dynamic> a,
  Map<String, dynamic> b,
) =>
    jsonEncode(canonicalContent(kind, a)) ==
    jsonEncode(canonicalContent(kind, b));

Object? _canonical(Object? value) {
  if (value is Map) {
    final out = <String, Object?>{};
    final keys = value.keys.map((k) => '$k').toList()..sort();
    for (final key in keys) {
      if (_nonPortable.contains(key)) continue;
      final v = value[key];
      if (v == null) continue; // absent and null are the same thing here
      if (_unorderedStringLists.contains(key) && v is List) {
        out[key] = [for (final e in v) '$e']..sort();
      } else if (_orderedRecordLists.contains(key) && v is List) {
        out[key] = _sortedRecords(v);
      } else {
        out[key] = _canonical(v);
      }
    }
    return out;
  }

  if (value is List) return [for (final e in value) _canonical(e)];

  // Whole doubles and ints must not read as different values: JSON gives back
  // 4 or 4.0 depending on how it was written.
  if (value is num && value == value.roundToDouble()) return value.toInt();

  return value;
}

List<Object?> _sortedRecords(List<dynamic> records) {
  final sorted = [...records];
  sorted.sort((a, b) {
    if (a is! Map || b is! Map) return 0;
    final byOrder = ((a['order'] as num?) ?? 0).compareTo(
      (b['order'] as num?) ?? 0,
    );
    if (byOrder != 0) return byOrder;
    return '${a['id']}'.compareTo('${b['id']}');
  });
  return [for (final r in sorted) _canonical(r)];
}
