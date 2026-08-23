# Label Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Search Open Food Facts from the macros editor and autofill the form from a chosen label, with autofill toggleable per device in Settings.

**Architecture:** A new `lib/labels/` module split pure-vs-plumbing: `label_lookup.dart` parses Open Food Facts search JSON into `LabelReference` values (all the edge cases, fixture-tested), `label_client.dart` makes the one user-initiated HTTP call. `EditMacrosDialog` — the single macros editor both platforms share — gains a "Find a label" section whose selected result always shows a reference card and, when `AppSettings.autofillFromLabels` is true (the default), also writes the form fields. A Settings row toggles the flag.

**Tech Stack:** Flutter/Dart, `http` (already a dependency; `package:http/testing.dart` MockClient for tests), `flutter_test`.

**Spec:** `docs/plans/label-search.md` — read it first; this plan implements it exactly.

## Global Constraints

- **Offline rule:** no network request except inside `LabelClient.search`, which runs only from the dialog's explicit Search action. Never on launch, never on open, never as-you-type.
- **User-Agent:** exactly `'RecipeBook/$kAppVersion (https://github.com/arc084/recipe_book)'` (`kAppVersion` from `lib/app_version.dart`).
- After every task: `flutter test` fully green and `flutter analyze` reports no issues before committing.
- Work happens in the existing worktree `.claude/worktrees/label-search` on branch `worktree-label-search`. Do not touch files under `lib/update/` (different branch) or anything in other worktrees.
- Every commit message ends with the two trailer lines used by this session's earlier commits:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01UpCDB13untHJkHJXwB5aGs`
- Comment style: comments explain *why*, in full sentences, matching the codebase's voice. No "added X" comments.

---

### Task 1: Parse the reference response, purely

**Files:**
- Create: `lib/labels/label_lookup.dart`
- Create: `test/fixtures/off_search.json`
- Test: `test/label_lookup_test.dart`

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: `class LabelReference` (fields: `String name`, `String? brand`, `double? caloriesPer100g`, `double? proteinPer100g`, `double? fatPer100g`, `double? carbsPer100g`, `double? sugarPer100g`, `double? servingAmount`, `String? servingUnit`, `double? packAmount`, `String? packUnit`); `List<LabelReference> parseSearch(String body)`; `class LabelSearchException implements Exception` with `final String message`; `ParsedAmount? parseAmount(String? text)` with `double amount` / `String unit`. Tasks 2 and 4 import all of these from `package:recipe_book/labels/label_lookup.dart`.

- [ ] **Step 1: Write the fixture**

`test/fixtures/off_search.json` — one complete product, one kJ-only product with sparse fields, one nameless product (must be dropped), one name-only product (must be kept):

```json
{
  "count": 4,
  "products": [
    {
      "product_name": "Chocolate Digestive",
      "brands": "McVitie's,United Biscuits",
      "serving_size": "2 biscuits (33 g)",
      "product_quantity": "500",
      "product_quantity_unit": "g",
      "nutriments": {
        "energy-kcal_100g": 495,
        "energy_100g": 2071,
        "proteins_100g": 6.7,
        "fat_100g": 23.9,
        "carbohydrates_100g": 62.5,
        "sugars_100g": 29.4
      }
    },
    {
      "product_name": "Plain Yoghurt",
      "brands": "",
      "serving_size": "1 pot",
      "quantity": "4 x 125 g",
      "nutriments": {
        "energy_100g": 264,
        "proteins_100g": 4.4,
        "fat_100g": 3.5,
        "carbohydrates_100g": 5.0
      }
    },
    {
      "product_name": "",
      "nutriments": { "energy-kcal_100g": 100 }
    },
    {
      "product_name": "Mystery Spice"
    }
  ]
}
```

- [ ] **Step 2: Write the failing tests**

