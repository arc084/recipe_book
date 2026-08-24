# Plan: label search in the macros editor

**Status:** built. Parser, client, setting, dialog and Settings row are all in
with tests; the one check fixtures cannot vouch for — a real search against
Open Food Facts, on a device — is still to be run by hand.

## Context

Entering macros is done "with the packet in hand": serving size, five values,
brand, pack — a dozen fields typed off a label into `EditMacrosDialog`. That is
fine for the odd item and cumbersome for a pantry of forty. Most of those
labels already exist in a public database; the editor should be able to go and
fetch one.

The reference source is **Open Food Facts**: free, no API key — which matters
for an open-source app, because every user of a keyed service would need to go
and get their own — and it holds real branded products whose label data maps
almost one-to-one onto `PantryItem`: per-100 g values, serving size, brand,
pack quantity.

**The offline rule holds.** Like the update check, nothing is ever fetched on
launch or in the background. A request happens when the user taps search, and
at no other time. Search terms necessarily leave the device at that moment;
tying the request to an explicit tap is what keeps that honest.

## Shape

```
lib/labels/
  label_lookup.dart    // pure: parse the OFF response, map to a reference
  label_client.dart    // fetch: the user-initiated search call
```

The same split as `lib/update/`: the parsing has the edge cases and gets
fixture tests; the fetch is plumbing with a timeout, cancellation, and a
descriptive User-Agent (Open Food Facts asks apps to identify themselves).

```dart
/// One product's label, as the reference database states it.
///
/// Everything optional except the name: a crowdsourced label can be missing
/// any field, and a missing field fills nothing rather than guessing.
class LabelReference {
  final String name;
  final String? brand;
  final double? caloriesPer100g;   // converted from kJ when only kJ is given
  final double? proteinPer100g;
  final double? fatPer100g;
  final double? carbsPer100g;
  final double? sugarPer100g;
  final double? servingAmount;     // parsed out of "30 g" / "2 biscuits (30g)"
  final String? servingUnit;
  final double? packAmount;
  final String? packUnit;
}

/// Parses one OFF search response. Malformed products are dropped, not
/// thrown on; an unparseable response fails visibly, never as "no results".
List<LabelReference> parseSearch(Map<String, dynamic> json);
```

Cases the parser tests must cover:

- a product with only `energy_100g` (kJ) and no `energy-kcal_100g` — convert,
  do not drop
- `serving_size` strings: `"30 g"`, `"2 biscuits (30g)"`, `"1 portion"` (the
  last yields no serving, not a guess)
- missing sugars, missing brand, missing quantity — partial references are
  still offered
- an empty result set is "nothing found", a malformed payload is a failure;
  the two must not look alike

## The dialog

A **"Find a label"** row at the top of `EditMacrosDialog` — the one macros
editor, already shared by both platforms. A text field seeded with the item's
name, and a search button. Nothing fires until the button (or Enter).

States, all in the row, in the update row's spirit — a failure that looks
like "nothing found" is worse than no search:

- idle — the field and the button
- searching — a spinner, cancellable
- results — name, brand, kcal per 100 g, so lookalike products can be told
  apart; a handful at a time
- nothing found — said plainly
- failed — the reason in plain words

## Picking a result

Selecting a result always shows a **reference card**: the label's values laid
out compactly next to the form. What happens to the form depends on one
setting:

- **Autofill on (the default):** every field the reference provides is written
  into the form — the five values against a `per100g` basis (OFF's canonical
  form), serving size when stated, brand, pack. Fields the label lacks are
  left as they were. Everything stays editable, and nothing touches the
  pantry until Save; a wrong pick costs one re-pick.
- **Autofill off:** the card is shown and the form is not written at all. The
  reference is something to read while typing what you trust.

`isEstimated` stays false either way — this is label data, the very thing
that flag distinguishes from guesses.

## The setting

`AppSettings.autofillFromLabels`, default **true**, surfaced as "Autofill from
label search" in Settings on both platforms. Per-device, like the rest of
settings.json — whether a device fills forms for you is not something two
devices need to agree on.

## Verification

- Parser tests over checked-in OFF response fixtures, one per case above
- Widget tests with an injected fake client: autofill on fills the form,
  autofill off shows only the card, a failure is visible, cancellation works
- A real search against Open Food Facts, on a device, by hand — the one thing
  fixtures cannot vouch for

## Out of scope now, planned later (low priority)

- **Barcode scanning.** OFF is keyed by barcode; pointing the phone camera at
  the packet is the natural next step and would skip the search entirely.
  Needs a camera dependency and Android plumbing — its own plan.
- **Search-as-you-type.** Live results as the name is typed. Wants debounce,
  request cancellation, and a decision about how eagerly an offline-by-design
  app may talk to the network — revisit once tap-to-search has proven itself.

Not planned: caching a reference database locally, other data sources.
