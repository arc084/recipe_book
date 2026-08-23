# Plan: recipe editing on Android

**Status:** planned, not started.

## Context

The original design handoff made editing desktop-only, and said so repeatedly:
*"Mobile has no recipe edit mode — desktop only"*, *"the phone reads, cooks and
shops"*. That was a reasonable call for a two-device personal app where one
device was always the kitchen laptop.

**It no longer holds.** The project is now an open-source kitchen manager, and
plenty of people will install it on a phone and never on a desktop at all. For
them, a read-only app cannot add a recipe they cooked from memory or fix a
quantity they got wrong. Editing has to exist on the phone.

This is a **deliberate departure from the handoff**, not an oversight — worth
recording, because the handoff is still the reference for everything else.

## What already exists

More than it looks like. The phone is not starting from nothing:

- `lib/ui/mobile/mobile_recipe.dart` already contains `MobileHandEntryPage`, a
  working create-only flow with title, ingredients and steps, including an
  ingredient parser that keeps quantity, unit and name as three separate fields
  and links to the pantry by name.
- `lib/ui/recipe/recipe_edit.dart` is the desktop editor, and the whole edit
  model it uses — `Recipe.copy()` into a `_draft`, mutate freely, then
  `AppState.saveRecipe(edited)` — is platform-agnostic. Nothing in it is
  desktop-specific except its layout.
- `AppState` mutations, stamping and tombstones are shared already.

So the work is a **phone-shaped surface over the existing edit model**, not a
second editor.

## Design

### One editor, two layouts — not two editors

The single most important constraint. A separate mobile editor would drift from
the desktop one, and the two would disagree about what saving means. Extract the
desktop editor's *behaviour* — the draft lifecycle, dirty tracking, validation,
component/ingredient/step mutation — into a shared controller, and let each
platform lay it out.

```dart
// lib/ui/recipe/recipe_edit_controller.dart
/// The draft a recipe is edited through, independent of how it is laid out.
///
/// Extracted so the phone and the desktop cannot drift apart about what an edit
/// *is*. Both hold one of these; only the widgets around it differ.
class RecipeEditController extends ChangeNotifier {
  RecipeEditController(Recipe original);
  Recipe get draft;
  bool get isDirty;
  void addComponent(); void renameComponent(String id, String name);
  void addIngredient(String componentId); void removeIngredient(String id);
  void reorderIngredient(String componentId, int from, int to);
  void addStep(String componentId); void removeStep(String id);
  Future<void> save(AppState app);
  void discard();
}
```

### The phone layout

The desktop editor is a two-column form; that does not fit 428dp. The phone gets
**one component at a time**, which also matches how the recipe reads there.

- A pushed full-screen route, not a dialog — `Scaffold` with a top bar carrying
  the title field, a dirty indicator and Save.
- Components as an expandable list; tapping one opens its ingredients and steps.
- Ingredient rows keep **quantity / unit / name as three fields** — this is
  non-negotiable, because collapsing them breaks serving scaling and pantry
  matching, which is the whole basis of the macro engine.
- Reordering by long-press drag, reusing `ReorderableListView`.
- `showPhoneSheet` for the meal-type picker and component add, matching the rest
  of the phone UI.

### Reaching it

The recipe screen's action row currently shows `＋ n missing` and `Start
cooking`. Add **Edit** beside them, matching the desktop's action row order.
`MobileHandEntryPage`'s "components are added on the desktop" note comes out,
and hand entry can then hand off to the full editor rather than being a
dead end.

## The bit that needs care

**`recipe_edit.dart` holds a `Recipe.copy()` across an async gap.** Flagged
during the sync milestone and still true. On the phone this gets worse: Android
can suspend and resume an app mid-edit, and a sync can land in between, so a
draft can be based on a recipe that no longer matches what is stored.

The controller should therefore:

- Record the `Stamp` of the recipe it was opened from.
- On save, compare against the current stored stamp. If it moved, do not
  silently overwrite — the user has just been handed a merge conflict by their
  own two devices. Surface it with the existing `conflict_review.dart`
  machinery rather than inventing a second mechanism.
- Persist the draft across process death (Android will kill a backgrounded app),
  so a half-written recipe is not lost. A draft file beside the databases is
  enough; it is not a database and must not sync.

## Build order

1. Extract `RecipeEditController` from `recipe_edit.dart`; desktop switches to
   it with **no behaviour change**. Milestone: existing tests green, desktop
   editing works exactly as before.
2. Controller tests — dirty tracking, add/remove/reorder, the three-field
   invariant, stale-stamp detection. Pure, no widgets.
3. Phone editor widgets over the controller. Milestone: `testWidgets` covering
   add an ingredient, reorder, save, discard.
4. Wire Edit into the mobile recipe screen; retire the hand-entry dead end.
5. Draft persistence across process death.

Steps 1–3 need no device. Step 4 is verifiable in the desktop mobile-preview
(`--dart-define=MOBILE_PREVIEW=true`); step 5 genuinely needs a phone, because
process death is the thing being tested.

## Consequences

- The handoff's "editing is desktop only" rule is retired. `README.md` and the
  mobile page doc comments that repeat it need updating, or they become lies.
- `SettingsPage(isPhone:)` still legitimately differs — database backup/import
  stays desktop-only, since that is about where files are kept, not about
  capability.
