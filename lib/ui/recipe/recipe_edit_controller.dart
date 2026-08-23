import 'package:flutter/foundation.dart';

import '../../data/models.dart';
import '../../domain/sync/stamp.dart';
import '../../state/app_state.dart';

/// What became of a save.
enum SaveOutcome {
  /// Written. The draft is now the stored recipe.
  saved,

  /// Not written: the stored recipe moved while this draft was open — a sync
  /// landed, or another device wrote through a shared folder. Overwriting
  /// silently would throw that edit away, so the caller must put the choice
  /// to the user instead.
  stale,
}

/// The draft a recipe is edited through, independent of how it is laid out.
///
/// Extracted so the phone and the desktop cannot drift apart about what an
/// edit *is*. Both hold one of these; only the widgets around it differ.
///
/// Field edits go through [change]; structural edits — components, lines,
/// steps and their order — have their own methods, because getting `order`
/// and cascade-deletes right is exactly what the two layouts must agree on.
class RecipeEditController extends ChangeNotifier {
  RecipeEditController(Recipe original)
    : _original = original,
      draft = original.copy(),
      openedFrom = original.stamp;

  final Recipe _original;

  /// A deep copy, so abandoning the edit leaves the saved recipe untouched.
  final Recipe draft;

  /// The stored recipe's stamp at the moment the draft was taken. [save]
  /// compares against the store before writing: a draft may outlive a sync,
  /// especially on a phone that was suspended mid-edit.
  final Stamp openedFrom;

  bool _dirty = false;
  bool get isDirty => _dirty;

  /// Runs a field mutation on [draft] and marks the edit dirty.
  void change(VoidCallback mutate) {
    mutate();
    _dirty = true;
    notifyListeners();
  }

  /// How many fields differ from the recipe as it was opened — the footer's
  /// "n unsaved changes".
  int get changeCount {
    var n = 0;
    if (draft.title != _original.title) n++;
    if (draft.mealTypeId != _original.mealTypeId) n++;
    if (draft.servings != _original.servings) n++;
    if (draft.totalMinutes != _original.totalMinutes) n++;
    if (draft.notes != _original.notes) n++;
    if (draft.tags.join(',') != _original.tags.join(',')) n++;
    if (draft.ingredients.length != _original.ingredients.length) n++;
    if (draft.steps.length != _original.steps.length) n++;
    if (draft.components.length != _original.components.length) n++;
    for (final line in draft.ingredients) {
      final was = _original.ingredients
          .where((i) => i.id == line.id)
          .firstOrNull;
      if (was == null) continue;
      if (was.name != line.name ||
          was.quantity != line.quantity ||
          was.unit != line.unit) {
        n++;
      }
    }
    for (final step in draft.steps) {
      final was = _original.steps.where((s) => s.id == step.id).firstOrNull;
      if (was != null && was.text != step.text) n++;
    }
    return n;
  }

  // ── Components ──────────────────────────────────────────────────────────

  RecipeComponent addComponent(String name) {
    final component = RecipeComponent(
      id: newId(),
      recipeId: draft.id,
      name: name,
      order: draft.components.length,
    );
    change(() => draft.components.add(component));
    return component;
  }

  void renameComponent(String id, String name) {
    final component = draft.components.where((c) => c.id == id).firstOrNull;
    if (component == null) return;
    change(() => component.name = name);
  }

  /// A component takes its ingredients and steps with it — otherwise they
  /// would linger in the lists, invisible to every screen that groups by
  /// component but still counted and still synced.
  void removeComponent(String id) {
    change(() {
      draft.components.removeWhere((c) => c.id == id);
      draft.ingredients.removeWhere((i) => i.componentId == id);
      draft.steps.removeWhere((s) => s.componentId == id);
    });
  }

  // ── Ingredients ─────────────────────────────────────────────────────────

  Ingredient addIngredient(String componentId) {
    final line = Ingredient(
      id: newId(),
      componentId: componentId,
      quantity: null,
      unit: '',
      name: '',
      order: draft.ingredients.length,
    );
    change(() => draft.ingredients.add(line));
    return line;
  }

  void removeIngredient(String id) {
    change(() => draft.ingredients.removeWhere((i) => i.id == id));
  }

  void reorderIngredient(String componentId, int from, int to) {
    change(() => _reorder(draft.ingredientsOf(componentId), from, to));
  }

  // ── Steps ───────────────────────────────────────────────────────────────

  RecipeStep addStep(String componentId, {String text = ''}) {
    final step = RecipeStep(
      id: newId(),
      componentId: componentId,
      text: text,
      order: draft.steps.length,
    );
    change(() => draft.steps.add(step));
    return step;
  }

  void removeStep(String id) {
    change(() => draft.steps.removeWhere((s) => s.id == id));
  }

  void reorderStep(String componentId, int from, int to) {
    change(() => _reorder(draft.stepsOf(componentId), from, to));
  }

  /// Moves an entry within one component's sorted list, then rewrites the
  /// `order` fields sequentially. Orders are only ever compared within a
  /// component, so renumbering here cannot disturb any other component.
  void _reorder(List<dynamic> sorted, int from, int to) {
    if (from < 0 || from >= sorted.length) return;
    final clamped = to.clamp(0, sorted.length - 1);
    final moved = sorted.removeAt(from);
    sorted.insert(clamped, moved);
    for (var i = 0; i < sorted.length; i++) {
      sorted[i].order = i;
    }
  }

  // ── Finishing ───────────────────────────────────────────────────────────

  /// Writes the draft, unless the stored recipe moved while it was open.
  ///
  /// Stale means *not written*: the user has effectively been handed a merge
  /// conflict by their own two devices, and the caller surfaces it with the
  /// same review the sync merge uses. [saveAnyway] is the "keep this
  /// device's" answer.
  SaveOutcome save(AppState app) {
    final stored = app.recipe(draft.id);
    if (stored == null || stored.stamp != openedFrom) return SaveOutcome.stale;
    saveAnyway(app);
    return SaveOutcome.saved;
  }

  /// Writes the draft regardless of what the store holds — the resolution of
  /// a stale save in the draft's favour.
  void saveAnyway(AppState app) {
    app.saveRecipe(draft);
    _dirty = false;
    notifyListeners();
  }

  /// Abandons the draft. The stored recipe was never touched.
  void discard() {
    _dirty = false;
    notifyListeners();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