`test/label_lookup_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/labels/label_lookup.dart';

/// The pure half of label search: Open Food Facts JSON in, references out.
///
/// Crowdsourced labels are reliably incomplete, so everything here is about
/// what happens to a missing or odd field — a gap fills nothing, never a
/// guess, and a broken payload fails visibly rather than looking empty.
void main() {
  final fixture = File('test/fixtures/off_search.json').readAsStringSync();

  test('a complete product comes through whole', () {
    final refs = parseSearch(fixture);
    final biscuit = refs.first;

    expect(biscuit.name, 'Chocolate Digestive');
    expect(biscuit.brand, "McVitie's");
    expect(biscuit.caloriesPer100g, 495);
    expect(biscuit.proteinPer100g, 6.7);
    expect(biscuit.fatPer100g, 23.9);
    expect(biscuit.carbsPer100g, 62.5);
    expect(biscuit.sugarPer100g, 29.4);
    // "2 biscuits (33 g)" — the parenthesised weight, not the count.
    expect(biscuit.servingAmount, 33);
    expect(biscuit.servingUnit, 'g');
    expect(biscuit.packAmount, 500);
    expect(biscuit.packUnit, 'g');
  });

  test('kJ-only energy is converted, not dropped', () {
    final yoghurt = parseSearch(fixture)[1];
    expect(yoghurt.caloriesPer100g, closeTo(63.1, 0.1)); // 264 kJ / 4.184
  });

  test('missing fields stay null and the product is still offered', () {
    final refs = parseSearch(fixture);
    final yoghurt = refs[1];
    expect(yoghurt.brand, isNull); // "" collapses to null
    expect(yoghurt.sugarPer100g, isNull);
    expect(yoghurt.servingAmount, isNull); // "1 pot" is not a weight
    expect(yoghurt.packAmount, 125); // parsed off "4 x 125 g"

    final spice = refs.last;
    expect(spice.name, 'Mystery Spice');
    expect(spice.caloriesPer100g, isNull);
  });

  test('a nameless product is dropped', () {
    // 4 in the fixture, one has no name.
    expect(parseSearch(fixture), hasLength(3));
  });

  test('an empty result set is empty, not an error', () {
    expect(parseSearch('{"count": 0, "products": []}'), isEmpty);
  });

  test('a malformed payload fails visibly, never as no results', () {
    expect(() => parseSearch('<!DOCTYPE html>'),
        throwsA(isA<LabelSearchException>()));
    expect(() => parseSearch('{"error": "down"}'),
        throwsA(isA<LabelSearchException>()));
  });

  group('parseAmount', () {
    test('reads a plain weight', () {
      final a = parseAmount('30 g')!;
      expect(a.amount, 30);
      expect(a.unit, 'g');
    });

    test('prefers the parenthesised weight in a compound serving', () {
      final a = parseAmount('2 biscuits (33g)')!;
      expect(a.amount, 33);
      expect(a.unit, 'g');
    });

    test('reads millilitres and decimal commas', () {
      final a = parseAmount('33,5 ml')!;
      expect(a.amount, 33.5);
      expect(a.unit, 'ml');
    });

    test('yields nothing for a unitless serving', () {
      expect(parseAmount('1 portion'), isNull);
      expect(parseAmount(null), isNull);
    });
  });
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `flutter test test/label_lookup_test.dart`
Expected: compilation failure — `package:recipe_book/labels/label_lookup.dart` does not exist.

- [ ] **Step 4: Write the implementation**

`lib/labels/label_lookup.dart`:

```dart
import 'dart:convert';

/// One product's label, as the reference database states it.
///
/// Everything optional except the name: a crowdsourced label can be missing
/// any field, and a missing field fills nothing rather than guessing.
class LabelReference {
  const LabelReference({
    required this.name,
    this.brand,
    this.caloriesPer100g,
    this.proteinPer100g,
    this.fatPer100g,
    this.carbsPer100g,
    this.sugarPer100g,
    this.servingAmount,
    this.servingUnit,
    this.packAmount,
    this.packUnit,
  });

  final String name;
  final String? brand;
  final double? caloriesPer100g;
  final double? proteinPer100g;
  final double? fatPer100g;
  final double? carbsPer100g;
  final double? sugarPer100g;
  final double? servingAmount;
  final String? servingUnit;
  final double? packAmount;
  final String? packUnit;
}

/// A search that failed in a way the user must be shown.
///
/// Kept apart from an empty result on purpose: "nothing found" and "the
/// request broke" must never look alike — a failure disguised as no results
/// is the most misleading state this feature can produce.
class LabelSearchException implements Exception {
  const LabelSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A number with the unit it was stated in, pulled out of label prose.
class ParsedAmount {
  const ParsedAmount(this.amount, this.unit);

