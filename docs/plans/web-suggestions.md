# Plan: the "From the web" half of Suggestions

**Status:** planned, not started. Written 2026-09-20 to be picked up next.

## Which feature this is

Suggestions has two halves. The first — rank my own recipes by what the pantry
covers — is built and works on both platforms. The second is a panel that
currently says:

> Web results appear here once a search runs, and stay marked approximate
> until you save one — a saved recipe takes its figures from your pantry like
> everything else.

Nothing populates it. That promise, made on both platforms
(`lib/ui/library/suggestions_panel.dart`, `lib/ui/mobile/mobile_suggestions.dart`),
is what this plan finishes.

**If "search suggestions" meant the other thing** — type-ahead in the search
boxes, so typing in Library or the grocery field offers matches as you go —
say so and this plan gets replaced. That is a smaller, offline, purely local
feature and would be a day's work rather than this. The two do not overlap.

## Context

The app is **offline by design**: nothing is fetched on launch or in the
background, only when the user asks. Two features already hold that line —
the update check, and label search in the macros editor — and both are worth
copying rather than reinventing (`docs/plans/label-search.md`).

There is already a way to get a recipe off the web: paste a link, and
`RecipeParser` reads schema.org JSON-LD, microdata, or the markup
(`lib/domain/recipe_parser.dart`), then the import flow matches each
ingredient to the pantry. **What is missing is the finding.** You have to
already know the URL.

Since 2026-09-20 every ingredient resolves to a pantry item
(`AppState.pantryItemFor`), so a saved web recipe lands in exactly the same
shape as any other: its lines link to pantry items, its macros come from them,
and anything new arrives out of stock.

## The source

**TheMealDB**, `https://www.themealdb.com/api/json/v1/1/`. Checked live on
2026-09-20:

| Call | Answer |
| --- | --- |
| `filter.php?i=chicken_breast` | 200, 17 meals, each with `idMeal`, `strMeal`, `strMealThumb` |
| `lookup.php?i=52940` | 200, full record: 20 ingredient/measure pairs, `strInstructions`, `strArea`, `strCategory`, `strMealThumb`, and `strSource` — the original page |

Why this one:

- **No API key.** The same reason Open Food Facts was chosen for labels: an
  open-source app cannot ask every user to go and register for one.
- **Ingredients arrive structured** (`strIngredient1..20` / `strMeasure1..20`),
  so the ingredient matching that already exists has something clean to work
  on, with no HTML parsing in the loop.
- **`strSource` points at the original recipe**, which is what attribution
  should link to, and what "open the full recipe" should open.

**Two honest caveats, to settle before building:**

1. **The free key is `1`, described by TheMealDB as a development key**;
   supporting them gets a production one. A released app pointing every user
   at the test key is on thin ice. Options, in order of preference: ask the
   user whether to support TheMealDB and carry a real key; make the source
   configurable in Settings and ship with none; or keep the feature but state
   plainly in the README what key it uses.
2. **Attribution.** Results must say "via TheMealDB" with a link, and a saved
   recipe keeps `sourceUrl` pointing at `strSource` (falling back to the
   TheMealDB page). This is the same courtesy the importer already pays by
   storing the URL it read.

The search is by **ingredient**, which fits the panel exactly: the panel is
already an ingredient field — the user adds "chicken", "rice" as chips, and
the local half ranks their own recipes by them. `filter.php` takes one
ingredient; two or more mean fetching each and intersecting by `idMeal`
locally. Worth stating in the UI: results match **all** the chips.

## Shape

```
lib/recipes/
  web_suggestions.dart   // pure: parse a filter/lookup response
  meal_db_client.dart    // fetch: one search, one lookup, both user-initiated
```

The same split as `lib/labels/` and `lib/update/`: the parsing gets fixture
tests, the fetch is thin plumbing with a timeout, a User-Agent and a
descriptive failure.

```dart
/// One recipe the web offered, before anything is saved.
class WebSuggestion {
  final String id;          // idMeal, for the lookup
  final String title;
  final String? imageUrl;
  final String? area;       // "Jamaican" — shown as a tag
}

/// The full record, mapped onto what the import flow already consumes.
ParsedRecipe parseMealRecord(Map<String, dynamic> json);
```

`parseMealRecord` returning **`ParsedRecipe`** is the point of the design: it
is the type the review step and the pantry-matching step already take, so
saving a web suggestion is the existing import flow with its first step
skipped. `strMeasure` ("1 whole", "2 chopped") goes through the same
`parseAmount` the label and importer paths use; anything it cannot read stays
as raw text and is flagged uncertain, exactly as a scraped line is.

## Flow

1. The user adds ingredient chips (already built) and taps **Search the web** —
   a button that does not exist yet. Nothing fetches before that tap.
2. `filter.php` per chip, intersected. Titles and thumbnails fill the panel,
   each marked **approximate**.
3. Tapping one calls `lookup.php`, maps it to a `ParsedRecipe`, and opens the
   **review step of the existing import flow** — where the pantry matching,
   the "remember this name" behaviour and the "nothing is written until the
   last step" rule all already live.
4. Saving writes a normal recipe: `sourceUrl` set, figures calculated from the
   pantry, new ingredients added to the pantry out of stock.

Nothing about steps 3 and 4 is new code, which is what keeps this small.

## Files

| File | Change |
| --- | --- |
| `lib/recipes/web_suggestions.dart` | new — `WebSuggestion`, `parseFilter`, `parseMealRecord` |
| `lib/recipes/meal_db_client.dart` | new — `search(List<String>)`, `lookup(String id)` |
| `lib/ui/library/suggestions_panel.dart` | the "From the web" panel becomes real: a search button, states (idle / searching / results / nothing / failed), attribution |
| `lib/ui/mobile/mobile_suggestions.dart` | the same, in the phone's layout |
| `lib/ui/import/import_flow.dart` | an entry point that starts at the review step from a `ParsedRecipe` |
| `lib/data/settings.dart` | a `web` permission row already exists — reuse it rather than adding one |
| `test/fixtures/mealdb_filter.json`, `mealdb_lookup.json` | real captured responses |
| `test/web_suggestions_test.dart` | new |
| `README.md` | what the feature fetches, from whom, and when |

## Verification

- Parser tests against the captured fixtures: 20 ingredient slots with empties
  and nulls; measures that parse and measures that do not; a record with no
  `strSource`; a malformed payload failing visibly rather than as "no
  results".
- Client tests with a `MockClient`: the User-Agent is sent, a non-200 is a
  visible failure, a timeout says so, and two chips produce two calls
  intersected by id.
- A widget test driving the panel with a fake client: idle → searching →
  results, and picking one opens the review step with the mapped recipe.
- One live call by hand before merging, as label search had: a real search and
  a real save, with the saved recipe's ingredients landing on pantry items.
- `flutter analyze --fatal-infos` and the full suite.

## Out of scope

- Searching by anything but ingredients.
- Storing or caching web results between sessions. A search happens because
  the user asked; keeping the answer would be a quiet second copy of someone
  else's data.
- Sending anything about the user's pantry to the service. Only the chips the
  user typed leave the device, and only on the tap.
