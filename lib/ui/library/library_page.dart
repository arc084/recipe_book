import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../../theme/tokens.dart';
import '../import/import_flow.dart';
import '../widgets/primitives.dart';
import 'recipe_card.dart';
import 'suggestions_panel.dart';

/// The tab the app opens on.
///
/// Toolbar order is fixed — search, Suggestions, Import from web, Add recipe —
/// and only Add recipe is a primary action.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _search = TextEditingController();
  String _query = '';
  String? _mealTypeId; // null == All
  final _activeTags = <String>{};
  bool _suggestionsOpen = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Recipe> _filtered(AppState app) {
    final q = _query.trim().toLowerCase();
    return app.library.recipes.where((r) {
      if (_mealTypeId != null && r.mealTypeId != _mealTypeId) return false;
      // Tags filter on top of the meal type.
      if (_activeTags.isNotEmpty && !_activeTags.every(r.tags.contains)) {
        return false;
      }
      if (q.isEmpty) return true;
      return r.title.toLowerCase().contains(q) ||
          r.tags.any((t) => t.toLowerCase().contains(q)) ||
          r.ingredients.any((i) => i.name.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final recipes = _filtered(app);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(26, 20, 26, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _toolbar(context),
              const SizedBox(height: 16),
              if (!_suggestionsOpen) ...[
                _mealTypeTabs(context, app),
                _tagRow(context, app),
              ],
            ],
          ),
        ),
        Expanded(
          child: _suggestionsOpen
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(26, 0, 26, 22),
                  child: SuggestionsPanel(
                    onClose: () => setState(() => _suggestionsOpen = false),
                  ),
                )
              : _grid(context, recipes),
        ),
      ],
    );
  }

  // ── Toolbar ─────────────────────────────────────────────────────────────

  Widget _toolbar(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppTextField(
            controller: _search,
            hint: 'Search recipes, ingredients, tags…',
            icon: Icons.search,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(width: 10),
        // Suggestions is secondary, but carries the accent so it reads as the
        // one exploratory action in the row.
        _AccentOutlineButton(
          label: 'Suggestions',
          icon: Icons.auto_awesome_outlined,
          active: _suggestionsOpen,
          onTap: () => setState(() => _suggestionsOpen = !_suggestionsOpen),
        ),
        const SizedBox(width: 10),
        AppButton(
          'Import from web',
          icon: Icons.link,
          onPressed: () => ImportFlow.start(context),
        ),
        const SizedBox(width: 10),
        AppButton(
          'Add recipe',
          kind: ButtonKind.primary,
          icon: Icons.add,
          onPressed: () => _addRecipe(context),
        ),
      ],
    );
  }

  void _addRecipe(BuildContext context) {
    final app = context.read<AppState>();
    final types = app.mealTypes;
    final recipe = Recipe(
      id: newId(),
      title: 'New recipe',
      mealTypeId: (_mealTypeId ?? types.first.id),
      servings: 4,
    );
    // A recipe always has somewhere to put its first ingredient.
    final component = RecipeComponent(
      id: newId(),
      recipeId: recipe.id,
      name: 'Ingredients',
      order: 0,
    );
    recipe.components.add(component);
    app.saveRecipe(recipe);
    context.read<NavController>().openRecipe(recipe.id, edit: true);
  }

  // ── Meal types ──────────────────────────────────────────────────────────

  Widget _mealTypeTabs(BuildContext context, AppState app) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _MealTab(
              label: 'All',
              count: app.library.recipes.length,
              selected: _mealTypeId == null,
              onTap: () => setState(() => _mealTypeId = null),
            ),
            for (final type in app.mealTypes)
              _MealTab(
                label: type.name,
                count: app.recipeCountFor(type.id),
                selected: _mealTypeId == type.id,
                onTap: () => setState(() => _mealTypeId = type.id),
              ),
            // The ＋ adds a user-defined type.
            _MealTab(
              label: '＋',
              selected: false,
              muted: true,
              onTap: () => _addMealType(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMealType(BuildContext context) async {
    final name = await promptForText(
      context,
      title: 'New meal type',
      hint: 'Brunch',
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final type = context.read<AppState>().addMealType(name.trim());
    setState(() => _mealTypeId = type.id);
  }

  // ── Tags ────────────────────────────────────────────────────────────────

  Widget _tagRow(BuildContext context, AppState app) {
    final t = context.tokens;
    final tags = app.allTags;
    return Padding(
      padding: const EdgeInsets.only(top: 13, bottom: 16),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Text(
              'Tags',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11,
                color: t.textMuted,
              ),
            ),
          ),
          for (final tag in tags)
            Tag(
              tag,
              style: _activeTags.contains(tag)
                  ? TagStyle.accent
                  : TagStyle.outline,
              onTap: () => setState(() {
                _activeTags.contains(tag)
                    ? _activeTags.remove(tag)
                    : _activeTags.add(tag);
              }),
            ),
          if (_activeTags.isNotEmpty)
            GestureDetector(
              onTap: () => setState(_activeTags.clear),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'clear',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 11,
                      color: t.accent,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Grid ────────────────────────────────────────────────────────────────

  Widget _grid(BuildContext context, List<Recipe> recipes) {
    final t = context.tokens;

    if (recipes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Text(
            _query.isEmpty && _activeTags.isEmpty
                ? 'Nothing here yet. Add a recipe or import one from the web.'
                : 'No recipes match that.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 13,
              color: t.textMuted,
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // Three columns at the design width, and it reflows sensibly when the
        // window is resized rather than squeezing the cards.
        final available = constraints.maxWidth - 52;
        final columns = (available / 260).floor().clamp(1, 5);

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(26, 2, 26, 26),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            // 120px photo, then the body: 12 top padding, title, 8, the tag
            // row, 11, the divider'd meta row, 13 bottom padding.
            mainAxisExtent: 120 + 112,
          ),
          itemCount: recipes.length,
          itemBuilder: (context, i) => RecipeCard(
            recipe: recipes[i],
            onOpen: () =>
                context.read<NavController>().openRecipe(recipes[i].id),
          ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════

class _MealTab extends StatefulWidget {
  const _MealTab({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.muted = false,
  });

  final String label;
  final int? count;
  final bool selected;
  final bool muted;
  final VoidCallback onTap;

  @override
  State<_MealTab> createState() => _MealTabState();
}

class _MealTabState extends State<_MealTab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = widget.selected
        ? t.accent
        : widget.muted
            ? t.textFaint
            : _hover
                ? t.text
                : t.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(right: 22),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.only(bottom: 11),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: widget.selected ? t.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 13.5,
                    color: fg,
                    fontVariations: [
                      FontVariation('wght', widget.selected ? 500 : 400),
                    ],
                  ),
                ),
                if (widget.count != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${widget.count}',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 13.5,
                      color: widget.selected ? t.textMuted : t.textFaint,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The Suggestions button: secondary weight, accent outline.
class _AccentOutlineButton extends StatefulWidget {
  const _AccentOutlineButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  State<_AccentOutlineButton> createState() => _AccentOutlineButtonState();
}

class _AccentOutlineButtonState extends State<_AccentOutlineButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 32,
          padding: EdgeInsets.symmetric(horizontal: t.space(3) * 1.2),
          decoration: BoxDecoration(
            color: widget.active || _hover
                ? t.accent.withValues(alpha: widget.active ? 0.15 : 0.08)
                : Colors.transparent,
            border: Border.fromBorderSide(BorderSide(color: t.accent)),
            borderRadius: t.brControl,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 15, color: t.accent),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: t.headingFamily,
                  fontSize: 12.5,
                  color: t.accent,
                  fontVariations: [FontVariation('wght', t.headingWeight)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small single-field prompt, used wherever the design shows "＋ add".
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String? hint,
  String? initial,
  String confirmLabel = 'Add',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) {
      final t = context.tokens;
      return Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          width: 380,
          padding: EdgeInsets.all(t.space(4)),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: t.brLarge,
            boxShadow: t.shadowLg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              SizedBox(height: t.space(3)),
              AppTextField(
                controller: controller,
                hint: hint,
                autofocus: true,
                onSubmitted: (v) => Navigator.of(context).pop(v),
              ),
              SizedBox(height: t.space(4)),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    'Cancel',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    confirmLabel,
                    kind: ButtonKind.primary,
                    onPressed: () =>
                        Navigator.of(context).pop(controller.text),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
