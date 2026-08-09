import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../../theme/tokens.dart';
import '../mobile/mobile_groceries.dart';
import '../mobile/mobile_library.dart';
import '../mobile/mobile_pantry.dart';
import '../mobile/mobile_plan.dart';

/// The Android frame: no title bar, no sidebar, a bottom tab bar.
///
/// Four tabs, in the same order as the desktop sidebar's first four. Settings
/// is reached from the Library header rather than taking a fifth tab — the
/// design's bar has four.
class MobileShell extends StatelessWidget {
  const MobileShell({super.key});

  static const _tabs = [
    AppTab.library,
    AppTab.pantry,
    AppTab.groceries,
    AppTab.plan,
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final nav = context.watch<NavController>();
    final tab = _tabs.contains(nav.tab) ? nav.tab : AppTab.library;

    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        bottom: false,
        child: switch (tab) {
          AppTab.pantry => const MobilePantryPage(),
          AppTab.groceries => const MobileGroceriesPage(),
          AppTab.plan => const MobilePlanPage(),
          _ => const MobileLibraryPage(),
        },
      ),
      bottomNavigationBar: _BottomBar(current: tab),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.current});

  final AppTab current;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();

    return Container(
      decoration: BoxDecoration(
        color: t.chrome,
        border: Border(top: BorderSide(color: t.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
          child: Row(
            children: [
              for (final tab in MobileShell._tabs)
                Expanded(
                  child: _BarItem(
                    tab: tab,
                    selected: tab == current,
                    // The badge is the unchecked count, and matches the list.
                    badge: tab == AppTab.groceries && app.openGroceryCount > 0
                        ? app.openGroceryCount
                        : null,
                    onTap: () => context.read<NavController>().go(tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.tab,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = selected ? t.accent : t.textMuted;

    return InkWell(
      onTap: onTap,
      borderRadius: t.brContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(tab.icon, size: 21, color: fg),
                if (badge != null)
                  Positioned(
                    right: -7,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: t.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$badge',
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 9.5,
                          height: 1.3,
                          color: t.ground,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              // The bar says "Plan"; the sidebar says "Meal Plan".
              tab == AppTab.plan ? 'Plan' : tab.label,
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
