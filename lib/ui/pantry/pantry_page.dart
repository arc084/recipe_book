import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../../theme/tokens.dart';
import '../library/library_page.dart' show promptForText;
import '../widgets/primitives.dart';
import 'remove_item.dart';
import 'edit_macros.dart';

/// What the user has, grouped by where it is kept.
///
/// Chips drag between Fridge, Pantry and Freezer; clicking one opens it. This
/// is the only tab where macros are written, and it is where every other
/// screen's numbers come from.
class PantryPage extends StatefulWidget {
  const PantryPage({super.key});

  @override
  State<PantryPage> createState() => _PantryPageState();
}

class _PantryPageState extends State<PantryPage> {
  final _add = TextEditingController();

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final nav = context.watch<NavController>();

    final selected = nav.pantryItemId == null
        ? null
        : app.pantryItem(nav.pantryItemId!);

    return Row(
      children: [
        _chipPanel(context, app),
        Expanded(
          child: selected == null
              ? _empty(context, app)
              : _detail(context, app, selected),
        ),
      ],
    );
  }

  // ── Chip panel ──────────────────────────────────────────────────────────

  Widget _chipPanel(BuildContext context, AppState app) {
    final t = context.tokens;
    final needing = app.itemsNeedingMacros;

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: t.chrome,
        border: Border(right: BorderSide(color: t.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'My pantry',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    Text(
                      '${app.pantry.items.length} items',
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 11,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _add,
                  hint: 'Add an ingredient…',
                  icon: Icons.add,
                  fontSize: 12.5,
                  onSubmitted: (v) {
                    if (v.trim().isEmpty) return;
                    // Anything added lands in Pantry until it is moved.
                    final item = app.addPantryItem(v.trim());
                    _add.clear();
                    context.read<NavController>().openPantryItem(item.id);
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
                  child: Text(
                    'Click a chip to open it · drag to move it between '
                    'groups · right-click for stock and removal. A ◦ means no '
                    'macros yet; struck through means run out.',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 10.5,
                      height: 1.45,
                      color: t.textFaint,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
              children: [
                for (final group in PantryGroup.values)
                  _group(context, app, group),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 13, 18, 16),
            child: Column(
              children: [
                Container(height: 1, color: t.divider),
                const SizedBox(height: 11),
                if (needing.isNotEmpty) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: t.accent.withValues(alpha: 0.10),
                      borderRadius: t.brContainer,
                      border: Border.fromBorderSide(
                        BorderSide(color: t.accent),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${needing.length} '
                                '${needing.length == 1 ? 'item needs' : 'items need'}'
                                ' macros',
                                style: TextStyle(
                                  fontFamily: t.bodyFamily,
                                  fontSize: 12,
                                  color: t.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                needing.take(3).map((i) => i.name).join(', '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: t.bodyFamily,
                                  fontSize: 10.5,
                                  color: t.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        AppButton(
                          'Review',
                          fontSize: 11,
                          height: 26,
                          onPressed: () => context
                              .read<NavController>()
                              .openPantryItem(needing.first.id),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 11),
                ],
                Row(
                  children: [
                    _Toggle(
                      value: app.pantry.assumeStaples,
                      onChanged: app.setAssumeStaples,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Assume staples on hand',
                            style: TextStyle(
                              fontFamily: t.bodyFamily,
                              fontSize: 11.5,
                              color: t.textSecondary,
                            ),
                          ),
                          Text(
                            app.pantry.items
                                .where((i) => i.isStaple)
                                .map((i) => i.name)
                                .join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: t.bodyFamily,
                              fontSize: 11,
                              color: t.textFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _group(BuildContext context, AppState app, PantryGroup group) {
    final t = context.tokens;
    final items = app.pantry.items.where((i) => i.group == group).toList();

    return DragTarget<String>(
      onAcceptWithDetails: (d) => app.movePantryItem(d.data, group),
      builder: (context, candidate, _) {
        final active = candidate.isNotEmpty;
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: t.brContainer,
            color: active ? t.accent.withValues(alpha: 0.08) : null,
            border: active
                ? Border.fromBorderSide(BorderSide(color: t.accent))
                : Border.fromBorderSide(
                    const BorderSide(color: Colors.transparent),
                  ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 9, left: 2),
                child: Row(
                  children: [
                    SectionLabel(group.label, color: t.textMuted, size: 10.5),
                    const SizedBox(width: 6),
                    Text(
                      // The count is what is on hand, with the run-out ones
                      // called out rather than folded into the same number.
                      items.where((i) => i.inStock).length.toString(),
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 10.5,
                        color: t.textFaint,
                      ),
                    ),
                    if (items.any((i) => !i.inStock)) ...[
                      const SizedBox(width: 6),
                      Text(
                        '· ${items.where((i) => !i.inStock).length} run out',
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 10.5,
                          color: t.accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final item in items) _chip(context, item)],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(BuildContext context, PantryItem item) {
    final t = context.tokens;
    final nav = context.read<NavController>();
    final selected = context.watch<NavController>().pantryItemId == item.id;

    final chip = Tag(
      item.name,
      // Run out reads as struck through and faded, so a glance down the
      // groups says what is actually on hand without having to open anything.
      struckThrough: !item.inStock,
      faded: !item.inStock,
      style: !item.inStock
          ? TagStyle.outline
          : item.brandLabel != null
              ? TagStyle.accent
              : selected
                  ? TagStyle.outline
                  : TagStyle.neutral,
      trailing: item.hasMacros
          ? (item.brandLabel != null
              ? Text(
                  _brandShort(item.brandLabel!),
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 9.5,
                    color: t.tagAccentFg.withValues(alpha: 0.7),
                  ),
                )
              : null)
          // A ◦ on a chip means no macros yet.
          : Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(BorderSide(color: t.accent)),
              ),
            ),
      onTap: () => nav.openPantryItem(item.id),
    );

    return Draggable<String>(
      data: item.id,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.9, child: chip),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      // Right-click is the desktop way at both of these without leaving the
      // group you are looking at.
      child: GestureDetector(
        onSecondaryTapDown: (d) =>
            _chipMenu(context, item, d.globalPosition),
        child: chip,
      ),
    );
  }

  Future<void> _chipMenu(
    BuildContext context,
    PantryItem item,
    Offset at,
  ) async {
    final t = context.tokens;
    final app = context.read<AppState>();
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;

    final choice = await showMenu<String>(
      context: context,
      color: t.surface,
      shape: RoundedRectangleBorder(borderRadius: t.brContainer),
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'stock',
          child: Text(
            item.inStock ? 'Mark as run out' : 'Mark as in stock',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 13,
              color: t.text,
            ),
          ),
        ),
        PopupMenuItem(
          value: 'groceries',
          child: Text(
            'Add to groceries',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 13,
              color: t.text,
            ),
          ),
        ),
        PopupMenuItem(
          value: 'remove',
          child: Text(
            'Remove from pantry…',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 13,
              color: t.accentText,
            ),
          ),
        ),
      ],
    );
    if (choice == null || !context.mounted) return;

    switch (choice) {
      case 'stock':
        app.setInStock(item.id, !item.inStock);
      case 'groceries':
        app.addGrocery(item.name, source: 'Pantry', pantryItemId: item.id);
      case 'remove':
        await confirmRemovePantryItem(context, item);
    }
  }

  String _brandShort(String brand) {
    final first = brand.split(' ').first;
    return first.length > 6 ? "${first.substring(0, 5)}'s" : first;
  }

  // ── Detail ──────────────────────────────────────────────────────────────

  Widget _empty(BuildContext context, AppState app) {
    final t = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.kitchen_outlined, size: 32, color: t.textFaint),
            const SizedBox(height: 14),
            Text(
              'Pick an ingredient to see its macros,\nits other names, and '
              'every recipe using it.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 13,
                height: 1.6,
                color: t.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detail(BuildContext context, AppState app, PantryItem item) {
    final t = context.tokens;
    final usedIn = app.usedIn(item.id);
    final branded = app.brandedMentions(item.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
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
                          'Pantry ▸ ${item.group.label} group',
                          style: TextStyle(
                            fontFamily: t.bodyFamily,
                            fontSize: 11,
                            color: t.textFaint,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                item.name,
                                style:
                                    Theme.of(context).textTheme.headlineSmall,
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Sage carries "in stock" on Organic; Nocturne is
                            // a mono palette and resolves accent2 to the
                            // accent, so the same token works in both.
                            Tag(
                              item.inStock ? 'In stock' : 'Run out',
                              style: item.inStock
                                  ? TagStyle.accent2
                                  : TagStyle.outline,
                            ),
                          ],
                        ),
                        if (item.brandLabel != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            [
                              item.brandLabel!,
                              if (item.packAmount != null)
                                '${item.packAmount!.round()} '
                                    '${item.packUnit ?? 'g'} pack',
                            ].join(' · '),
                            style: TextStyle(
                              fontFamily: t.bodyFamily,
                              fontSize: 12.5,
                              color: t.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  // Whether it is on hand is the thing that changes most
                  // often, so it is a single click here and reversible.
                  AppButton(
                    item.inStock ? 'Mark as run out' : 'Back in stock',
                    onPressed: () => app.setInStock(item.id, !item.inStock),
                  ),
                  const SizedBox(width: 8),
                  AppIconButton(
                    icon: Icons.delete_outline,
                    tooltip: 'Remove from pantry',
                    onPressed: () => confirmRemovePantryItem(context, item),
                  ),
                  const SizedBox(width: 8),
                  // Add to groceries is on the item, not just the list.
                  AppButton(
                    'Add to groceries',
                    onPressed: () {
                      app.addGrocery(
                        item.name,
                        source: 'Pantry',
                        pantryItemId: item.id,
                      );
                      ScaffoldMessenger.of(context)
                        ..clearSnackBars()
                        ..showSnackBar(SnackBar(
                          content: Text('${item.name} added to groceries'),
                          backgroundColor: t.surface,
                          behavior: SnackBarBehavior.floating,
                          width: 320,
                        ));
                    },
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    'Edit macros',
                    kind: ButtonKind.primary,
                    onPressed: () => EditMacrosDialog.open(context, item),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(height: 1, color: t.divider),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 22),
            children: [
              _macrosSection(context, item),
              const SizedBox(height: 18),
              _aliasSection(context, app, item),
              const SizedBox(height: 18),
              _usedInSection(context, app, item, usedIn, branded),
            ],
          ),
        ),
      ],
    );
  }

  Widget _macrosSection(BuildContext context, PantryItem item) {
    final t = context.tokens;

    if (!item.hasMacros) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel('Macros'),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.accent.withValues(alpha: 0.08),
              borderRadius: t.brContainer,
              border: Border.fromBorderSide(BorderSide(color: t.accent)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: t.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'No macros yet. Every recipe using ${item.name} flags '
                    'this line rather than counting it as zero.',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 12.5,
                      height: 1.5,
                      color: t.text,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                AppButton(
                  'Add them',
                  kind: ButtonKind.primary,
                  onPressed: () => EditMacrosDialog.open(context, item),
                ),
              ],
            ),
          ),
        ],
      );
    }

    final serving = item.servingAmount == null
        ? null
        : '${item.servingAmount!.round()} ${item.servingUnit}'
            '${item.altAmount == null ? '' : ' (${item.altAmount!.round()} ${item.altUnit})'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SectionLabel('Macros'),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                [
                  item.basis.label,
                  if (serving != null) 'serving $serving',
                  if (item.brandLabel != null)
                    'from the product label'
                  else
                    'entered by hand',
                ].join(' · '),
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
        const SizedBox(height: 10),
        StatStrip(
          valueSize: 19,
          labelSize: 10.5,
          padding: 14,
          cells: [
            (value: '${item.calories!.round()}', label: 'calories'),
            (value: '${item.protein?.round() ?? 0} g', label: 'protein'),
            (value: '${item.fat?.round() ?? 0} g', label: 'fat'),
            (value: '${item.carbs?.round() ?? 0} g', label: 'carbs'),
            (value: '${item.sugar?.round() ?? 0} g', label: 'sugar'),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 9, 2, 0),
          child: Row(
            children: [
              Icon(
                item.isEstimated ? Icons.help_outline : Icons.check,
                size: 14,
                color: t.accent,
              ),
              const SizedBox(width: 8),
              Text(
                [
                  if (item.brandLabel != null)
                    'Matched to the brand you buy'
                  else
                    'Entered by hand',
                  if (item.enteredOn != null)
                    'entered ${DateFormat('d MMM').format(item.enteredOn!)}',
                  item.isEstimated
                      ? 'estimated — every recipe carrying these says so'
                      : 'not estimated',
                ].join(' · '),
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 11,
                  color: t.textMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _aliasSection(BuildContext context, AppState app, PantryItem item) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SectionLabel('Also known as'),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'an imported recipe naming any of these draws from this item',
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
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final alias in item.aliases)
              Tag(
                alias,
                trailing: GestureDetector(
                  onTap: () => app.removeAlias(item.id, alias),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Icon(Icons.close, size: 11, color: t.textMuted),
                  ),
                ),
              ),
            Tag(
              '＋ add',
              style: TagStyle.outline,
              onTap: () async {
                final name = await promptForText(
                  context,
                  title: 'Another name for ${item.name}',
                  hint: 'choc chips',
                );
                if (name == null || name.trim().isEmpty || !context.mounted) {
                  return;
                }
                app.addAlias(item.id, name.trim());
              },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 9, 2, 0),
          child: Text(
            'A recipe that names a brand is left alone and keeps its own '
            'macros.',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 11,
              height: 1.5,
              color: t.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _usedInSection(
    BuildContext context,
    AppState app,
    PantryItem item,
    List<({Recipe recipe, Ingredient line, double calories})> usedIn,
    List<({Recipe recipe, Ingredient line})> branded,
  ) {
    final t = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SectionLabel('Used in'),
            const SizedBox(width: 9),
            Text(
              '${usedIn.length} linked'
              '${branded.isEmpty ? '' : ' · plus ${branded.length} that names a brand'}',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11,
                color: t.textFaint,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (usedIn.isEmpty)
          Text(
            'Nothing draws on this yet.',
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
                Container(
                  height: 34,
                  color: t.text.withValues(alpha: 0.03),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  child: Row(
                    children: [
                      Expanded(child: SectionLabel('Recipe', size: 10.5)),
                      SizedBox(
                        width: 190,
                        child: SectionLabel('Called for as', size: 10.5),
                      ),
                      SizedBox(
                        width: 70,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SectionLabel('Amount', size: 10.5),
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: SectionLabel('Calories', size: 10.5),
                        ),
                      ),
                    ],
                  ),
                ),
                for (var i = 0; i < usedIn.length; i++)
                  _usedInRow(context, usedIn[i], i > 0),
              ],
            ),
          ),
      ],
    );
  }

  Widget _usedInRow(
    BuildContext context,
    ({Recipe recipe, Ingredient line, double calories}) row,
    bool divided,
  ) {
    final t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: t.divider)) : null,
      ),
      child: HoverRow(
        onTap: () =>
            context.read<NavController>().openRecipe(row.recipe.id),
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.recipe.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 13,
                      color: t.text,
                    ),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: Text(
                    'recipe says “${row.line.name}”',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 11.5,
                      color: t.textMuted,
                    ),
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: Text(
                    row.line.quantity == null
                        ? row.line.unit
                        : '${row.line.quantity!.round()} ${row.line.unit}'
                            .trim(),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 12.5,
                      color: t.textSecondary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    row.calories.round().toString(),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 12.5,
                      color: t.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 30,
          height: 17,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? t.accent : t.toggleTrackOff,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Align(
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.toggleKnob,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
