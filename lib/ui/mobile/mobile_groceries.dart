import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets/primitives.dart';
import 'mobile_widgets.dart';

/// Groceries on Android — the screen this app is most likely to be open on.
///
/// Same behaviours as the desktop: checked items dim in place and drop to the
/// bottom of their aisle, and Clear checked is the only thing that removes
/// them.
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
                  '$open to buy · $done in the cart',
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
}
