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

  test('reads the Search-a-licious envelope', () {
    // Trimmed from a real search.openfoodfacts.org answer: results under
    // `hits`, `brands` as a list, and one product with energy only in kJ.
    const body = '''
{"hits": [
  {"product_name": "Digestive biscuits", "brands": ["Asda"],
   "quantity": "400g",
   "nutriments": {"energy-kcal_100g": 488, "proteins_100g": 7.1,
                  "fat_100g": 22, "carbohydrates_100g": 63,
                  "sugars_100g": 17}},
  {"product_name": "Oatcakes", "brands": [],
   "nutriments": {"energy-kj_100g": 1841}}
], "page": 1, "page_size": 8, "count": 2}
''';
    final refs = parseSearch(body);
    expect(refs, hasLength(2));
    expect(refs[0].brand, 'Asda');
    expect(refs[0].caloriesPer100g, 488);
    expect(refs[0].proteinPer100g, closeTo(7.1, 1e-9));
    expect(refs[0].packAmount, 400);
    expect(refs[1].brand, isNull);
    expect(refs[1].caloriesPer100g, closeTo(1841 / 4.184, 1e-6));
  });

  test('an empty Search-a-licious result is empty, not an error', () {
    expect(parseSearch('{"hits": [], "count": 0}'), isEmpty);
  });

  test('an empty result set is empty, not an error', () {
    expect(parseSearch('{"count": 0, "products": []}'), isEmpty);
  });

  test('a malformed payload fails visibly, never as no results', () {
    expect(
      () => parseSearch('<!DOCTYPE html>'),
      throwsA(isA<LabelSearchException>()),
    );
    expect(
      () => parseSearch('{"error": "down"}'),
      throwsA(isA<LabelSearchException>()),
    );
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
