import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../../theme/tokens.dart';
import '../widgets/primitives.dart';

/// The list you shop from.
///
/// Checked items dim in place and drop to the bottom of their aisle rather
/// than disappearing — Clear checked is the only thing that removes them, and
/// it is one action for the whole list.
class GroceriesPage extends StatefulWidget {
  const GroceriesPage({super.key});

  @override
  State<GroceriesPage> createState() => _GroceriesPageState();
}

class _GroceriesPageState extends State<GroceriesPage> {
  final _add = TextEditingController();
  final _newAisle = TextEditingController();
  String? _editing;

  @override
  void dispose() {
    _add.dispose();
    _newAisle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Row(
      children: [
        Expanded(child: _main(context, app)),
        _sidebar(context, app),
      ],
    );
  }

  // ── List ────────────────────────────────────────────────────────────────

  Widget _main(BuildContext context, AppState app) {
    final t = context.tokens;
    final open = app.openGroceryCount;
    final done = app.library.groceries.length - open;
    final recipeCount = <String>{
      for (final g in app.library.groceries)
        ...g.sources.where((s) => s != 'Added by hand'),
    }.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Groceries',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$open to buy · $done in the cart · from '
                        '$recipeCount ${recipeCount == 1 ? 'recipe' : 'recipes'}',
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 12,
                          color: t.textMuted,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  AppButton(
                    'Clear checked → pantry',
                    fontSize: 12,
                    onPressed: done == 0
                        ? null
                        : () {
                            final n = app.clearChecked();
                            ScaffoldMessenger.of(context)
                              ..clearSnackBars()
                              ..showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '$n cleared and put in the pantry',
                                  ),
                                  backgroundColor: t.surface,
                                  behavior: SnackBarBehavior.floating,
                                  width: 340,
                                ),
                              );
                          },
                  ),
                ],
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _add,
                hint: 'Add an item — “2 lemons”',
                icon: Icons.add,
                fontSize: 12.5,
                onSubmitted: (v) {
                  if (v.trim().isEmpty) return;
                  final parsed = _parse(v.trim());
                  app.addGrocery(parsed.name, quantity: parsed.quantity);
                  _add.clear();
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 12),
            children: [
              for (final aisle in app.aisles) _aisle(context, app, aisle),
              const SizedBox(height: 4),
              Row(
                children: [
                  SizedBox(
                    width: 210,
                    child: AppTextField(
                      controller: _newAisle,
                      hint: '＋ New category — “Bakery”',
                      height: 28,
                      fontSize: 11.5,
                      onSubmitted: (v) {
                        if (v.trim().isEmpty) return;
                        app.addAisle(v.trim());
                        _newAisle.clear();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Tick the box to check off · drag a row to re-file it · '
                      'double-click a name to rename',
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 10.5,
                        color: t.textFaint,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// "2 lemons" → quantity 2, name lemons.
  ({String name, String quantity}) _parse(String input) {
    final m = RegExp(r'^([\d.,/]+\s*\w*)\s+(.+)$').firstMatch(input);
    if (m == null) return (name: input, quantity: '');
    final qty = m.group(1)!.trim();
    // Only treat the head as a quantity if it actually starts with a digit.
    if (!RegExp(r'^\d').hasMatch(qty)) return (name: input, quantity: '');
    return (name: m.group(2)!.trim(), quantity: qty);
  }

  Widget _aisle(BuildContext context, AppState app, Aisle aisle) {
    final t = context.tokens;
    final items =
        app.library.groceries.where((g) => g.aisleId == aisle.id).toList()
          // Checked items drop to the bottom of their aisle.
          ..sort((a, b) {
            if (a.checked != b.checked) return a.checked ? 1 : -1;
            return 0;
          });

    final open = items.where((i) => !i.checked).length;

    return DragTarget<String>(
      onAcceptWithDetails: (d) => app.moveGrocery(d.data, aisle.id),
      builder: (context, candidate, _) {
        final active = candidate.isNotEmpty;
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: t.brContainer,
            color: active ? t.accent.withValues(alpha: 0.07) : null,
            border: Border.fromBorderSide(
              BorderSide(color: active ? t.accent : Colors.transparent),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SectionLabel(aisle.name),
                    const SizedBox(width: 8),
                    Text(
                      items.isEmpty
                          ? 'empty'
                          : '$open of ${items.length} to buy',
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 11,
                        color: t.textFaint,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Container(height: 1, color: t.divider)),
                  ],
                ),
              ),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
                  child: Text(
                    'drag an item here to re-file it',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      color: t.textFaint,
                    ),
                  ),
                )
              else
                Panel(
                  clip: true,
                  child: Column(
                    children: [
                      for (var i = 0; i < items.length; i++)
                        _row(context, app, items[i], i > 0),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(
    BuildContext context,
    AppState app,
    GroceryItem item,
    bool divided,
  ) {
    final t = context.tokens;

    final row = Container(
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: t.divider)) : null,
      ),
      child: HoverRow(
        child: SizedBox(
          height: 38,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              children: [
                _Checkbox(
                  checked: item.checked,
                  onTap: () => app.toggleGrocery(item.id),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: _editing == item.id
                      ? _renameField(context, app, item)
                      : GestureDetector(
                          onDoubleTap: () => setState(() => _editing = item.id),
                          child: Text(
                            item.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: t.bodyFamily,
                              fontSize: 13,
                              // Checked items dim in place.
                              color: item.checked ? t.textFaint : t.text,
                              decoration: item.checked
                                  ? TextDecoration.lineThrough
                                  : null,
                              decorationColor: t.textFaint,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                if (item.quantity.isNotEmpty)
                  Text(
                    item.quantity,
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 11.5,
                      color: item.checked ? t.textFaint : t.textMuted,
                    ),
                  ),
                const SizedBox(width: 12),
                // Every item says where it came from.
                Tag(
                  item.sources.length > 1
                      ? '${item.sources.first} +${item.sources.length - 1}'
                      : item.sources.firstOrNull ?? 'Added by hand',
                  dense: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Opacity(
      opacity: item.checked ? 0.55 : 1,
      child: Draggable<String>(
        data: item.id,
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 320,
            child: Panel(
              elevation: PanelElevation.lg,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              child: Text(
                item.name,
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 13,
                  color: t.text,
                ),
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: row),
        child: row,
      ),
    );
  }

  Widget _renameField(BuildContext context, AppState app, GroceryItem item) {
    final controller = TextEditingController(text: item.name);
    return AppTextField(
      controller: controller,
      height: 26,
      fontSize: 13,
      autofocus: true,
      onSubmitted: (v) {
        app.renameGrocery(item.id, v);
        setState(() => _editing = null);
      },
    );
  }

  // ── Sidebar ─────────────────────────────────────────────────────────────

  Widget _sidebar(BuildContext context, AppState app) {
    final t = context.tokens;

    // Which recipes the list was built from, and how many lines each put on it.
    final byRecipe = <String, int>{};
    for (final g in app.library.groceries) {
      for (final s in g.sources) {
        if (s == 'Added by hand') continue;
        byRecipe[s] = (byRecipe[s] ?? 0) + 1;
      }
    }

    // Things used across several of this week's recipes that the user has but
    // is likely to be getting through.
    final runningLow = _runningLow(app);

    return Container(
      width: 282,
      decoration: BoxDecoration(
        color: t.chrome,
        border: Border(left: BorderSide(color: t.divider)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Built from', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          if (byRecipe.isEmpty)
            Text(
              'Nothing on the list came from a recipe yet.',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11.5,
                color: t.textMuted,
              ),
            ),
          for (final entry in byRecipe.entries)
            _builtFromRow(context, app, entry.key, entry.value),
          const SizedBox(height: 18),
          Container(height: 1, color: t.divider),
          const SizedBox(height: 18),
          SectionLabel('Running low'),
          const SizedBox(height: 4),
          Text(
            'You have used these across several recipes this week.',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 11,
              height: 1.4,
              color: t.textFaint,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final item in runningLow)
                Tag(
                  item.name,
                  style: TagStyle.outline,
                  trailing: Icon(Icons.add, size: 11, color: t.accent),
                  onTap: () => app.addGrocery(
                    item.name,
                    source: 'Running low',
                    pantryItemId: item.id,
                  ),
                ),
              if (runningLow.isEmpty)
                Text(
                  'Nothing yet.',
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 11.5,
                    color: t.textMuted,
                  ),
                ),
            ],
          ),
          const Spacer(),
          Container(height: 1, color: t.divider),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.phone_iphone, size: 15, color: t.accent),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  'This list is on every paired device.',
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 11.5,
                    height: 1.4,
                    color: t.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Pantry items three or more of this week's planned recipes draw on, and
  /// which are not already on the list.
  List<PantryItem> _runningLow(AppState app) {
    final today = DateTime.now();
    final monday = app
        .dayOnly(today)
        .subtract(Duration(days: today.weekday - 1));

    final counts = <String, int>{};
    for (var i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      for (final slot in MealSlot.values) {
        final entry = app.planAt(day, slot);
        if (entry == null) continue;
        final recipe = app.recipe(entry.recipeId);
        if (recipe == null) continue;
        for (final line in recipe.ingredients) {
          if (line.pantryItemId == null) continue;
          counts[line.pantryItemId!] = (counts[line.pantryItemId!] ?? 0) + 1;
        }
      }
    }

    final onList = {
      for (final g in app.library.groceries)
        if (!g.checked) g.name.trim().toLowerCase(),
    };

    return counts.entries
        .where((e) => e.value >= 3)
        .map((e) => app.pantryItem(e.key))
        .whereType<PantryItem>()
        .where((p) => !onList.contains(p.name.trim().toLowerCase()))
        .take(6)
        .toList();
  }

  Widget _builtFromRow(
    BuildContext context,
    AppState app,
    String recipeTitle,
    int count,
  ) {
    final t = context.tokens;
    final recipe = app.library.recipes
        .where((r) => r.title == recipeTitle)
        .firstOrNull;

    return HoverRow(
      borderRadius: t.brContainer,
      onTap: recipe == null
          ? null
          : () => context.read<NavController>().openRecipe(recipe.id),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  t.accent.withValues(alpha: 0.16),
                  t.surface,
                ),
                borderRadius: t.brSmall,
              ),
              child: Icon(Icons.restaurant, size: 15, color: t.textMuted),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipeTitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 12.5,
                      color: t.text,
                    ),
                  ),
                  Text(
                    '$count ${count == 1 ? 'item' : 'items'}',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 10.5,
                      color: t.textMuted,
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
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.checked, required this.onTap});

  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 17,
          height: 17,
          decoration: BoxDecoration(
            color: checked ? t.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(
              t.radiusControl > 100 ? 999 : 4,
            ),
            border: Border.fromBorderSide(
              BorderSide(color: checked ? t.accent : t.divider, width: 1.5),
            ),
          ),
          child: checked ? Icon(Icons.check, size: 11, color: t.ground) : null,
        ),
      ),
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
