import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/state/app_state.dart';

/// Groceries across two devices.
///
/// The shopping list is the screen most likely to be open on a phone in a shop
/// while the desktop sits at home, so it is the one that has to converge — and
/// until now nothing tested that it did. These also cover the tombstone path
/// `clearChecked` depends on: the 14-day grocery retention exists precisely
/// because that operation buries a whole list at once.
void main() {
  late Directory dirA;
  late Directory dirB;
  late AppState a;
  late AppState b;

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
    dirA = Directory.systemTemp.createTempSync('rb_g_a');
    dirB = Directory.systemTemp.createTempSync('rb_g_b');
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

  GroceryItem? find(AppState s, String name) => s.library.groceries
      .where((g) => g.name.toLowerCase() == name.toLowerCase())
      .firstOrNull;

  test('an item added on one device arrives on the other', () async {
    a.addGrocery('sourdough starter', quantity: '1');

    final conflicts = await sync(b, a);

    expect(conflicts, 0);
    expect(find(b, 'sourdough starter'), isNotNull);
    expect(find(b, 'sourdough starter')!.quantity, '1');
  });

  test('checking something off propagates', () async {
    a.addGrocery('lemons');
    await sync(b, a);

    a.toggleGrocery(find(a, 'lemons')!.id);
    await sync(b, a);

    expect(find(b, 'lemons')!.checked, isTrue);
  });

  test('toggled on both devices, the later one wins without asking', () async {
    a.addGrocery('capers');
    await sync(b, a);
    await sync(a, b);

    // B ticks it, then A unticks it afterwards.
    b.toggleGrocery(find(b, 'capers')!.id);
    a.toggleGrocery(find(a, 'capers')!.id);
    a.toggleGrocery(find(a, 'capers')!.id);

    final conflicts = await sync(b, a);

    expect(conflicts, 0);
    expect(find(b, 'capers')!.checked, isFalse);
  });

  test('moving an item to another aisle propagates', () async {
    a.addGrocery('tahini');
    await sync(b, a);

    final other = a.aisles.last;
    a.moveGrocery(find(a, 'tahini')!.id, other.id);
    await sync(b, a);

    expect(find(b, 'tahini')!.aisleId, other.id);
  });

  test('clearing checked items removes them on the peer, for good', () async {
    a.addGrocery('parsley');
    await sync(b, a);

    a.toggleGrocery(find(a, 'parsley')!.id);
    a.clearChecked();
    expect(find(a, 'parsley'), isNull);

    await sync(b, a);
    expect(find(b, 'parsley'), isNull);

    // The tombstone is what stops B's copy — which existed a moment ago —
    // travelling back and resurrecting it.
    await sync(a, b);
    expect(find(a, 'parsley'), isNull);
  });

  test('clearing checked restocks the pantry on the peer too', () async {
    final item = a.pantryItem(a.pantry.items.first.id)!;
    a.setInStock(item.id, false);
    await sync(b, a);
    expect(b.pantryItem(item.id)!.inStock, isFalse);

    a.addGrocery(item.name, pantryItemId: item.id);
    a.toggleGrocery(find(a, item.name)!.id);
    a.clearChecked();

    await sync(b, a);

    expect(b.pantryItem(item.id)!.inStock, isTrue);
  });

  test('the same name added on both devices lands twice', () async {
    // Asserted rather than fixed. The two are genuinely different records —
    // deduping by name across devices would be guessing, and a duplicate line
    // is a five-second fix in the shop.
    a.addGrocery('olive oil');
    b.addGrocery('olive oil');

    await sync(b, a);

    expect(
      b.library.groceries.where((g) => g.name == 'olive oil').length,
      2,
    );
  });

  // A grocery pointing at an aisle that no longer exists would be refiled by
  // `repairCrossReferences`, and `RepairReport.refiledGroceries` counts it —
  // but there is no way to delete an aisle, from the UI or from `AppState`, so
  // that path cannot currently be reached. Left untested deliberately rather
  // than reached for by mutating the database behind the app's back.

  test('syncing twice transfers nothing the second time', () async {
    a.addGrocery('anchovies');
    await sync(b, a);

    final again = b.planMerge(a.library, a.pantry);
    expect(again.library.unresolved, isEmpty);
    expect(again.library.stats.isEmpty, isTrue);
  });
}
