# Plan: scan a barcode in the macros editor

**Status:** planned, not started. Raised 2026-09-20 after label search was
fixed and found to work but to return noisy results.

## Context

Label search works again (`docs/plans/label-search.md`, endpoint moved to
Search-a-licious in PR #16), and it fills every field the database states. What
it does not do is find *one particular packet*. Searching **basil** returns
three jars of basil and five products that merely contain basil —
"Lloyd Grossman Tomato & Basil" among them. That is not a bug in the search: a
full-text query over a million branded products cannot know that the user is
holding a jar of dried basil rather than a sauce.

The packet knows. Every one of them carries the number the database is indexed
by, and Open Food Facts answers on it directly:

```
GET https://world.openfoodfacts.org/api/v2/product/<barcode>.json
```

Checked 2026-09-20 with the app's User-Agent: `3017620422003` (Nutella) and
`0038000138416` (Pringles Original) both return `status: 1` with
`product_name`, `brands`, `serving_size`, `product_quantity` and the same
`nutriments` keys the search parser already reads. A barcode that is not in the
database returns HTTP 404 with `status: 0` and `status_verbose: "product not
found"` — a clean, distinguishable answer rather than an error.

So a scan is **one exact result instead of eight approximate ones**, which is
the whole point. Typing thirteen digits by hand would get the same answer; the
camera is what makes it faster than reading the label off the packet, which is
the thing this feature exists to replace.

## The rules this has to keep

- **The offline rule.** Like the update check and like search, nothing is
  fetched on launch or in the background. A scan is a user action, and the
  lookup happens because the user pointed the camera at a packet and it
  resolved. See `docs/plans/label-search.md`.
- **Nothing is uploaded.** The app reads Open Food Facts and never writes to
  it. A product the database does not have stays missing; offering to
  contribute one is a different feature with its own consent questions.
- **The camera is asked for when first needed**, and then listed in Settings →
  Permissions with what it is for, which is what `PermissionState.defaults`
  already does for the microphone, wakelock, web fetch, photos and
  notifications.
- **Android only, and the desktop is not made to look broken.** The scan
  button appears where a camera exists; on Windows the editor is exactly what
  it is today. Typing a barcode by hand is offered on both, which also covers a
  phone whose camera permission was refused.

## Shape

The fetch and the parse split the way `lib/labels/` already splits, and most of
the parsing exists:

```
lib/labels/
  label_lookup.dart    // + parseProduct, shared with parseSearch
  label_client.dart    // + lookupBarcode(String code)
  barcode_scanner.dart // the camera sheet, Android only
```

**`parseProduct`.** `parseSearch` currently maps a product document to a
`LabelReference` inline, inside its loop. That body moves out into
`LabelReference? parseProduct(Map<String, dynamic>)` and both callers use it —
the barcode response's `product` object is the same document a search hit is.
Worth doing on its own: it is the piece with all the edge cases (kJ-only
energy, `brands` as a list or a string, pack size structured or free text), and
it is currently only reachable through a search envelope.

**`lookupBarcode`.** The same client, timeout, User-Agent and exception type as
`search`:

```dart
/// The one product a barcode names, or null when the database does not have
/// it — which is a normal answer, not a failure.
Future<LabelReference?> lookupBarcode(String code);
```

404 with `status: 0` returns null. Any other non-200 throws
`LabelSearchException`, as search does, so the editor's existing failure line
covers it.

**The scanner.** `mobile_scanner` (ML Kit on Android) in a full-screen sheet:
a preview, a cancel, and a torch toggle for a dim kitchen. It returns the first
stable EAN-8 / EAN-13 / UPC-A result and closes. It has no opinion about
Open Food Facts — it hands back a string.

**In the editor.** `EditMacrosDialog` already has a search row, a result list,
and a reference card; a scan is a different way to reach the same reference
card. `_searchSection` gains a **Scan** button beside the search field on
Android, and the dialog gains one state: scanning. A scan that resolves fills
the card exactly as picking a search result does, including honouring the
autofill setting, so **everything after the scan is code that already exists
and is already tested.** A scan that finds nothing says so and leaves the
search field holding the barcode, so the user can search by name instead.

**Injection, so it stays testable.** The dialog takes `search` as a parameter
already (`edit_macros_search_test.dart` passes a fake). `scan` and `lookup` go
in the same way, and the widget tests never open a camera.

## Files

| File | Change |
| --- | --- |
| `pubspec.yaml` | `mobile_scanner` |
| `android/app/src/main/AndroidManifest.xml` | `android.permission.CAMERA` |
| `lib/labels/label_lookup.dart` | extract `parseProduct`; add `parseProductLookup` for the `{status, product}` envelope |
| `lib/labels/label_client.dart` | `lookupBarcode` |
| `lib/labels/barcode_scanner.dart` | new — the camera sheet and its permission prompt |
| `lib/data/settings.dart` | a `camera` row in `PermissionState.defaults` |
| `lib/ui/pantry/edit_macros.dart` | Scan button, scanning state, "type it instead" |
| `test/label_lookup_test.dart` | `parseProduct` against a real product document; the not-found envelope |
| `test/label_client_test.dart` | 404/`status: 0` is null, not an exception; other failures still throw |
| `test/edit_macros_search_test.dart` | a fake scanner: a hit fills the card, a miss leaves the code in the search box |

## Worth deciding before building

**Should the barcode be kept on the pantry item?** A `String? barcode` on
`PantryItem` would let a later scan recognise a product already in the pantry —
"that is your Nutella" — and opens the door to scanning a packet to mark it run
out or add it to the list, which is a genuinely nice kitchen gesture. It is
also a new synced field: it needs a merge story and a migration, and the
`Stamped` records make that cheap but not free. **Recommendation: leave it out
of the first cut.** Scanning to fill macros is worth having on its own, and the
field can be added when there is a second use for it.

## Verification

- Unit tests as listed above; `flutter test` and `flutter analyze
  --fatal-infos` clean.
- A real scan on the phone, which is the only check fixtures cannot stand in
  for: a packet with a barcode in the database fills the card; a packet that is
  not in it says so; refusing the camera permission leaves a usable dialog with
  the manual field.
- The APK grows by roughly 2–3 MB from ML Kit's barcode model. Worth recording
  what it actually costs when it lands.

## Out of scope

- Contributing a missing product back to Open Food Facts.
- Scanning anywhere other than the macros editor — pantry, groceries and cook
  mode all have their own questions.
- Anything on Windows. The desktop has no camera this app can assume.
