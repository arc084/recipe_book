import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets/primitives.dart';
import 'mobile_recipe.dart';
import 'mobile_widgets.dart';

/// Groceries on Android — the screen this app is most likely to be open on.
///
/// Same behaviours as the desktop: checked items dim in place and drop to the
/// bottom of their aisle, and Clear checked is the only thing that removes
/// them. Where the desktop drags a row to re-file it and double-clicks to
/// rename, the phone presses and holds for a sheet with both; the desktop's
/// sidebar — what the list was built from, what is running low — sits below
/// the aisles.
class MobileGroceriesPage extends StatefulWidget {
  const MobileGroceriesPage({super.key});

  @override
  State<MobileGroceriesPage> createState() => _MobileGroceriesPageState();
}

class _MobileGroceriesPageState extends State<MobileGroceriesPage> {
  final _add = TextEditingController();

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();
    final open = app.openGroceryCount;
    final done = app.library.groceries.length - open;
    final byRecipe = app.groceriesByRecipe();
    final runningLow = app.runningLow();
    final from = byRecipe.isEmpty
        ? ''
        : ' · from ${byRecipe.length} '
              '${byRecipe.length == 1 ? 'recipe' : 'recipes'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MobileHeader(title: 'Groceries', showSync: false),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$open to buy · $done in the cart$from',
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 12.5,
                    color: t.textMuted,
                  ),
                ),
              ),
              if (done > 0)
                AppButton(
                  'Clear checked',
                  fontSize: 12,
                  height: 32,
                  onPressed: () {
                    final n = app.clearChecked();
                    phoneToast(context, '$n cleared into the pantry');
                  },
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: AppTextField(
            controller: _add,
            hint: 'Add an item — “2 lemons”',
            icon: Icons.add,
            height: 46,
            fontSize: 14,
            onSubmitted: (v) {
              if (v.trim().isEmpty) return;
              final p = _parse(v.trim());
              app.addGrocery(p.name, quantity: p.quantity);
              _add.clear();
            },
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              for (final aisle in app.aisles) _aisle(context, app, aisle),
              Row(
                children: [
                  AppButton(
                    '＋ New category',
                    fontSize: 12.5,
                    height: 34,
                    onPressed: () => _newAisle(context, app),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Tap to check off · press and hold to rename or '
                      're-file',
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 11,
                        height: 1.4,
                        color: t.textFaint,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              _builtFrom(context, app, byRecipe),
              const SizedBox(height: 22),
              _runningLow(context, app, runningLow),
            ],
          ),
        ),
      ],
    );
  }

  ({String name, String quantity}) _parse(String input) {
    final m = RegExp(r'^([\d.,/]+\s*\w*)\s+(.+)$').firstMatch(input);
    if (m == null) return (name: input, quantity: '');
    final qty = m.group(1)!.trim();
    if (!RegExp(r'^\d').hasMatch(qty)) return (name: input, quantity: '');
    return (name: m.group(2)!.trim(), quantity: qty);
  }

  Widget _aisle(BuildContext context, AppState app, Aisle aisle) {
    final t = context.tokens;
    final items =
        app.library.groceries.where((g) => g.aisleId == aisle.id).toList()
          ..sort((a, b) {
            if (a.checked != b.checked) return a.checked ? 1 : -1;
            return 0;
          });
    if (items.isEmpty) return const SizedBox.shrink();

    final open = items.where((i) => !i.checked).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Row(
              children: [
                SectionLabel(aisle.name),
                const SizedBox(width: 8),
                Text(
                  '$open of ${items.length}',
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 11,
                    color: t.textFaint,
                  ),
                ),
              ],
            ),
          ),
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
  }

  Widget _row(
    BuildContext context,
    AppState app,
    GroceryItem item,
    bool divided,
  ) {
    final t = context.tokens;
    return Opacity(
      opacity: item.checked ? 0.55 : 1,
      child: Container(
        decoration: BoxDecoration(
          border: divided ? Border(top: BorderSide(color: t.divider)) : null,
        ),
        child: InkWell(
          // The whole row is the target — a wrong tap costs nothing, since
          // checking off only dims.
          onTap: () => app.toggleGrocery(item.id),
          onLongPress: () => _itemMenu(context, app, item),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: item.checked ? t.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(
                      t.radiusControl > 100 ? 999 : 5,
                    ),
                    border: Border.fromBorderSide(
                      BorderSide(
                        color: item.checked ? t.accent : t.divider,
                        width: 1.5,
                      ),
                    ),
                  ),
                  child: item.checked
                      ? Icon(Icons.check, size: 13, color: t.ground)
                      : null,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 14.5,
                          color: item.checked ? t.textFaint : t.text,
                          decoration: item.checked
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: t.textFaint,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (item.quantity.isNotEmpty) item.quantity,
                          // Every item says where it came from.
                          ...item.sources,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 11.5,
                          color: t.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openRecipe(BuildContext context, String recipeId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MobileRecipePage(recipeId: recipeId)),
    );
  }

  // ── Sheets ──────────────────────────────────────────────────────────────

  Future<void> _itemMenu(
    BuildContext context,
    AppState app,
    GroceryItem item,
  ) async {
    final aisle = app.aisles.where((a) => a.id == item.aisleId).firstOrNull;
    final recipes = [
      for (final source in item.sources)
        ?app.library.recipes.where((r) => r.title == source).firstOrNull,
    ];

    final choice = await showPhoneSheet<String>(
      context,
      title: item.name,
      subtitle: [
        if (item.quantity.isNotEmpty) item.quantity,
        if (aisle != null) 'in ${aisle.name}',
        ...item.sources,
      ].join(' · '),
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          SheetRow(
            icon: Icons.edit_outlined,
            title: 'Rename…',
            onTap: () => Navigator.of(sheet).pop('rename'),
          ),
          SheetRow(
            icon: Icons.drive_file_move_outline,
            title: 'Move to another category…',
            detail: aisle == null ? null : 'Now in ${aisle.name}',
            onTap: () => Navigator.of(sheet).pop('move'),
          ),
          // Every item says where it came from; on the phone that is also the
          // way back to the recipe.
          for (final r in recipes)
            SheetRow(
              icon: Icons.restaurant,
              title: 'Open ${r.title}',
              onTap: () => Navigator.of(sheet).pop('recipe:${r.id}'),
            ),
        ],
      ),
    );
    if (choice == null || !context.mounted) return;

    if (choice == 'rename') {
      final name = await promptInPhoneSheet(
        context,
        title: 'Rename',
        initial: item.name,
        confirmLabel: 'Save',
      );
      if (name == null || name.trim().isEmpty) return;
      app.renameGrocery(item.id, name);
    } else if (choice == 'move') {
      await _moveSheet(context, app, item);
    } else if (choice.startsWith('recipe:')) {
      _openRecipe(context, choice.substring('recipe:'.length));
    }
  }

  Future<void> _moveSheet(
    BuildContext context,
    AppState app,
    GroceryItem item,
  ) async {
    final picked = await showPhoneSheet<String>(
      context,
      title: 'Move ${item.name}',
      builder: (sheet) => ListView(
        shrinkWrap: true,
        children: [
          for (final aisle in app.aisles)
            SheetRow(
              icon: aisle.id == item.aisleId
                  ? Icons.check
                  : Icons.circle_outlined,
              title: aisle.name,
              accent: aisle.id == item.aisleId,
              onTap: () => Navigator.of(sheet).pop(aisle.id),
            ),
          SheetRow(
            icon: Icons.add,
            title: 'New category…',
            accent: true,
            onTap: () => Navigator.of(sheet).pop('__new__'),
          ),
        ],
      ),
    );
    if (picked == null || !context.mounted) return;

    if (picked == '__new__') {
      final aisle = await _newAisle(context, app, announce: false);
      if (aisle == null) return;
      app.moveGrocery(item.id, aisle.id);
      if (context.mounted) phoneToast(context, 'Moved to ${aisle.name}');
      return;
    }
    app.moveGrocery(item.id, picked);
  }

  Future<Aisle?> _newAisle(
    BuildContext context,
    AppState app, {
    bool announce = true,
  }) async {
    final name = await promptInPhoneSheet(
      context,
      title: 'New category',
      hint: 'Bakery',
    );
    if (name == null || name.trim().isEmpty) return null;
    final aisle = app.addAisle(name.trim());
    // An empty category is not drawn on the phone's list, so say where it
    // went rather than appear to have done nothing.
    if (announce && context.mounted) {
      phoneToast(
        context,
        '${aisle.name} added — press and hold an item to move it in',
      );
    }
    return aisle;
  }

  // ── Built from / running low ────────────────────────────────────────────

  Widget _builtFrom(
    BuildContext context,
    AppState app,
    Map<String, int> byRecipe,
  ) {
    final t = context.tokens;
    final entries = byRecipe.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel('Built from'),
        const SizedBox(height: 8),
        if (entries.isEmpty)
          Text(
            'Nothing on the list came from a recipe yet.',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 12.5,
              color: t.textMuted,
            ),
          )
        else
          Panel(
            clip: true,
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++)
                  _builtFromRow(
                    context,
                    app,
                    entries[i].key,
                    entries[i].value,
                    i > 0,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _builtFromRow(
    BuildContext context,
    AppState app,
    String title,
    int count,
    bool divided,
  ) {
    final t = context.tokens;
    final recipe = app.library.recipes
        .where((r) => r.title == title)
        .firstOrNull;

    return Container(
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: t.divider)) : null,
      ),
      child: InkWell(
        onTap: recipe == null ? null : () => _openRecipe(context, recipe.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.restaurant, size: 16, color: t.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 14,
                    color: t.text,
                  ),
                ),
              ),
              Text(
                '$count ${count == 1 ? 'item' : 'items'}',
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 11.5,
                  color: t.textMuted,
                ),
              ),
              if (recipe != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right, size: 18, color: t.textFaint),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _runningLow(
    BuildContext context,
    AppState app,
    List<PantryItem> items,
  ) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel('Running low'),
        const SizedBox(height: 4),
        Text(
          'You have used these across several recipes this week.',
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 11.5,
            height: 1.4,
            color: t.textFaint,
          ),
        ),
        const SizedBox(height: 10),
        if (items.isEmpty)
          Text(
            'Nothing yet.',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 12.5,
              color: t.textMuted,
            ),
          )
        else
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final item in items)
                TouchChip(
                  label: '＋ ${item.name}',
                  onTap: () {
                    app.addGrocery(
                      item.name,
                      source: 'Running low',
                      pantryItemId: item.id,
                    );
                    phoneToast(context, '${item.name} added');
                  },
                ),
            ],
          ),
      ],
    );
  }
}
