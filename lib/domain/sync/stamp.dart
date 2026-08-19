/// When a record last changed, and which device changed it.
///
/// This is the whole basis of conflict resolution, so it is deliberately small:
/// a time and an author, ordered as a pair.
library;

/// A record's modification mark.
///
/// Ordering is `(at, by)` — `by` is not decoration. Two devices editing in the
/// same millisecond would otherwise compare equal while holding different
/// content, and each would keep its own copy forever. Breaking the tie on the
/// device id is arbitrary but it is the *same* arbitrary answer on both sides,
/// which is all convergence needs.
class Stamp implements Comparable<Stamp> {
  Stamp(DateTime at, this.by) : at = at.toUtc();

  /// Always UTC, at millisecond precision — the precision JSON round-trips.
  final DateTime at;

  /// The `deviceId` of whoever wrote it.
  final String by;

  /// The stamp a record carries before it has ever been stamped. Anything real
  /// sorts above it, so a migrated record never beats a genuine edit.
  static final Stamp epoch = Stamp(
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    '',
  );

  bool get isEpoch => at.millisecondsSinceEpoch == 0 && by.isEmpty;

  @override
  int compareTo(Stamp other) {
    final byTime = at.compareTo(other.at);
    return byTime != 0 ? byTime : by.compareTo(other.by);
  }

  bool operator >(Stamp o) => compareTo(o) > 0;
  bool operator <(Stamp o) => compareTo(o) < 0;
  bool operator >=(Stamp o) => compareTo(o) >= 0;
  bool operator <=(Stamp o) => compareTo(o) <= 0;

  static Stamp max(Stamp a, Stamp b) => a >= b ? a : b;
  static Stamp min(Stamp a, Stamp b) => a <= b ? a : b;

  @override
  bool operator ==(Object other) =>
      other is Stamp && other.at == at && other.by == by;

  @override
  int get hashCode => Object.hash(at, by);

  @override
  String toString() => '${at.toIso8601String()}@$by';

  /// Reads the flat `updatedAt` / `updatedBy` pair a record carries.
  ///
  /// Returns null when the record has neither — which is how a schema-1 record
  /// arriving through an un-migrated path is recognised.
  static Stamp? tryRead(Map<String, dynamic> json) {
    final at = json['updatedAt'];
    if (at is! String || at.isEmpty) return null;
    final parsed = DateTime.tryParse(at);
    if (parsed == null) return null;
    return Stamp(parsed, json['updatedBy'] as String? ?? '');
  }

  /// Writes the pair back, flat, so the files stay readable and hand-editable.
  void writeInto(Map<String, dynamic> json) {
    json['updatedAt'] = at.toIso8601String();
    json['updatedBy'] = by;
  }
}

/// Issues stamps that never go backwards on this device.
///
/// A system clock can move backwards — a timezone fix, an NTP correction, a
/// restored backup — and a record stamped in that window would be permanently
/// unable to win a conflict against the copy it just replaced. Folding a
/// counter into the millisecond field keeps the value a readable date while
/// still being monotonic, which is what a hybrid logical clock buys and why
/// there is no separate counter field in the JSON.
class DeviceClock {
  DeviceClock({required this.deviceId, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final String deviceId;
  final DateTime Function() _now;

  DateTime? _last;

  /// The next stamp: real time, or one millisecond past the last issued,
  /// whichever is later.
  Stamp next() {
    final wall = _now().toUtc();
    final last = _last;
    final at = (last == null || wall.isAfter(last))
        ? wall
        : last.add(const Duration(milliseconds: 1));
    _last = at;
    return Stamp(at, deviceId);
  }

  /// Primes the clock with the highest stamp already on disk.
  ///
  /// Without this, restoring an older backup — or a clock that jumped back
  /// between runs — would re-issue stamps below ones already written, and the
  /// records they belong to could never win again.
  void seed(Stamp highWater) {
    if (_last == null || highWater.at.isAfter(_last!)) _last = highWater.at;
  }
}
