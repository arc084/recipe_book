import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../domain/macros.dart';
import '../../domain/units.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../cook/cook_mode.dart';
import '../widgets/photo_picker.dart';
import '../widgets/primitives.dart';
import 'mobile_widgets.dart';

/// A recipe on Android: the two desktop columns stacked under the photo.
///
/// The phone reads, cooks and shops. There is no edit mode here — that is
/// desktop only.
class MobileRecipePage extends StatefulWidget {
  const MobileRecipePage({super.key, required this.recipeId});

  final String recipeId;

  @override
  State<MobileRecipePage> createState() => _MobileRecipePageState();
}

class _MobileRecipePageState extends State<MobileRecipePage> {
  int? _scaledServings;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();
    final recipe = app.recipe(widget.recipeId);
    if (recipe == null) return const SizedBox.shrink();

    final servings = _scaledServings ?? recipe.servings;
    final totals = app.macros.forRecipe(recipe, servings: servings);
    final cov = app.coverage.summarise(recipe);
    final coverage = app.coverage;
    final per = totals.perServing;
    final steps = recipe.orderedSteps;

    return Scaffold(
      backgroundColor: t.ground,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Stack(
              children: [
                // Dropping a file is a desktop gesture, so on the phone the
                // photo area is tapped instead.
                SizedBox(
                  height: 220,
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: () async {
                      final ok = await pickRecipePhoto(context, recipe.id);
                      if (ok && context.mounted) {
                        phoneToast(context, 'Photo saved with the recipe');
                      }
                    },
                    child: RecipePhoto(
                      path: recipe.photoPath,
                      placeholder: recipe.photoPath == null
                          ? 'Tap to add a photo'
                          : '${recipe.title} photo',
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, t.ground],
                          stops: const [0.35, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: CircleAvatar(
                      radius: 19,
                      backgroundColor: t.ground.withValues(alpha: 0.68),
                      child: IconButton(
                        icon: Icon(
                          Icons.arrow_back,
                          size: 19,
                          color: t.textStrong,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverList.list(
              children: [
                Text(
                  recipe.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < recipe.tags.length; i++)
                      Tag(
                        recipe.tags[i],
                        style: i == 0 ? TagStyle.accent : TagStyle.outline,
                      ),
                    if (app.mealType(recipe.mealTypeId) != null)
                      Tag(app.mealType(recipe.mealTypeId)!.name),
                  ],
                ),
                const SizedBox(height: 16),
                StatStrip(
                  valueSize: 17,
                  labelSize: 10.5,
                  padding: 13,
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
                if (!totals.isComplete || totals.isEstimated)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Text(
                      [
                        if (!totals.isComplete)
                          '${totals.gaps.length} not counted',
                        if (totals.isEstimated) 'includes estimated values',
                      ].join(' · '),
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 11,
                        color: t.accent,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (cov.toBuy.isNotEmpty) ...[
                      Expanded(
                        child: AppButton(
                          '＋ ${cov.toBuy.length} missing',
                          height: 44,
                          fontSize: 14,
                          onPressed: () {
                            final n = app.addMissingToGroceries(recipe);
                            phoneToast(context, '$n added to groceries');
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: AppButton(
                        'Start cooking',
                        kind: ButtonKind.primary,
                        height: 44,
                        fontSize: 14,
                        onPressed: () => CookMode.start(context, recipe.id),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    SectionLabel('Ingredients'),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${cov.have} of ${cov.total} in pantry',
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 11,
                          color: t.textFaint,
                        ),
                      ),
                    ),
                    AppIconButton(
                      icon: Icons.remove,
                      size: 30,
                      iconSize: 15,
                      onPressed: servings > 1
                          ? () => setState(() => _scaledServings = servings - 1)
                          : null,
                    ),
                    SizedBox(
                      width: 80,
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
                      size: 30,
                      iconSize: 15,
                      onPressed: () =>
                          setState(() => _scaledServings = servings + 1),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Panel(
                  clip: true,
                  child: Column(
                    children: [
                      for (final c in recipe.orderedComponents) ...[
                        Container(
                          width: double.infinity,
                          color: t.accent.withValues(alpha: 0.08),
                          padding: const EdgeInsets.fromLTRB(14, 8, 14, 7),
                          child: SectionLabel(
                            c.name,
                            color: t.accentText,
                            size: 10,
                          ),
                        ),
                        for (final line in recipe.ingredientsOf(c.id))
                          _row(
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
                const SizedBox(height: 24),
                Row(
                  children: [
                    SectionLabel('Method'),
                    const SizedBox(width: 8),
                    Text(
                      '${steps.length} steps · '
                      '${recipe.components.length} components',
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 11,
                        color: t.textFaint,
                      ),
                    ),
                  ],
                ),
                for (final c in recipe.orderedComponents) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 4),
                    child: Row(
                      children: [
                        SectionLabel(c.name, color: t.accentText, size: 10),
                        const SizedBox(width: 9),
                        Expanded(child: Container(height: 1, color: t.divider)),
                      ],
                    ),
                  ),
                  for (final step in recipe.stepsOf(c.id))
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 25,
                            height: 25,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.fromBorderSide(
                                BorderSide(color: t.accent),
                              ),
                            ),
                            child: Text(
                              '${steps.indexOf(step) + 1}',
                              style: TextStyle(
                                fontFamily: t.bodyFamily,
                                fontSize: 12,
                                color: t.accent,
                                height: 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Text(
                              step.text,
                              style: TextStyle(
                                fontFamily: t.bodyFamily,
                                fontSize: 14.5,
                                height: 1.55,
                                color: t.textStrong,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                if (recipe.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 24),
                  SectionLabel('Notes'),
                  const SizedBox(height: 8),
                  Text(
                    recipe.notes,
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 13.5,
                      height: 1.55,
                      color: t.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppState app,
    Recipe recipe,
    Ingredient line,
    CoverageResult cov,
    double scale,
  ) {
    final t = context.tokens;
    final (IconData icon, Color colour) = switch (cov.coverage) {
      Coverage.inPantry => (Icons.check, t.accent),
      Coverage.staple => (Icons.check, t.textFaint),
      Coverage.onList => (Icons.circle_outlined, t.accent),
      Coverage.outOfStock => (Icons.remove_circle_outline, t.accent),
      Coverage.missing => (Icons.priority_high, t.accent),
    };
    final scaled = line.quantity == null ? null : line.quantity! * scale;
    final amount = line.quantity == null
        ? line.unit
        : '${formatAmount(scaled)} ${line.unit}'.trim();

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.divider)),
        color: cov.countsAsMissing ? t.accent.withValues(alpha: 0.09) : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            Icon(icon, size: 16, color: colour),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                line.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 14,
                  color: t.text,
                ),
              ),
            ),
            if (cov.coverage == Coverage.missing ||
                cov.coverage == Coverage.outOfStock)
              AppButton(
                'add',
                kind: ButtonKind.ghost,
                fontSize: 12,
                height: 28,
                onPressed: () {
                  app.addGrocery(
                    line.name,
                    quantity: amount,
                    source: recipe.title,
                    pantryItemId: line.pantryItemId,
                  );
                  phoneToast(context, '${line.name} added to groceries');
                },
              )
            else
              Text(
                cov.coverage == Coverage.onList ? 'on your list' : amount,
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12.5,
                  color: cov.coverage == Coverage.onList
                      ? t.accentText
                      : t.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Hand entry
// ═══════════════════════════════════════════════════════════════════════════

/// Writing a recipe out by hand on the phone.
///
/// This is *creation*, not the edit mode — title, ingredients and steps only.
/// Components, and any later change to a saved recipe, are the desktop's job.
class MobileHandEntryPage extends StatefulWidget {
  const MobileHandEntryPage({super.key, required this.recipeId});

  final String recipeId;

  @override
  State<MobileHandEntryPage> createState() => _MobileHandEntryPageState();
}

class _MobileHandEntryPageState extends State<MobileHandEntryPage> {
  late Recipe _draft;
  final _title = TextEditingController();
  final _ingredient = TextEditingController();
  final _step = TextEditingController();

  @override
  void initState() {
    super.initState();
    _draft = context.read<AppState>().recipe(widget.recipeId)!.copy();
    _title.text = _draft.title;
  }

  @override
  void dispose() {
    _title.dispose();
    _ingredient.dispose();
    _step.dispose();
    super.dispose();
  }

  String get _componentId => _draft.components.first.id;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.read<AppState>();

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopBar(
              title: 'New recipe',
              onBack: () {
                // Nothing was meant to be kept if they backed out empty.
                if (_draft.title.trim().isEmpty &&
                    _draft.ingredients.isEmpty &&
                    _draft.steps.isEmpty) {
                  app.deleteRecipe(_draft.id);
                }
                Navigator.of(context).pop();
              },
              actions: [
                AppButton(
                  'Save',
                  kind: ButtonKind.primary,
                  onPressed: _title.text.trim().isEmpty
                      ? null
                      : () {
                          _draft.title = _title.text.trim();
                          app.saveRecipe(_draft);
                          Navigator.of(context).pop();
                        },
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  AppTextField(
                    controller: _title,
                    hint: 'Recipe title',
                    height: 48,
                    fontSize: 16,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 22),
                  SectionLabel('Ingredients'),
                  const SizedBox(height: 8),
                  for (final line in _draft.ingredientsOf(_componentId))
                    _chipLine(
                      context,
                      '${formatAmount(line.quantity)} ${line.unit} ${line.name}'
                          .trim(),
                      () => setState(() => _draft.ingredients.remove(line)),
                    ),
                  AppTextField(
                    controller: _ingredient,
                    hint: 'e.g. 400 g canned tomatoes',
                    height: 44,
                    onSubmitted: (v) {
                      if (v.trim().isEmpty) return;
                      setState(() {
                        _draft.ingredients.add(_parse(v.trim()));
                        _ingredient.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 22),
                  SectionLabel('Method'),
                  const SizedBox(height: 8),
                  for (final step in _draft.stepsOf(_componentId))
                    _chipLine(
                      context,
                      step.text,
                      () => setState(() => _draft.steps.remove(step)),
                    ),
                  AppTextField(
                    controller: _step,
                    hint: 'Add a step',
                    height: 44,
                    onSubmitted: (v) {
                      if (v.trim().isEmpty) return;
                      setState(() {
                        _draft.steps.add(
                          RecipeStep(
                            id: newId(),
                            componentId: _componentId,
                            text: v.trim(),
                            order: _draft.steps.length,
                          ),
                        );
                        _step.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Components — Cutlets, Breading and so on — are added on '
                    'the desktop.',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 11.5,
                      height: 1.5,
                      color: t.textFaint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Reuses the importer's splitting so a typed line keeps quantity, unit and
  /// name as three fields.
  Ingredient _parse(String raw) {
    final m = RegExp(r'^([\d.,/]+)\s*([A-Za-z]+)?\s+(.+)$').firstMatch(raw);
    final app = context.read<AppState>();
    var qty = <double?>[null].first;
    var unit = '';
    var name = raw;

    if (m != null && RegExp(r'^\d').hasMatch(m.group(1)!)) {
      qty = double.tryParse(m.group(1)!.replaceAll(',', '.'));
      final maybeUnit = m.group(2) ?? '';
      if (toBase(1, maybeUnit) != null && maybeUnit.isNotEmpty) {
        unit = maybeUnit;
        name = m.group(3)!;
      } else {
        name = '${m.group(2) ?? ''} ${m.group(3)}'.trim();
      }
    }

    final match = app.pantry.items
        .where((p) => p.matchesName(name))
        .firstOrNull;

    return Ingredient(
      id: newId(),
      componentId: _componentId,
      quantity: qty,
      unit: unit,
      name: name,
      pantryItemId: match?.id,
      order: _draft.ingredients.length,
    );
  }

  Widget _chipLine(BuildContext context, String text, VoidCallback onRemove) {
    final t = context.tokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
      decoration: BoxDecoration(color: t.surface, borderRadius: t.brContainer),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 13.5,
                color: t.text,
              ),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: t.textMuted),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
