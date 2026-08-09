import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../domain/macros.dart';
import '../../domain/units.dart';
import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../../theme/tokens.dart';
import '../cook/cook_mode.dart';
import '../widgets/primitives.dart';
import 'recipe_edit.dart';

/// Opening a recipe.
///
/// Two columns, neither scrolling the other: ingredients fixed on the left,
/// method reading down the right. The actions that matter in a kitchen sit
/// above the fold.
class RecipePage extends StatefulWidget {
  const RecipePage({super.key, required this.recipeId});

  final String recipeId;

  @override
  State<RecipePage> createState() => _RecipePageState();
}

class _RecipePageState extends State<RecipePage> {
  /// Serving scaling lives on the view, not the edit screen: it recalculates
  /// quantities and macros without touching the saved recipe.
  int? _scaledServings;
  bool _dragOver = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final nav = context.watch<NavController>();
    final recipe = app.recipe(widget.recipeId);

    if (recipe == null) {
      return const Center(child: Text('That recipe is gone.'));
    }

    if (nav.editing) {
      return RecipeEditView(recipeId: widget.recipeId);
    }

    final servings = _scaledServings ?? recipe.servings;
    final totals = app.macros.forRecipe(recipe, servings: servings);
    final cov = app.coverage.summarise(recipe);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _hero(context, recipe),
        _header(context, app, recipe, totals, cov),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 18, 26, 22),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 322,
                  child: _ingredientColumn(
                    context,
                    app,
                    recipe,
                    totals,
                    cov,
                    servings,
                  ),
                ),
                const SizedBox(width: 22),
                Expanded(child: _methodColumn(context, recipe)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Hero ────────────────────────────────────────────────────────────────

  Widget _hero(BuildContext context, Recipe recipe) {
    final t = context.tokens;
    return SizedBox(
      height: 196,
      child: DropTarget(
        onDragEntered: (_) => setState(() => _dragOver = true),
        onDragExited: (_) => setState(() => _dragOver = false),
        onDragDone: (detail) {
          setState(() => _dragOver = false);
          final file = detail.files.firstOrNull;
          if (file == null) return;
          context.read<AppState>().setRecipePhoto(recipe.id, file.path);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            RecipePhoto(
              path: recipe.photoPath,
              placeholder: 'Drop a photo of ${recipe.title}',
              hovering: _dragOver,
            ),
            // The photo fades into the ground so the title sits on it cleanly.
            IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, t.ground],
                    stops: const [0.3, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 14,
              left: 18,
              child: _BackChip(
                onTap: () => context.read<NavController>().closeRecipe(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Title and actions ───────────────────────────────────────────────────

  Widget _header(
    BuildContext context,
    AppState app,
    Recipe recipe,
    MacroTotals totals,
    ({
      int have,
      int total,
      List<CoverageResult> missing,
      List<CoverageResult> toBuy,
    }) cov,
  ) {
    final t = context.tokens;
    final mealType = app.mealType(recipe.mealTypeId);

    return Transform.translate(
      offset: const Offset(0, -30),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    recipe.title,
                    style: Theme.of(context).textTheme.displaySmall,
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (var i = 0; i < recipe.tags.length; i++)
                        Tag(
                          recipe.tags[i],
                          style:
                              i == 0 ? TagStyle.accent : TagStyle.outline,
                        ),
                      if (mealType != null) Tag(mealType.name),
                      Padding(
                        padding: const EdgeInsets.only(left: 5),
                        child: Text(
                          _provenance(recipe),
                          style: TextStyle(
                            fontFamily: t.bodyFamily,
                            fontSize: 11.5,
                            color: t.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIconButton(
                  icon: Icons.star_border,
                  size: 34,
                  tooltip: 'Favourite',
                  onPressed: () {},
                ),
                const SizedBox(width: 8),
                // Editing is desktop only, which is where we are.
                AppButton(
                  'Edit',
                  onPressed: () =>
                      context.read<NavController>().editRecipe(true),
                ),
                const SizedBox(width: 8),
                if (cov.missing.isNotEmpty)
                  AppButton(
                    '＋ ${cov.missing.length} missing '
                    '${cov.missing.length == 1 ? 'item' : 'items'}',
                    onPressed: () {
                      final n = app.addMissingToGroceries(recipe);
                      _toast(context, '$n added to groceries');
                    },
                  ),
                if (cov.missing.isNotEmpty) const SizedBox(width: 8),
                AppButton(
                  'Start cooking',
                  kind: ButtonKind.primary,
                  onPressed: () => CookMode.start(context, recipe.id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _provenance(Recipe r) {
    final parts = <String>[];
    if (r.sourceUrl != null) {
      final host = Uri.tryParse(r.sourceUrl!)?.host.replaceFirst('www.', '');
      if (host != null && host.isNotEmpty) parts.add('from $host');
    }
    if (r.timesCooked > 0) parts.add('cooked ${r.timesCooked}×');
    return parts.join(' · ');
  }

  // ── Ingredients ─────────────────────────────────────────────────────────

  Widget _ingredientColumn(
    BuildContext context,
    AppState app,
    Recipe recipe,
    MacroTotals totals,
    ({
      int have,
      int total,
      List<CoverageResult> missing,
      List<CoverageResult> toBuy,
    }) cov,
    int servings,
  ) {
    final t = context.tokens;
    final per = totals.perServing;
    final coverage = app.coverage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatStrip(
          cells: [
            (
              value: recipe.totalMinutes == null
                  ? '—'
                  : '${recipe.totalMinutes} min',
              label: 'total',
            ),
            (value: per.calories.round().toString(), label: 'cal'),
            (value: '${per.protein.round()}g', label: 'protein'),
          ],
        ),
        // Anything inheriting estimated values says so on the totals.
        if (totals.isEstimated || !totals.isComplete)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              [
                if (!totals.isComplete)
                  '${totals.gaps.length} '
                      '${totals.gaps.length == 1 ? 'ingredient is' : 'ingredients are'}'
                      ' not counted',
                if (totals.isEstimated) 'includes estimated values',
              ].join(' · '),
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 10.5,
                color: t.accent,
              ),
            ),
          ),
        const SizedBox(height: 14),
        Row(
          children: [
            SectionLabel('Ingredients'),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                '${cov.have} of ${cov.total} in pantry · '
                '${recipe.components.length} components',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 11,
                  color: t.textFaint,
                ),
              ),
            ),
            AppIconButton(
              icon: Icons.remove,
              size: 26,
              iconSize: 13,
              onPressed: servings > 1
                  ? () => setState(() => _scaledServings = servings - 1)
                  : null,
            ),
            SizedBox(
              width: 72,
              child: Text(
                '$servings ${servings == 1 ? 'serving' : 'servings'}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12,
                  color: servings == recipe.servings
                      ? t.textSecondary
                      : t.accent,
                ),
              ),
            ),
            AppIconButton(
              icon: Icons.add,
              size: 26,
              iconSize: 13,
              onPressed: () => setState(() => _scaledServings = servings + 1),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Expanded(
          child: Panel(
            clip: true,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final component in recipe.orderedComponents) ...[
                  _componentHeading(context, component.name),
                  for (final line in recipe.ingredientsOf(component.id))
                    _ingredientRow(
                      context,
                      app,
                      recipe,
                      line,
                      coverage.of(line),
                      servings / recipe.servings,
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _componentHeading(BuildContext context, String name) {
    final t = context.tokens;
    return Container(
      width: double.infinity,
      color: t.accent.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(13, 7, 13, 6),
      child: SectionLabel(name, color: t.accentText, size: 10),
    );
  }

  Widget _ingredientRow(
    BuildContext context,
    AppState app,
    Recipe recipe,
    Ingredient line,
    CoverageResult cov,
    double scale,
  ) {
    final t = context.tokens;

    // Pantry coverage is shown on every ingredient: what the user has is
    // ticked, what is missing is called out with one action to add it.
    final (IconData icon, Color colour) = switch (cov.coverage) {
      Coverage.inPantry => (Icons.check, t.accent),
      Coverage.staple => (Icons.check, t.textFaint),
      Coverage.onList => (Icons.circle_outlined, t.accent),
      Coverage.missing => (Icons.priority_high, t.accent),
    };

    final scaled = line.quantity == null ? null : line.quantity! * scale;
    final amount = line.quantity == null
        ? line.unit
        : '${formatAmount(scaled)} ${line.unit}'.trim();

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.divider)),
        color: cov.coverage == Coverage.missing || cov.coverage == Coverage.onList
            ? t.accent.withValues(alpha: 0.09)
            : null,
      ),
      child: HoverRow(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: SizedBox(
            height: 36,
            child: Row(
              children: [
                Icon(icon, size: 15, color: colour),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    line.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 13,
                      color: t.text,
                    ),
                  ),
                ),
                if (cov.coverage == Coverage.missing)
                  AppButton(
                    'add',
                    kind: ButtonKind.ghost,
                    fontSize: 11,
                    height: 22,
                    onPressed: () {
                      app.addGrocery(
                        line.name,
                        quantity: amount,
                        source: recipe.title,
                        pantryItemId: line.pantryItemId,
                      );
                      _toast(context, '${line.name} added to groceries');
                    },
                  )
                else
                  Text(
                    cov.coverage == Coverage.onList ? 'on your list' : amount,
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 11.5,
                      color: cov.coverage == Coverage.onList
                          ? t.accentText
                          : t.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Method ──────────────────────────────────────────────────────────────

  Widget _methodColumn(BuildContext context, Recipe recipe) {
    final t = context.tokens;
    final steps = recipe.orderedSteps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SectionLabel('Method'),
            const SizedBox(width: 9),
            Text(
              '${steps.length} steps · ${recipe.components.length} components',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11,
                color: t.textFaint,
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(right: 4),
            children: [
              for (final component in recipe.orderedComponents) ...[
                _methodHeading(
                  context,
                  component.name,
                  recipe.stepsOf(component.id).length,
                ),
                for (final step in recipe.stepsOf(component.id))
                  _step(context, steps.indexOf(step) + 1, step.text),
              ],
              if (recipe.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 18),
                _methodHeading(context, 'Notes', null),
                const SizedBox(height: 10),
                Text(
                  recipe.notes,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 13,
                    height: 1.55,
                    color: t.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _methodHeading(BuildContext context, String name, int? stepCount) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SectionLabel(name, color: t.accentText, size: 10),
          if (stepCount != null) ...[
            const SizedBox(width: 9),
            Text(
              '$stepCount ${stepCount == 1 ? 'step' : 'steps'}',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 10.5,
                color: t.textFaint,
              ),
            ),
          ],
          const SizedBox(width: 9),
          Expanded(child: Container(height: 1, color: t.divider)),
        ],
      ),
    );
  }

  Widget _step(BuildContext context, int number, String text) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.only(top: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 23,
            height: 23,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.fromBorderSide(BorderSide(color: t.accent)),
            ),
            child: Text(
              '$number',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11.5,
                color: t.accent,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 13.5,
                height: 1.55,
                color: t.textStrong,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackChip extends StatelessWidget {
  const _BackChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 32,
          padding: const EdgeInsets.only(left: 9, right: 12),
          decoration: BoxDecoration(
            color: t.ground.withValues(alpha: 0.68),
            borderRadius: t.brContainer,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chevron_left, size: 18, color: t.textStrong),
              const SizedBox(width: 4),
              Text(
                'Library',
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12.5,
                  color: t.textStrong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Adding to groceries never leaves the screen the user was on, so it says so
/// in place.
void _toast(BuildContext context, String message) {
  final t = context.tokens;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 12.5,
            color: t.text,
          ),
        ),
        backgroundColor: t.surface,
        behavior: SnackBarBehavior.floating,
        width: 320,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: t.brContainer),
      ),
    );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