  final double amount;
  final String unit;
}

/// Reads a weight or volume out of strings like "30 g", "2 biscuits (33g)"
/// or "4 x 125 g". The *last* match wins, because compound servings put the
/// weight in a trailing parenthesis. "1 portion" yields nothing — a serving
/// with no unit cannot bridge to a per-100 g basis, so guessing would only
/// corrupt the scaling.
ParsedAmount? parseAmount(String? text) {
  if (text == null) return null;
  final matches = RegExp(
    r'(\d+(?:[.,]\d+)?)\s*(kg|ml|g|l)\b',
  ).allMatches(text.toLowerCase()).toList();
  if (matches.isEmpty) return null;
  final m = matches.last;
  return ParsedAmount(
    double.parse(m.group(1)!.replaceAll(',', '.')),
    m.group(2)!,
  );
}

/// Parses one Open Food Facts search response.
///
/// Malformed products are dropped, not thrown on — one bad crowdsourced
/// entry must not sink the whole result list. A malformed *payload* throws
/// [LabelSearchException] instead, so it can never masquerade as an empty
/// result.
List<LabelReference> parseSearch(String body) {
  final dynamic raw;
  try {
    raw = jsonDecode(body);
  } on FormatException {
    throw const LabelSearchException(
      'The reference database sent something unreadable.',
    );
  }
  if (raw is! Map<String, dynamic> || raw['products'] is! List) {
    throw const LabelSearchException(
      'The reference database sent something unreadable.',
    );
  }

  final out = <LabelReference>[];
  for (final p in raw['products'] as List) {
    if (p is! Map<String, dynamic>) continue;
    final name = (p['product_name'] as String?)?.trim();
    if (name == null || name.isEmpty) continue;

    final n = p['nutriments'];
    final nutriments = n is Map<String, dynamic> ? n : const <String, dynamic>{};
    final serving = parseAmount(p['serving_size'] as String?);
    final pack = _pack(p);

    out.add(
      LabelReference(
        name: name,
        brand: _brand(p['brands']),
        caloriesPer100g: _kcal(nutriments),
        proteinPer100g: _number(nutriments['proteins_100g']),
        fatPer100g: _number(nutriments['fat_100g']),
        carbsPer100g: _number(nutriments['carbohydrates_100g']),
        sugarPer100g: _number(nutriments['sugars_100g']),
        servingAmount: serving?.amount,
        servingUnit: serving?.unit,
        packAmount: pack?.amount,
        packUnit: pack?.unit,
      ),
    );
  }
  return out;
}

double? _number(dynamic v) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

/// kcal when stated; converted from kJ when that is all the label has.
/// Plenty of European entries carry only `energy_100g` (kJ), and dropping
/// them would silently hide exactly the products the user searched for.
double? _kcal(Map<String, dynamic> nutriments) {
  final kcal = _number(nutriments['energy-kcal_100g']);
  if (kcal != null) return kcal;
  final kj = _number(nutriments['energy_100g']);
  return kj == null ? null : kj / 4.184;
}

/// OFF's `brands` is a comma-separated list; the first is the label's own.
String? _brand(dynamic brands) {
  if (brands is! String) return null;
  final first = brands.split(',').first.trim();
  return first.isEmpty ? null : first;
}

/// Pack size: the structured pair when present, else parsed out of the
/// free-text `quantity`.
ParsedAmount? _pack(Map<String, dynamic> p) {
  final amount = _number(p['product_quantity']);
  if (amount != null) {
    final unit = p['product_quantity_unit'];
    return ParsedAmount(
      amount,
      unit is String && unit.trim().isNotEmpty ? unit.trim() : 'g',
    );
  }
  return parseAmount(p['quantity'] as String?);
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/label_lookup_test.dart`
Expected: all pass.

- [ ] **Step 6: Analyze and commit**

Run: `flutter analyze` — no issues.

```bash
git add lib/labels/label_lookup.dart test/label_lookup_test.dart test/fixtures/off_search.json
git commit -m "Parse the reference database's answer, purely

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UpCDB13untHJkHJXwB5aGs"
```

---

### Task 2: Fetch label searches when, and only when, asked

**Files:**
- Create: `lib/labels/label_client.dart`
- Test: `test/label_client_test.dart`

**Interfaces:**
- Consumes: `parseSearch`, `LabelReference`, `LabelSearchException` from Task 1.
- Produces: `class LabelClient` with constructor `LabelClient({http.Client Function()? httpClient})` and `Future<List<LabelReference>> search(String terms)`. Task 4 calls `LabelClient().search`.

- [ ] **Step 1: Write the failing tests**

`test/label_client_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recipe_book/labels/label_client.dart';
import 'package:recipe_book/labels/label_lookup.dart';

/// The plumbing half: one GET against Open Food Facts, identified, bounded,
/// and honest about failure. The offline rule lives in the caller — nothing
/// in this file runs unless the user tapped search.
void main() {
  const body =
      '{"count": 1, "products": [{"product_name": "Chocolate Digestive", '
      '"nutriments": {"energy-kcal_100g": 495}}]}';

  test('identifies the app and sends the search terms', () async {
    late http.Request seen;
    final client = LabelClient(
      httpClient: () => MockClient((request) async {
        seen = request;
        return http.Response(body, 200);
      }),
    );

    final refs = await client.search('digestive biscuits');

    expect(seen.url.host, 'world.openfoodfacts.org');
    expect(seen.url.queryParameters['search_terms'], 'digestive biscuits');
    expect(seen.url.queryParameters['json'], '1');
    expect(seen.headers['user-agent'], startsWith('RecipeBook/'));
    expect(seen.headers['user-agent'], contains('github.com'));
    expect(refs.single.name, 'Chocolate Digestive');
  });

  test('a non-200 answer is a visible failure', () {
    final client = LabelClient(
      httpClient: () => MockClient((_) async => http.Response('down', 503)),
    );
    expect(
      () => client.search('anything'),
      throwsA(
        isA<LabelSearchException>().having(
          (e) => e.message,
          'message',
          contains('503'),
        ),
      ),
    );
  });

  test('a network error is a visible failure, not a crash', () {
    final client = LabelClient(
      httpClient: () =>
          MockClient((_) async => throw http.ClientException('refused')),
    );
    expect(
      () => client.search('anything'),
      throwsA(isA<LabelSearchException>()),
    );
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/label_client_test.dart`
Expected: compilation failure — `label_client.dart` does not exist.

- [ ] **Step 3: Write the implementation**

`lib/labels/label_client.dart`:

```dart
import 'dart:async';

import 'package:http/http.dart' as http;

import '../app_version.dart';
import 'label_lookup.dart';

/// The one call this app makes to the reference database: a product search,
/// fired only by the user tapping search in the macros editor. Nothing here
/// runs on launch or in the background — that is the same offline rule the
/// update check follows, and it is load-bearing.
class LabelClient {
  LabelClient({http.Client Function()? httpClient})
    : _httpClient = httpClient ?? http.Client.new;

  /// A factory rather than a client, so every search gets a fresh client it
  /// can close — and tests can hand in a fake.
  final http.Client Function() _httpClient;

  static final Uri _endpoint = Uri.parse(
    'https://world.openfoodfacts.org/cgi/search.pl',
  );

  /// Open Food Facts asks apps to identify themselves.
  static const String userAgent =
      'RecipeBook/$kAppVersion (https://github.com/arc084/recipe_book)';

  Future<List<LabelReference>> search(String terms) async {
    final uri = _endpoint.replace(
      queryParameters: {
        'search_terms': terms,
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page_size': '8',
        'fields':
            'product_name,brands,nutriments,serving_size,quantity,'
            'product_quantity,product_quantity_unit',
      },
    );

    final client = _httpClient();
    try {
      final response = await client
          .get(uri, headers: {'User-Agent': userAgent})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw LabelSearchException(
          'The reference database answered ${response.statusCode}.',
        );
      }
      return parseSearch(response.body);
    } on LabelSearchException {
      rethrow;
    } on TimeoutException {
      throw const LabelSearchException('The search took too long.');
    } catch (e) {
      // Whatever the transport threw, the user sees words, not a stack.
      throw LabelSearchException('The search could not get through: $e');
    } finally {
      client.close();
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/label_client_test.dart`
Expected: all pass.

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze` — no issues.

```bash
git add lib/labels/label_client.dart test/label_client_test.dart
git commit -m "Fetch label searches when, and only when, asked

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UpCDB13untHJkHJXwB5aGs"
```

---

### Task 3: Let a device opt out of autofill

**Files:**
- Modify: `lib/data/settings.dart` (class `AppSettings`, constructor around line 152, `fromJson` around line 201, `toJson` around line 223)
- Modify: `lib/state/app_state.dart` (beside `setCloudSyncEnabled`, around line 866)
- Test: `test/label_settings_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `bool AppSettings.autofillFromLabels` (default `true`) and `void AppState.setAutofillFromLabels(bool on)`. Task 4 reads the field; Task 5 calls the setter.

- [ ] **Step 1: Write the failing tests**

`test/label_settings_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/data/settings.dart';
import 'package:recipe_book/state/app_state.dart';

/// The autofill flag: on unless this device said otherwise, and remembered
/// across launches. Per-device on purpose — whether a device fills forms for
/// you is not something two devices need to agree on, so it lives in
/// settings.json and never syncs.
void main() {
  test('defaults on, including for settings saved before the flag existed', () {
    expect(AppSettings().autofillFromLabels, isTrue);
    expect(AppSettings.fromJson(const {}).autofillFromLabels, isTrue);
  });

  test('a device that turned it off stays off through the round trip', () {
    final s = AppSettings()..autofillFromLabels = false;
    expect(AppSettings.fromJson(s.toJson()).autofillFromLabels, isFalse);
  });

  test('the setter persists across a relaunch', () async {
    final dir = Directory.systemTemp.createTempSync('rb_autofill');
    try {
      final app = AppState(directory: dir);
      await app.load();
      app.setAutofillFromLabels(false);
      await app.flush();

      final relaunched = AppState(directory: dir);
      await relaunched.load();
      expect(relaunched.settings.autofillFromLabels, isFalse);
      await relaunched.flush();
    } finally {
      dir.deleteSync(recursive: true);
    }
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/label_settings_test.dart`
Expected: compilation failure — `autofillFromLabels` is not defined.

- [ ] **Step 3: Implement**

In `lib/data/settings.dart`, add to the `AppSettings` constructor parameter list:

```dart
    this.autofillFromLabels = true,
```

Add the field beside `themeMode`, with the why:

```dart
  /// Whether picking a label-search result writes the macros form, or only
  /// shows the reference card to copy from. On by default; the search itself
  /// is always available either way.
  bool autofillFromLabels;
```

In `AppSettings.fromJson`, add:

```dart
    autofillFromLabels: j['autofillFromLabels'] as bool? ?? true,
```

In `toJson`, add:

```dart
    'autofillFromLabels': autofillFromLabels,
```

In `lib/state/app_state.dart`, directly under `setCloudSyncEnabled`:

```dart
  void setAutofillFromLabels(bool on) {
    settings.autofillFromLabels = on;
    _touchSettings();
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/label_settings_test.dart`
Expected: all pass. Then run the full `flutter test` — the settings round-trip is load-bearing for sync tests, so prove nothing else moved.

- [ ] **Step 5: Analyze and commit**

Run: `flutter analyze` — no issues.

```bash
git add lib/data/settings.dart lib/state/app_state.dart test/label_settings_test.dart
git commit -m "Let a device opt out of autofill

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UpCDB13untHJkHJXwB5aGs"
```

---

### Task 4: Search Open Food Facts from the macros editor

**Files:**
- Modify: `lib/ui/pantry/edit_macros.dart` (constructor around line 15, state class around line 30, `dispose` around line 55, the `ListView` children around line 175)
- Test: `test/edit_macros_search_test.dart`

**Interfaces:**
- Consumes: `LabelReference`, `LabelSearchException` (Task 1); `LabelClient` (Task 2); `AppSettings.autofillFromLabels` and `AppState.setAutofillFromLabels` (Task 3).
- Produces: `EditMacrosDialog({required PantryItem item, Future<List<LabelReference>> Function(String terms)? search})` — the new optional `search` parameter is the test seam; `EditMacrosDialog.open` is unchanged.

- [ ] **Step 1: Write the failing tests**

`test/edit_macros_search_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:recipe_book/data/models.dart';
import 'package:recipe_book/labels/label_lookup.dart';
import 'package:recipe_book/state/app_state.dart';
import 'package:recipe_book/theme/app_theme.dart';
import 'package:recipe_book/ui/pantry/edit_macros.dart';

/// The dialog's half of label search: nothing fires without a tap, every
/// state is told apart, and the one setting decides whether picking a result
/// writes the form or only shows the card.
void main() {
  late Directory dir;
  late AppState app;
  late PantryItem item;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('rb_macros_search');
    app = AppState(directory: dir);
    await app.load();
    item = PantryItem(id: newId(), name: 'digestives');
    app.savePantryItem(item);
  });

  tearDown(() async {
    await app.flush();
    dir.deleteSync(recursive: true);
  });

  /// A full reference, the shape Task 1 produces from a healthy answer.
  LabelReference biscuit() => const LabelReference(
    name: 'Chocolate Digestive',
    brand: "McVitie's",
    caloriesPer100g: 495,
    proteinPer100g: 6.7,
    fatPer100g: 23.9,
    carbsPer100g: 62.5,
    sugarPer100g: 29.4,
    servingAmount: 33,
    servingUnit: 'g',
    packAmount: 500,
    packUnit: 'g',
  );

  Future<void> openDialog(
    WidgetTester tester,
    Future<List<LabelReference>> Function(String terms) search,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => EditMacrosDialog(item: item, search: search),
                  ),
                  child: const Text('macros'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('macros'));
    await tester.pumpAndSettle();
  }

  testWidgets('nothing fires on open; a tap searches and lists results',
      (tester) async {
    var calls = 0;
    await openDialog(tester, (terms) async {
      calls++;
      expect(terms, 'digestives'); // seeded with the item's name
      return [biscuit()];
    });
    expect(calls, 0);

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.textContaining('Chocolate Digestive'), findsWidgets);
  });

  testWidgets('nothing found is said plainly', (tester) async {
    await openDialog(tester, (_) async => const []);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nothing found'), findsOneWidget);
  });

  testWidgets('a failure is shown in words, never as empty results',
      (tester) async {
    await openDialog(tester, (_) async {
      throw const LabelSearchException('The reference database answered 503.');
    });
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.textContaining('503'), findsOneWidget);
    expect(find.textContaining('Nothing found'), findsNothing);
  });

  testWidgets('picking a result fills the form when autofill is on',
      (tester) async {
    await openDialog(tester, (_) async => [biscuit()]);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Chocolate Digestive').first);
    await tester.pumpAndSettle();

    // The five values, per 100 g.
    expect(find.widgetWithText(TextField, '495'), findsOneWidget);
    expect(find.widgetWithText(TextField, '6.7'), findsOneWidget);
    // Serving and pack.
    expect(find.widgetWithText(TextField, '33'), findsOneWidget);
    expect(find.widgetWithText(TextField, '500'), findsOneWidget);
    // The reference card, and the note that the form was written.
    expect(find.textContaining('Per 100 g'), findsOneWidget);
    expect(find.textContaining('Filled into the form'), findsOneWidget);
  });

  testWidgets('with autofill off the card shows and the form is untouched',
      (tester) async {
    app.setAutofillFromLabels(false);
    await openDialog(tester, (_) async => [biscuit()]);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Chocolate Digestive').first);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, '495'), findsNothing);
    expect(find.textContaining('Per 100 g'), findsOneWidget);
    expect(find.textContaining('Autofill is off'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/edit_macros_search_test.dart`
Expected: compilation failure — `EditMacrosDialog` has no `search` parameter.

- [ ] **Step 3: Implement the dialog changes**

All edits in `lib/ui/pantry/edit_macros.dart`.

Add imports below the existing ones:

```dart
import '../../labels/label_client.dart';
import '../../labels/label_lookup.dart';
```

Extend the widget's constructor and fields (currently `const EditMacrosDialog({super.key, required this.item});`):

```dart
  const EditMacrosDialog({super.key, required this.item, this.search});

  final PantryItem item;

  /// Injected by tests; the real Open Food Facts client otherwise.
  final Future<List<LabelReference>> Function(String terms)? search;
```

Add to `_EditMacrosDialogState`, beside the existing controllers:

```dart
  late final Future<List<LabelReference>> Function(String terms) _search =
      widget.search ?? LabelClient().search;
  late final _query = TextEditingController(text: _draft.name);

  _SearchState _searchState = _SearchState.idle;
  List<LabelReference> _results = const [];
  String? _searchError;
  LabelReference? _picked;

  /// Bumped to orphan an in-flight search the user cancelled or replaced —
  /// its answer arrives, sees a newer generation, and is dropped.
  int _searchGeneration = 0;
```

Add `_query` to the controller list in `dispose`.

Add the state machine methods to `_EditMacrosDialogState`:

```dart
  // ── Label search ────────────────────────────────────────────────────────

  Future<void> _runSearch() async {
    final terms = _query.text.trim();
    if (terms.isEmpty) return;
    final generation = ++_searchGeneration;
    setState(() {
      _searchState = _SearchState.searching;
      _picked = null;
    });
    try {
      final found = await _search(terms);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = found;
        _searchState =
            found.isEmpty ? _SearchState.nothing : _SearchState.results;
      });
    } on LabelSearchException catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _searchError = e.message;
        _searchState = _SearchState.failed;
      });
    }
  }

  void _cancelSearch() {
    _searchGeneration++;
    setState(() => _searchState = _SearchState.idle);
  }

  void _pick(LabelReference label) {
    final autofill = context.read<AppState>().settings.autofillFromLabels;
    setState(() => _picked = label);
    if (!autofill) return;
    setState(() {
      // The five values are OFF's canonical per-100 g form, so the basis
      // chip follows them — but only when there are values to state.
      if (label.caloriesPer100g != null ||
          label.proteinPer100g != null ||
          label.fatPer100g != null ||
          label.carbsPer100g != null ||
          label.sugarPer100g != null) {
        _draft.basis = MacroBasis.per100g;
      }
      void put(TextEditingController c, double? v) {
        if (v != null) c.text = formatAmount(v);
      }

      put(_calories, label.caloriesPer100g);
      put(_protein, label.proteinPer100g);
      put(_fat, label.fatPer100g);
      put(_carbs, label.carbsPer100g);
      put(_sugar, label.sugarPer100g);
      put(_serving, label.servingAmount);
      if (label.servingUnit != null) _servingUnit.text = label.servingUnit!;
      put(_pack, label.packAmount);
      if (label.packUnit != null) _packUnit.text = label.packUnit!;
      _brand.text = _productName(label);
    });
  }

  String _productName(LabelReference label) =>
      label.brand == null ? label.name : '${label.brand} ${label.name}';
```

Add the search section widgets to `_EditMacrosDialogState`:

```dart
  Widget _searchSection(BuildContext context) {
    final t = context.tokens;
    final searching = _searchState == _SearchState.searching;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _step(context, '0', 'Find a label'),
        const SizedBox(height: 6),
        Text(
          'Search Open Food Facts and copy a label instead of typing it. '
          'Nothing is fetched until you tap search.',
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 11,
            color: t.textFaint,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: _query,
                hint: 'Product name',
                height: 38,
                fontSize: 13,
                onSubmitted: (_) => _runSearch(),
              ),
            ),
            const SizedBox(width: 8),
            AppButton(
              searching ? 'Cancel' : 'Search',
              fontSize: 12,
              height: 38,
              onPressed: searching ? _cancelSearch : _runSearch,
            ),
          ],
        ),
        if (searching)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        if (_searchState == _SearchState.failed)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'The search failed: $_searchError',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 12,
                color: t.text,
              ),
            ),
          ),
        if (_searchState == _SearchState.nothing)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Nothing found for "${_query.text.trim()}".',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 12,
                color: t.textMuted,
              ),
            ),
          ),
        if (_searchState == _SearchState.results)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              children: [for (final r in _results) _resultRow(context, r)],
            ),
          ),
        if (_picked != null) _referenceCard(context, _picked!),
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _resultRow(BuildContext context, LabelReference label) {
    final t = context.tokens;
    return InkWell(
      onTap: () => _pick(label),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _productName(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12.5,
                  color: t.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label.caloriesPer100g == null
                  ? 'no kcal'
                  : '${formatAmount(label.caloriesPer100g)} kcal/100 g',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11.5,
                color: t.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _referenceCard(BuildContext context, LabelReference label) {
    final t = context.tokens;
    String amount(double? v, String suffix) =>
        v == null ? '—' : '${formatAmount(v)}$suffix';
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(color: t.ground, borderRadius: t.brContainer),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _productName(label),
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 12.5,
              color: t.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Per 100 g: ${amount(label.caloriesPer100g, ' kcal')} · '
            '${amount(label.proteinPer100g, ' g protein')} · '
            '${amount(label.fatPer100g, ' g fat')} · '
            '${amount(label.carbsPer100g, ' g carbs')} · '
            '${amount(label.sugarPer100g, ' g sugar')}',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 11.5,
              color: t.textMuted,
            ),
          ),
          if (label.servingAmount != null || label.packAmount != null) ...[
            const SizedBox(height: 2),
            Text(
              [
                if (label.servingAmount != null)
                  'Serving ${formatAmount(label.servingAmount)} '
                      '${label.servingUnit}',
                if (label.packAmount != null)
                  'Pack ${formatAmount(label.packAmount)} ${label.packUnit}',
              ].join(' · '),
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11.5,
                color: t.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            context.read<AppState>().settings.autofillFromLabels
                ? 'Filled into the form — check and edit before saving.'
                : 'Autofill is off — copy across whatever you trust.',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 11,
              color: t.textFaint,
            ),
          ),
        ],
      ),
    );
  }
