import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/domain/sync/stamp.dart';
import 'package:recipe_book/state/app_state.dart';

/// The meal plan across two devices.
///
/// Plan entries were the one collection that travelled but never converged:
/// `setPlan` and `movePlan` saved without naming the record they changed, so
/// every entry sat at [Stamp.epoch] for life. An edited slot then tied on both
/// devices and raised a conflict *about a meal slot*, and any edit lost to any
/// delete, because epoch is older than every tombstone.
void main() {
  late Directory dirA;
  late Directory dirB;
  late AppState a;
  late AppState b;

  // A Monday a year out. Fixed dates here were a time bomb: the seed plants
  // "this week's plan" around DateTime.now(), so the day the calendar reached
  // the hardcoded week, tuesday-dinner was suddenly occupied by seed data and
  // the move-into-empty-slot test was silently testing a swap. (CI's UTC
  // clock got there a day before local time did.)
  DateTime nextYearMonday() {
    final now = DateTime.now();
    return DateTime(
      now.year,
      now.month,
      now.day,
    ).add(Duration(days: 8 - now.weekday + 364));
  }

  final monday = nextYearMonday();
  final tuesday = nextYearMonday().add(const Duration(days: 1));

  Future<void> pair() async {
    final libPath = '${dirA.path}${Platform.pathSeparator}lib-export.json';
    final panPath = '${dirA.path}${Platform.pathSeparator}pan-export.json';
    await a.exportLibrary(libPath);
    await a.exportPantry(panPath);
    await b.adoptFrom(libraryPath: libPath, pantryPath: panPath);
  }

  Future<int> sync(AppState into, AppState from) async {
    final plan = into.planMerge(from.library, from.pantry);
    await into.applyMerge(plan.library, plan.pantry);
    return plan.library.unresolved.length + plan.pantry.unresolved.length;
  }

  setUp(() async {
    dirA = Directory.systemTemp.createTempSync('rb_plan_a');
    dirB = Directory.systemTemp.createTempSync('rb_plan_b');
    a = AppState(directory: dirA);
    b = AppState(directory: dirB);
    await a.load();
    await b.load();
    await pair();
  });

  tearDown(() async {
    await a.flush();
    await b.flush();
    dirA.deleteSync(recursive: true);
    dirB.deleteSync(recursive: true);
  });

  String someRecipe(AppState s, [int at = 0]) => s.library.recipes[at].id;

  group('stamping', () {
    test('filling an empty slot stamps the new entry', () {
      a.setPlan(monday, MealSlot.dinner, someRecipe(a));

      final entry = a.planAt(monday, MealSlot.dinner)!;
      expect(entry.stamp, isNot(Stamp.epoch));
      expect(entry.stamp.by, a.settings.deviceId);
    });

    test('changing a filled slot stamps it again, strictly later', () {
      a.setPlan(monday, MealSlot.dinner, someRecipe(a, 0));
      final first = a.planAt(monday, MealSlot.dinner)!.stamp;

      a.setPlan(monday, MealSlot.dinner, someRecipe(a, 1));
      final second = a.planAt(monday, MealSlot.dinner)!.stamp;

      expect(second > first, isTrue);
    });

    test('moving into an empty slot stamps the entry that lands there', () {
      a.setPlan(monday, MealSlot.dinner, someRecipe(a));
      a.movePlan(monday, MealSlot.dinner, tuesday, MealSlot.dinner);

      expect(a.planAt(monday, MealSlot.dinner), isNull);
      final moved = a.planAt(tuesday, MealSlot.dinner)!;
      expect(moved.stamp, isNot(Stamp.epoch));
    });

    test('a swap stamps both halves, not just the one that was dragged', () {
      a.setPlan(monday, MealSlot.dinner, someRecipe(a, 0));
      a.setPlan(tuesday, MealSlot.dinner, someRecipe(a, 1));
      final before = a.planAt(tuesday, MealSlot.dinner)!.stamp;

      a.movePlan(monday, MealSlot.dinner, tuesday, MealSlot.dinner);

      // Naming only the dragged entry would leave the other device disagreeing
      // about the half that stayed put.
      expect(a.planAt(monday, MealSlot.dinner)!.stamp, isNot(Stamp.epoch));
      expect(a.planAt(tuesday, MealSlot.dinner)!.stamp > before, isTrue);
    });
  });

  group('one id per slot', () {
    test('both devices filling the same slot produce one record', () async {
      // Independently, while apart. With random ids these were two unrelated
      // records: the merge kept both, and the one `planAt` did not return sat
      // in the file with a stale recipe, ready to reappear.
      a.setPlan(monday, MealSlot.lunch, someRecipe(a, 0));
      b.setPlan(monday, MealSlot.lunch, someRecipe(b, 1));

      await sync(a, b);

      final atSlot = a.library.plan.where(
        (p) => a.dayOnly(p.date) == a.dayOnly(monday) && p.slot == MealSlot.lunch,
      );
      expect(atSlot.length, 1);
    });

    test('the id is derived from the slot, so both devices agree on it', () {
      a.setPlan(tuesday, MealSlot.breakfast, someRecipe(a));
      b.setPlan(tuesday, MealSlot.breakfast, someRecipe(b));

      expect(
        a.planAt(tuesday, MealSlot.breakfast)!.id,
        b.planAt(tuesday, MealSlot.breakfast)!.id,
      );
      expect(
        a.planAt(tuesday, MealSlot.breakfast)!.id,
        planSlotId(a.dayOnly(tuesday), MealSlot.breakfast),
      );
    });
  });

  group('across devices', () {
    test('an edited slot syncs without asking anything', () async {
      a.setPlan(monday, MealSlot.dinner, someRecipe(a, 0));
      await sync(b, a);

      // Now A changes its mind. This is the case that used to tie at epoch on
      // both sides and raise a conflict prompt about a meal slot.
      a.setPlan(monday, MealSlot.dinner, someRecipe(a, 2));
      final conflicts = await sync(b, a);

      expect(conflicts, 0);
      expect(
        b.planAt(monday, MealSlot.dinner)!.recipeId,
        someRecipe(a, 2),
      );
    });

    test('an edit after the other device cleared the slot wins', () async {
      a.setPlan(monday, MealSlot.dinner, someRecipe(a, 0));
      await sync(b, a);

      b.clearPlan(monday, MealSlot.dinner);
      // A fills it again, later. Epoch would have lost to the tombstone no
      // matter the order; a real stamp settles it on the clock.
      a.setPlan(monday, MealSlot.dinner, someRecipe(a, 1));

      await sync(b, a);

      expect(b.planAt(monday, MealSlot.dinner), isNotNull);
      expect(b.planAt(monday, MealSlot.dinner)!.recipeId, someRecipe(a, 1));
    });

    test('a clear after the other device filled it wins', () async {
      a.setPlan(monday, MealSlot.snack, someRecipe(a, 0));
      await sync(b, a);
      b.clearPlan(monday, MealSlot.snack);

      await sync(a, b);

      expect(a.planAt(monday, MealSlot.snack), isNull);
    });

    test('syncing twice changes nothing the second time', () async {
      a.setPlan(tuesday, MealSlot.lunch, someRecipe(a));
      await sync(b, a);

      final plan = b.planMerge(a.library, a.pantry);
      expect(plan.library.unresolved, isEmpty);
      expect(plan.library.stats.isEmpty, isTrue);
    });

    test('a deleted recipe takes its plan entries and they stay gone',
        () async {
      final doomed = someRecipe(a, 0);
      a.setPlan(monday, MealSlot.dinner, doomed);
      await sync(b, a);

      a.deleteRecipe(doomed);
      await sync(b, a);
      expect(b.planAt(monday, MealSlot.dinner), isNull);

      // B still held the recipe a moment ago; syncing back must not revive it.
      await sync(a, b);
      expect(a.planAt(monday, MealSlot.dinner), isNull);
      expect(a.library.recipes.any((r) => r.id == doomed), isFalse);
    });
  });
}
