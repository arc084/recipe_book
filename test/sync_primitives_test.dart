import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/domain/sync/stamp.dart';
import 'package:recipe_book/domain/sync/tombstone.dart';

DateTime t(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

void main() {
  group('Stamp ordering', () {
    test('orders by time first', () {
      expect(Stamp(t(2), 'a') > Stamp(t(1), 'z'), isTrue);
    });

    test('breaks a same-millisecond tie on the device id', () {
      // Without this the two devices each keep their own copy forever: the
      // stamps compare equal while the content differs.
      final a = Stamp(t(5), 'aaa');
      final b = Stamp(t(5), 'bbb');
      expect(a < b, isTrue);
      expect(Stamp.max(a, b), b);
      // And the answer is the same whichever side asks.
      expect(Stamp.max(b, a), b);
    });

    test('epoch loses to anything real', () {
      expect(Stamp.epoch < Stamp(t(1), 'a'), isTrue);
    });

    test('round-trips through JSON', () {
      final json = <String, dynamic>{};
      Stamp(t(1750000000000), 'device-1').writeInto(json);
      expect(Stamp.tryRead(json), Stamp(t(1750000000000), 'device-1'));
    });

    test('reads as null when the record has no stamp', () {
      expect(Stamp.tryRead(<String, dynamic>{'id': 'x'}), isNull);
    });
  });

  group('DeviceClock', () {
    test('never issues the same stamp twice', () {
      final clock = DeviceClock(deviceId: 'd', now: () => t(1000));
      final a = clock.next();
      final b = clock.next();
      expect(b > a, isTrue);
    });

    test('keeps moving forward when the system clock jumps backwards', () {
      // An NTP correction or a timezone fix must not produce a stamp that can
      // never win again.
      var wall = t(5000);
      final clock = DeviceClock(deviceId: 'd', now: () => wall);
      final before = clock.next();
      wall = t(1000);
      final after = clock.next();
      expect(after > before, isTrue);
    });

    test('seeding lifts it above what is already on disk', () {
      final clock = DeviceClock(deviceId: 'd', now: () => t(1000));
      clock.seed(Stamp(t(9000), 'other'));
      expect(clock.next() > Stamp(t(9000), 'other'), isTrue);
    });
  });

  group('tombstone GC', () {
    final now = t(100 * 24 * 3600 * 1000); // day 100

    Tombstone stone(
      String id,
      int day, {
      EntityKind kind = EntityKind.recipe,
    }) => Tombstone(
      kind: kind,
      id: id,
      stamp: Stamp(t(day * 24 * 3600 * 1000), 'd'),
    );

    test('keeps one a peer has not seen yet', () {
      final kept = gcTombstones(
        [stone('r', 99)],
        peerLastSync: [t(98 * 24 * 3600 * 1000)],
        liveReferencedIds: const {},
        now: now,
      );
      expect(kept, hasLength(1));
    });

    test('drops one every peer has seen and that is past retention', () {
      final kept = gcTombstones(
        [stone('r', 1)],
        peerLastSync: [t(99 * 24 * 3600 * 1000)],
        liveReferencedIds: const {},
        now: now,
      );
      expect(kept, isEmpty);
    });

    test('keeps one still named by a live cross-reference', () {
      final kept = gcTombstones(
        [stone('r', 1)],
        peerLastSync: [t(99 * 24 * 3600 * 1000)],
        liveReferencedIds: const {'r'},
        now: now,
      );
      expect(kept, hasLength(1));
    });

    test('groceries expire sooner than recipes', () {
      // clearChecked empties the list wholesale, so at recipe retention these
      // would quickly outnumber everything else in the file.
      expect(
        retentionFor(EntityKind.grocery) < retentionFor(EntityKind.recipe),
        isTrue,
      );
      final kept = gcTombstones(
        [stone('g', 80, kind: EntityKind.grocery), stone('r', 80)],
        peerLastSync: [t(99 * 24 * 3600 * 1000)],
        liveReferencedIds: const {},
        now: now,
      );
      expect(kept.map((s) => s.id), ['r']);
    });

    test('with no peers, only the retention floor applies', () {
      final kept = gcTombstones(
        [stone('recent', 99), stone('old', 1)],
        peerLastSync: const [],
        liveReferencedIds: const {},
        now: now,
      );
      expect(kept.map((s) => s.id), ['recent']);
    });
  });

  group('Register', () {
    test('higher stamp wins', () {
      final a = Register(true, Stamp(t(1), 'a'));
      final b = Register(false, Stamp(t(2), 'b'));
      expect(Register.max(a, b).value, false);
      expect(Register.max(b, a).value, false);
    });
  });
}