```

Add the enum at the bottom of the file, beside the other private helpers:

```dart
/// Where the label search stands. `nothing` and `failed` are deliberately
/// separate states: an error shown as an empty list would send the user
/// typing a label that the database actually had.
enum _SearchState { idle, searching, results, nothing, failed }
```

Finally, wire the section in: in `build`'s `ListView` children, directly above the line `// 1. Serving size comes first.`, insert:

```dart
                  _searchSection(context),
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/edit_macros_search_test.dart`
Expected: all pass. If `_step` renders the `'0'` badge oddly, keep the tests as the contract and adjust only presentation.

- [ ] **Step 5: Run the full suite**

Run: `flutter test`
Expected: everything green — the dialog is also exercised by any existing pantry tests.

- [ ] **Step 6: Analyze and commit**

Run: `flutter analyze` — no issues.

```bash
git add lib/ui/pantry/edit_macros.dart test/edit_macros_search_test.dart
git commit -m "Search Open Food Facts from the macros editor

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UpCDB13untHJkHJXwB5aGs"
```

---

### Task 5: Offer the autofill switch in Settings

**Files:**
- Modify: `lib/ui/settings/settings_page.dart` (section list around lines 121–130, new section method beside `_databasesSection` around line 459)

**Interfaces:**
- Consumes: `AppSettings.autofillFromLabels`, `AppState.setAutofillFromLabels` (Task 3); the file's existing `_Section` widget and `AppButton` idiom (see the cloud section's Pause/Resume button around line 233 for the exact pattern).
- Produces: nothing later tasks need.

