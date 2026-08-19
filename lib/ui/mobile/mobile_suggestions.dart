import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets/primitives.dart';
import 'mobile_recipe.dart';
import 'mobile_widgets.dart';

/// Suggestions on Android.
///
/// The same results and the same figures as the desktop; the phone stacks each
/// row's macros under its title.
class MobileSuggestionsPage extends StatefulWidget {
  const MobileSuggestionsPage({super.key});

  @override
  State<MobileSuggestionsPage> createState() => _MobileSuggestionsPageState();
}

class _MobileSuggestionsPageState extends State<MobileSuggestionsPage> {
  final _controller = TextEditingController();
  final _ingredients = <String>[];
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
    final results = app.suggestions(withIngredients: _ingredients, sort: _sort);

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: [
            const MobileTopBar(title: 'Suggestions'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Name an ingredient you want to cook with — or leave it '
                    'empty to match your whole pantry.',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 12.5,
                      height: 1.5,
                      color: t.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppTextField(
                    controller: _controller,
                    hint: 'chicken breast',
                    icon: Icons.search,
                    height: 46,
                    fontSize: 14,
                    onSubmitted: (v) {
                      if (v.trim().isEmpty) return;
                      setState(() {
                        _ingredients.add(v.trim());
                        _controller.clear();
                      });
                    },
                  ),
                  if (_ingredients.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final ing in _ingredients)
                          Tag(
                            ing,
                            style: TagStyle.accent,
                            trailing: GestureDetector(
                              onTap: () =>
                                  setState(() => _ingredients.remove(ing)),
                              child: Icon(
                                Icons.close,
                                size: 12,
                                color: t.tagAccentFg,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            ChipRow(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              children: [
                for (final s in SuggestionSort.values)
                  TouchChip(
                    label: s.label,
                    fontSize: 12,
                    selected: _sort == s,
                    onTap: () => setState(() => _sort = s),
                  ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Row(
                    children: [
                      SectionLabel('In your recipes'),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${results.length} · macros from your pantry',
                          style: TextStyle(
                            fontFamily: t.bodyFamily,
                            fontSize: 11,
                            color: t.textFaint,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final row in results)
                    _row(
                      context,
                      app,
                      row.recipe.id,
                      row.missing,
                      row.missingNames,
                    ),
                  const SizedBox(height: 20),
                  SectionLabel('From the web', color: t.textFaint),
                  const SizedBox(height: 8),
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
                      'marked approximate until you save one.',
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 12.5,
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
      ),
    );
  }

  Widget _row(
    BuildContext context,
    AppState app,
    String recipeId,
    int missing,
    List<String> missingNames,
  ) {
    final t = context.tokens;
    final recipe = app.recipe(recipeId)!;
    final per = app.macros.forRecipe(recipe).perServing;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: t.brContainer,
        boxShadow: t.shadowSm,
      ),
      child: InkWell(
        borderRadius: t.brContainer,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MobileRecipePage(recipeId: recipeId),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                recipe.title,
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 14.5,
                  color: t.text,
                ),
              ),
              const SizedBox(height: 5),
              // The phone stacks the macros under the title.
              Text(
                '${per.calories.round()} cal · ${per.protein.round()}g '
                'protein${recipe.totalMinutes == null ? '' : ' · ${recipe.totalMinutes} min'}',
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12,
                  color: t.textStrong,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                missing == 0
                    ? 'Everything in your pantry'
                    : '$missing missing · ${missingNames.join(', ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 11.5,
                  color: missing == 0 ? t.accent : t.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
