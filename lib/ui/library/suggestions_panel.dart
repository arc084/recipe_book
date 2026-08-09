import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../../theme/tokens.dart';
import '../widgets/primitives.dart';

/// Opens from the Library toolbar.
///
/// The user's own recipes come first, with calculated macros and anything
/// missing named. Web results sit below them and are marked approximate until
/// saved — the app is offline by design, so that half only fills in once a
/// fetch has actually happened.
class SuggestionsPanel extends StatefulWidget {
  const SuggestionsPanel({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  State<SuggestionsPanel> createState() => _SuggestionsPanelState();
}

class _SuggestionsPanelState extends State<SuggestionsPanel> {
  final _ingredients = <String>[];
  final _controller = TextEditingController();
  SuggestionSort _sort = SuggestionSort.pantryMatch;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();
    final results = app.suggestions(
      withIngredients: _ingredients,
      sort: _sort,
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.radiusLarge * 0.85),
        boxShadow: [
          ...t.shadowLg,
          BoxShadow(color: t.divider, spreadRadius: 1, blurRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Suggestions',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Name an ingredient you want to cook with — or '
                            'leave it empty to match your whole pantry.',
                            style: TextStyle(
                              fontFamily: t.bodyFamily,
                              fontSize: 12,
                              color: t.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppIconButton(
                      icon: Icons.close,
                      bordered: false,
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
                const SizedBox(height: 13),
                _ingredientField(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 11, 2, 14),
                  child: Row(
                    children: [
                      Text(
                        'Sort',
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 11,
                          color: t.textMuted,
                        ),
                      ),
                      const SizedBox(width: 7),
                      _SortSegment(
                        value: _sort,
                        onChanged: (v) => setState(() => _sort = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              children: [
                Row(
                  children: [
                    Icon(Icons.menu_book_outlined, size: 15, color: t.accent),
                    const SizedBox(width: 8),
                    SectionLabel('In your recipes', color: t.textStrong),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${results.length} of ${app.library.recipes.length}'
                        '${_ingredients.isEmpty ? '' : ' use ${_ingredients.join(', ')}'}'
                        ' · macros calculated from your pantry items',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 11,
                          color: t.textFaint,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                if (results.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'Nothing in your library uses that.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 12.5,
                        color: t.textMuted,
                      ),
                    ),
                  ),
                for (final row in results) _row(context, app, row),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Icon(Icons.public, size: 15, color: t.textFaint),
                    const SizedBox(width: 8),
                    SectionLabel('From the web', color: t.textFaint),
                  ],
                ),
                const SizedBox(height: 9),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: t.brContainer,
                    border: Border.fromBorderSide(
                      BorderSide(color: t.divider),
                    ),
                  ),
                  child: Text(
                    'Web results appear here once a search runs, and stay '
                    'marked approximate until you save one — a saved recipe '
                    'takes its figures from your pantry like everything else.',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 12,
                      height: 1.5,
                      color: t.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ingredientField(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.ground,
        borderRadius: t.brContainer,
        border: Border.fromBorderSide(BorderSide(color: t.accent)),
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: t.accent),
          const SizedBox(width: 8),
          for (final ing in _ingredients) ...[
            Tag(
              ing,
              style: TagStyle.accent,
              trailing: GestureDetector(
                onTap: () => setState(() => _ingredients.remove(ing)),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Icon(
                    Icons.close,
                    size: 11,
                    color: t.tagAccentFg.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: SizedBox(
              height: 22,
              child: TextField(
                controller: _controller,
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12.5,
                  color: t.text,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  hintText: 'add another…',
                  hintStyle: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 12.5,
                    color: t.textFaint,
                  ),
                ),
                onSubmitted: (v) {
                  if (v.trim().isEmpty) return;
                  setState(() {
                    _ingredients.add(v.trim());
                    _controller.clear();
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppState app,
    ({Recipe recipe, int missing, List<String> missingNames}) row,
  ) {
    final t = context.tokens;
    final totals = app.macros.forRecipe(row.recipe);
    final per = totals.perServing;

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: HoverRow(
        borderRadius: t.brContainer,
        onTap: () {
          context.read<NavController>().openRecipe(row.recipe.id);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.recipe.title,
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 13,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      row.missing == 0
                          ? 'Everything in your pantry'
                          : '${row.missing} missing · '
                              '${row.missingNames.join(', ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 11,
                        color: row.missing == 0 ? t.accent : t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _Fig('${per.calories.round()}', 'cal'),
              const SizedBox(width: 16),
              _Fig('${per.protein.round()}g', 'protein'),
              const SizedBox(width: 16),
              SizedBox(
                width: 52,
                child: Text(
                  row.recipe.totalMinutes == null
                      ? '—'
                      : '${row.recipe.totalMinutes} min',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 11.5,
                    color: t.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Fig extends StatelessWidget {
  const _Fig(this.value, this.label);

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 12.5,
            color: t.text,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 11,
            color: t.textMuted,
          ),
        ),
      ],
    );
  }
}

class _SortSegment extends StatelessWidget {
  const _SortSegment({required this.value, required this.onChanged});

  final SuggestionSort value;
  final ValueChanged<SuggestionSort> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.fromBorderSide(BorderSide(color: t.divider)),
        borderRadius: t.brControl,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < SuggestionSort.values.length; i++) ...[
            if (i > 0) Container(width: 1, height: 24, color: t.divider),
            _SegOption(
              label: SuggestionSort.values[i].label,
              selected: value == SuggestionSort.values[i],
              onTap: () => onChanged(SuggestionSort.values[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegOption extends StatefulWidget {
  const _SegOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SegOption> createState() => _SegOptionState();
}

class _SegOptionState extends State<_SegOption> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // Nocturne marks the selected option with the accent on a tint; Organic
    // fills it and flips the text to the ground colour.
    final selectedBg = t.primaryButtonIsFilled
        ? t.accent
        : t.accent.withValues(alpha: 0.15);
    final selectedFg = t.primaryButtonIsFilled ? t.ground : t.accent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          color: widget.selected
              ? selectedBg
              : _hover
                  ? t.text.withValues(alpha: 0.07)
                  : Colors.transparent,
          child: Text(
            widget.label,
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 11,
              color: widget.selected ? selectedFg : t.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
