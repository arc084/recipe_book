import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../pantry/edit_macros.dart';
import '../pantry/remove_item.dart';
import '../widgets/primitives.dart';
import 'mobile_widgets.dart';

/// The Pantry on Android.
///
/// The same three groups in the same order, chips draggable between them, and
/// Edit macros is here too — it is the one writing screen on both platforms,
/// because it is done with the packet in hand.
///
/// The box at the top searches; ＋ adds what is typed. A pantry of forty is
/// past the point where every ingredient is on screen, so typing a name most
/// often means "where is it", and an add box answered that by making a second
/// row for something already there.
class MobilePantryPage extends StatefulWidget {
  const MobilePantryPage({super.key});

  @override
  State<MobilePantryPage> createState() => _MobilePantryPageState();
}

class _MobilePantryPageState extends State<MobilePantryPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Adds what is typed, or opens the item that already answers to it.
  void _add(BuildContext context) {
    final name = _search.text.trim();
    if (name.isEmpty) return;
    final app = context.read<AppState>();
    final existing = app.pantry.items
        .where((i) => i.matchesName(name))
        .firstOrNull;

    final item = app.addPantryItem(name);
    _search.clear();
    setState(() => _query = '');
    if (existing != null) {
      phoneToast(context, '${item.name} is already in your pantry');
    }
    _openItem(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();
    final needing = app.itemsNeedingMacros;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MobileHeader(title: 'Pantry', showSync: false),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: _search,
                  hint: 'Search the pantry…',
                  icon: Icons.search,
                  height: 46,
                  fontSize: 14,
                  onChanged: (v) => setState(() => _query = v.trim()),
                  onSubmitted: (_) => _add(context),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 52,
                child: AppButton(
                  '＋',
                  kind: ButtonKind.primary,
                  height: 46,
                  fontSize: 18,
                  onPressed: _query.isEmpty ? null : () => _add(context),
                ),
              ),
            ],
          ),
        ),
        if (needing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.accent.withValues(alpha: 0.10),
                borderRadius: t.brContainer,
                border: Border.fromBorderSide(BorderSide(color: t.accent)),
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
                            fontSize: 13,
                            color: t.text,
                          ),
                        ),
                        Text(
                          needing.take(3).map((i) => i.name).join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: t.bodyFamily,
                            fontSize: 11,
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AppButton(
                    'Review',
                    fontSize: 12,
                    height: 30,
                    onPressed: () => _openItem(context, needing.first),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              for (final group in PantryGroup.values)
                _group(context, app, group),
              if (_query.isNotEmpty && _matches(app).isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18, left: 2),
                  child: Text(
                    'Nothing here called “$_query”. ＋ adds it.',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 13,
                      color: t.textMuted,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Toggle(
                    value: app.pantry.assumeStaples,
                    onChanged: app.setAssumeStaples,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Assume staples on hand',
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 13,
                        color: t.textSecondary,
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

  /// Everything the search box currently matches, by name or by any of an
  /// item's other known names.
  List<PantryItem> _matches(AppState app) => _query.isEmpty
      ? app.pantry.items
      : app.pantry.items
            .where(
              (i) => i.allNames.any(
                (n) => n.toLowerCase().contains(_query.toLowerCase()),
              ),
            )
            .toList();

  Widget _group(BuildContext context, AppState app, PantryGroup group) {
    final t = context.tokens;
    final items = _matches(app).where((i) => i.group == group).toList();
    // A group with nothing matching is noise while searching, but its own
    // heading is the drop target the rest of the time.
    if (_query.isNotEmpty && items.isEmpty) return const SizedBox.shrink();

    return DragTarget<String>(
      onAcceptWithDetails: (d) => app.movePantryItem(d.data, group),
      builder: (context, candidate, _) {
        final active = candidate.isNotEmpty;
        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            borderRadius: t.brContainer,
            color: active ? t.accent.withValues(alpha: 0.08) : null,
            border: Border.fromBorderSide(
              BorderSide(color: active ? t.accent : Colors.transparent),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10, left: 2),
                child: Row(
                  children: [
                    SectionLabel(group.label, color: t.textMuted, size: 11),
                    const SizedBox(width: 7),
                    Text(
                      '${items.length}',
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 11,
                        color: t.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 7,
                runSpacing: 7,
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
    final fg = !item.inStock
        ? t.accent
        : item.brandLabel != null
        ? t.tagAccentFg
        : t.tagNeutralFg;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      decoration: BoxDecoration(
        color: item.inStock
            ? (item.brandLabel != null ? t.tagAccentBg : t.tagNeutralBg)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: item.inStock
            ? null
            : Border.fromBorderSide(BorderSide(color: t.accent)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.name,
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 13,
              // Run out reads as struck through here too.
              color: item.inStock ? fg : fg.withValues(alpha: 0.6),
              decoration: item.inStock ? null : TextDecoration.lineThrough,
              decorationColor: fg,
            ),
          ),
          if (!item.hasMacros) ...[
            const SizedBox(width: 7),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(BorderSide(color: t.accent)),
              ),
            ),
          ],
        ],
      ),
    );

    return LongPressDraggable<String>(
      data: item.id,
      feedback: Material(color: Colors.transparent, child: chip),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: GestureDetector(
        onTap: () => _openItem(context, item),
        // Marking something run out while putting the shopping away should
        // not cost a screen each time. Nothing is thrown away by it, so a
        // stray double tap is undone by another.
        onDoubleTap: () {
          final app = context.read<AppState>();
          app.setInStock(item.id, !item.inStock);
          phoneToast(
            context,
            item.inStock
                ? '${item.name} marked run out'
                : '${item.name} back in stock',
          );
        },
        child: chip,
      ),
    );
  }

  void _openItem(BuildContext context, PantryItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MobilePantryItemPage(itemId: item.id)),
    );
  }
}

/// The phone's equivalent of the desktop's right-click menu, reached from the
/// item screen since a long press is already the drag gesture here.
Future<void> showPantryItemMenu(BuildContext context, PantryItem item) async {
  final app = context.read<AppState>();
  {
    await showPhoneSheet<void>(
      context,
      title: item.name,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetRow(
            icon: item.inStock
                ? Icons.remove_circle_outline
                : Icons.check_circle_outline,
            title: item.inStock ? 'Mark as run out' : 'Back in stock',
            detail: item.inStock
                ? 'Keeps its macros and names; recipes count it as missing'
                : 'Recipes stop flagging it',
            onTap: () {
              app.setInStock(item.id, !item.inStock);
              Navigator.of(sheetContext).pop();
            },
          ),
          SheetRow(
            icon: Icons.delete_outline,
            title: 'Remove from pantry…',
            detail: 'Deletes its macros and other known names',
            accent: true,
            onTap: () async {
              Navigator.of(sheetContext).pop();
              final removed = await confirmRemovePantryItem(context, item);
              // The item screen has nothing left to show.
              if (removed && context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

/// One pantry item on the phone.
class MobilePantryItemPage extends StatelessWidget {
  const MobilePantryItemPage({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();
    final item = app.pantryItem(itemId);
    if (item == null) return const SizedBox.shrink();
    final usedIn = app.usedIn(itemId);

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: [
            MobileTopBar(
              title: item.name,
              actions: [
                IconButton(
                  icon: Icon(
                    Icons.more_horiz,
                    size: 21,
                    color: t.textSecondary,
                  ),
                  onPressed: () => showPantryItemMenu(context, item),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Tag(
                          item.inStock ? 'In stock' : 'Run out',
                          style: item.inStock
                              ? TagStyle.accent2
                              : TagStyle.outline,
                        ),
                        const Spacer(),
                        AppButton(
                          item.inStock ? 'Mark as run out' : 'Back in stock',
                          fontSize: 12.5,
                          height: 34,
                          onPressed: () =>
                              app.setInStock(item.id, !item.inStock),
                        ),
                      ],
                    ),
                  ),
                  if (item.brandLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        item.brandLabel!,
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 13,
                          color: t.textSecondary,
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          'Add to groceries',
                          height: 44,
                          fontSize: 14,
                          onPressed: () {
                            app.addGrocery(
                              item.name,
                              source: 'Pantry',
                              pantryItemId: item.id,
                            );
                            phoneToast(context, '${item.name} added');
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: AppButton(
                          'Edit macros',
                          kind: ButtonKind.primary,
                          height: 44,
                          fontSize: 14,
                          onPressed: () => EditMacrosDialog.open(context, item),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  if (!item.hasMacros)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: t.accent.withValues(alpha: 0.08),
                        borderRadius: t.brContainer,
                        border: Border.fromBorderSide(
                          BorderSide(color: t.accent),
                        ),
                      ),
                      child: Text(
                        'No macros yet. Every recipe using ${item.name} flags '
                        'this line rather than counting it as zero.',
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 13,
                          height: 1.5,
                          color: t.text,
                        ),
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        SectionLabel('Macros'),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.basis.label,
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
                      valueSize: 16,
                      labelSize: 10,
                      padding: 12,
                      cells: [
                        (value: '${item.calories!.round()}', label: 'cal'),
                        (
                          value: '${item.protein?.round() ?? 0}g',
                          label: 'protein',
                        ),
                        (value: '${item.fat?.round() ?? 0}g', label: 'fat'),
                        (value: '${item.carbs?.round() ?? 0}g', label: 'carbs'),
                        (value: '${item.sugar?.round() ?? 0}g', label: 'sugar'),
                      ],
                    ),
                  ],
                  const SizedBox(height: 22),
                  SectionLabel('Also known as'),
                  const SizedBox(height: 4),
                  Text(
                    'An imported recipe naming any of these draws from this '
                    'item.',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 11.5,
                      height: 1.4,
                      color: t.textFaint,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _AliasTags(item: item),
                  const SizedBox(height: 22),
                  SectionLabel('Used in'),
                  const SizedBox(height: 10),
                  if (usedIn.isEmpty)
                    Text(
                      'Nothing draws on this yet.',
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 13,
                        color: t.textMuted,
                      ),
                    ),
                  for (final row in usedIn)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: t.brContainer,
                      ),
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
                                    fontSize: 13.5,
                                    color: t.text,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'says “${row.line.name}”',
                                  style: TextStyle(
                                    fontFamily: t.bodyFamily,
                                    fontSize: 11,
                                    color: t.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${row.calories.round()} cal',
                            style: TextStyle(
                              fontFamily: t.bodyFamily,
                              fontSize: 12.5,
                              color: t.textStrong,
                            ),
                          ),
                        ],
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

/// An item's other names, editable.
///
/// The desktop removes a name with a small × on its tag. That is too fine a
/// target for a thumb and too easy to hit while scrolling, so here tapping a
/// name opens a sheet that offers to remove it.
class _AliasTags extends StatelessWidget {
  const _AliasTags({required this.item});

  final PantryItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.read<AppState>();

    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final alias in item.aliases)
          Tag(
            alias,
            trailing: Icon(Icons.close, size: 12, color: t.textMuted),
            onTap: () => _confirmRemove(context, app, alias),
          ),
        Tag(
          '＋ add',
          style: TagStyle.outline,
          onTap: () async {
            final name = await promptInPhoneSheet(
              context,
              title: 'Another name for ${item.name}',
              hint: 'choc chips',
            );
            if (name == null || name.trim().isEmpty) return;
            if (item.matchesName(name.trim())) {
              if (context.mounted) {
                phoneToast(context, '${item.name} already answers to that');
              }
              return;
            }
            app.addAlias(item.id, name.trim());
          },
        ),
      ],
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    AppState app,
    String alias,
  ) {
    return showPhoneSheet<void>(
      context,
      title: '“$alias”',
      subtitle:
          'Recipe lines already linked to ${item.name} stay linked. One '
          'that only matched by saying “$alias” stops drawing on it.',
      builder: (sheet) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetRow(
            icon: Icons.delete_outline,
            title: 'Remove this name',
            accent: true,
            onTap: () {
              app.removeAlias(item.id, alias);
              Navigator.of(sheet).pop();
            },
          ),
          SheetRow(
            icon: Icons.close,
            title: 'Keep it',
            onTap: () => Navigator.of(sheet).pop(),
          ),
        ],
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
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 38,
        height: 22,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? t.accent : t.toggleTrackOff,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Align(
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.toggleKnob,
            ),
          ),
        ),
      ),
    );
  }
}