- [ ] **Step 1: Add the section method**

In `lib/ui/settings/settings_page.dart`, beside the other `_xxxSection` methods:

```dart
  // ── Label search ────────────────────────────────────────────────────────

  Widget _labelSearchSection(BuildContext context, AppState app) {
    final t = context.tokens;
    final on = app.settings.autofillFromLabels;
    return _Section(
      title: 'Label search',
      subtitle:
          'The macros editor can search Open Food Facts for a product\'s '
          'label. It only ever fetches when you tap search.',
      child: Row(
        children: [
          Expanded(
            child: Text(
              on
                  ? 'Picking a result fills the form. The reference card '
                        'always shows.'
                  : 'Picking a result only shows the reference card.',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 12.5,
                color: t.text,
              ),
            ),
          ),
          const SizedBox(width: 8),
          AppButton(
            on ? 'Turn autofill off' : 'Turn autofill on',
            fontSize: 12,
            onPressed: () => app.setAutofillFromLabels(!on),
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 2: Wire it into the section list**

In `build`'s children list, after `_databasesSection(context, app),` and its spacing:

```dart
        const SizedBox(height: 22),
        _labelSearchSection(context, app),
```

- [ ] **Step 3: Verify**

Run: `flutter test` — full suite green (the section has no widget test of its own: the flag's behaviour is covered in Tasks 3 and 4; this is presentation wired to an already-tested setter, and `SettingsPage`'s heavy platform dependencies make a widget test cost more than it proves).
Run: `flutter analyze` — no issues.
Optional eyeball: `flutter run -d linux --dart-define=MOBILE_PREVIEW=true` and check the row reads correctly on both layouts.

- [ ] **Step 4: Commit**

```bash
git add lib/ui/settings/settings_page.dart
git commit -m "Offer the autofill switch in Settings

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UpCDB13untHJkHJXwB5aGs"
```

---

## After the tasks

- Update `docs/plans/label-search.md`'s status line from "designed, not started" to built-with-manual-check-outstanding, in the same voice as the other plan docs, and commit it with the final task if not done separately.
- The one thing fixtures cannot vouch for: a real search against Open Food Facts on a device, by hand (Deniz runs this, like the other on-device checks).
- Out of scope, recorded in the spec as planned/low priority: barcode scanning, search-as-you-type.
