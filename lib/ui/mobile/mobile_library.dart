import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../import/import_flow.dart';
import '../widgets/primitives.dart';
import 'mobile_recipe.dart';
import 'mobile_suggestions.dart';
import 'mobile_widgets.dart';

/// The Library on Android.
///
/// Same content as the desktop: the toolbar splits across two rows,
/// Suggestions sits beside search, and Add recipe becomes the floating action
/// button.
class MobileLibraryPage extends StatefulWidget {
  const MobileLibraryPage({super.key});

  @override
  State<MobileLibraryPage> createState() => _MobileLibraryPageState();
}

class _MobileLibraryPageState extends State<MobileLibraryPage> {
  final _search = TextEditingController();
  String _query = '';
  String? _mealTypeId;
  final _activeTags = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Recipe> _filtered(AppState app) {
    final q = _query.trim().toLowerCase();
    return app.library.recipes.where((r) {
      if (_mealTypeId != null && r.mealTypeId != _mealTypeId) return false;
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
    final t = context.tokens;
    final app = context.watch<AppState>();
    final recipes = _filtered(app);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const MobileHeader(title: 'My Cookbook'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: _search,
                      hint: 'Search recipes, ingredients',
                      icon: Icons.search,
                      height: 48,
                      fontSize: 14,
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                  const SizedBox(width: 9),
                  _SuggestionsButton(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const MobileSuggestionsPage(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Meal types scroll on the phone — the same six, same order,
            // each carrying its count.
            ChipRow(
              children: [
                TouchChip(
                  label: 'All',
                  count: app.library.recipes.length,
                  selected: _mealTypeId == null,
                  onTap: () => setState(() => _mealTypeId = null),
                ),
                for (final type in app.mealTypes)
                  TouchChip(
                    label: type.name,
                    count: app.recipeCountFor(type.id),
                    selected: _mealTypeId == type.id,
                    onTap: () => setState(() => _mealTypeId = type.id),
                  ),
              ],
            ),
            ChipRow(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              children: [
                for (final tag in app.allTags)
                  TouchChip(
                    label: tag,
                    fontSize: 12,
                    selected: _activeTags.contains(tag),
                    onTap: () => setState(() {
                      _activeTags.contains(tag)
                          ? _activeTags.remove(tag)
                          : _activeTags.add(tag);
                    }),
                  ),
              ],
            ),
            Expanded(
              child: recipes.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          'Nothing matches that.',
                          style: TextStyle(
                            fontFamily: t.bodyFamily,
                            fontSize: 13.5,
                            color: t.textMuted,
                          ),
                        ),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        mainAxisExtent: 104 + 92,
                      ),
                      itemCount: recipes.length,
                      itemBuilder: (context, i) =>
                          _PhoneCard(recipe: recipes[i]),
                    ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: PhoneFab(onTap: () => _openAddSheet(context)),
        ),
      ],
    );
  }

  /// The ＋ on the phone: the clipboard is offered by name when it holds a
  /// recipe address, then Import from a link, then hand entry. Components are
  /// added on the desktop.
  Future<void> _openAddSheet(BuildContext context) async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clip?.text?.trim() ?? '';
    final uri = Uri.tryParse(text);
    final clipboardUrl =
        (uri != null && (uri.scheme == 'http' || uri.scheme == 'https'))
            ? text
            : null;

    if (!context.mounted) return;

    await showPhoneSheet<void>(
      context,
      title: 'Add a recipe',
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (clipboardUrl != null)
            SheetRow(
              icon: Icons.content_paste,
              title: 'Import ${_hostOf(clipboardUrl)}',
              detail: clipboardUrl,
              accent: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                ImportFlow.startWithUrl(context, clipboardUrl);
              },
            ),
          SheetRow(
            icon: Icons.link,
            title: 'Import from a link',
            detail: 'Paste an address, or share a page to Recipe Book',
            onTap: () {
              Navigator.of(sheetContext).pop();
              ImportFlow.start(context);
            },
          ),
          SheetRow(
            icon: Icons.edit_outlined,
            title: 'Write it out',
            detail: 'Title, ingredients and steps. Components on the desktop.',
            onTap: () {
              Navigator.of(sheetContext).pop();
              _handEntry(context);
            },
          ),
        ],
      ),
    );
  }

  String _hostOf(String url) =>
      Uri.tryParse(url)?.host.replaceFirst('www.', '') ?? 'this link';

  void _handEntry(BuildContext context) {
    final app = context.read<AppState>();
    final recipe = Recipe(
      id: newId(),
      title: '',
      mealTypeId: (_mealTypeId ?? app.mealTypes.first.id),
      servings: 4,
    );
    recipe.components.add(RecipeComponent(
      id: newId(),
      recipeId: recipe.id,
      name: 'Ingredients',
      order: 0,
    ));
    app.saveRecipe(recipe);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MobileHandEntryPage(recipeId: recipe.id),
      ),
    );
  }
}

class _SuggestionsButton extends StatelessWidget {
  const _SuggestionsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: t.brContainer,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: t.accent.withValues(alpha: 0.12),
          borderRadius: t.brContainer,
          border: Border.fromBorderSide(BorderSide(color: t.accent)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_outlined, size: 17, color: t.accent),
            const SizedBox(width: 7),
            Text(
              'Suggestions',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 13,
                color: t.primaryButtonIsFilled ? t.accentText : t.tagAccentFg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The phone card: two up, the macros stacked under the title.
class _PhoneCard extends StatelessWidget {
  const _PhoneCard({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();
    final totals = app.macros.forRecipe(recipe);
    final per = totals.perServing;

    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MobileRecipePage(recipeId: recipe.id),
        ),
      ),
      borderRadius: t.brContainer,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: t.brContainer,
          boxShadow: t.shadowSm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 104,
              child: RecipePhoto(
                path: recipe.photoPath,
                placeholder: '${recipe.title} photo',
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(11, 10, 11, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        recipe.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 13.5,
                          height: 1.25,
                          color: t.text,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (recipe.totalMinutes != null)
                          '${recipe.totalMinutes} min',
                        '${totals.isComplete ? '' : '~'}'
                            '${per.calories.round()} cal',
                        '${per.protein.round()}g protein',
                      ].join(' · '),
                      // Two columns at 428px leaves the meta line short of
                      // room for time, calories and protein on one line.
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 11,
                        height: 1.35,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
