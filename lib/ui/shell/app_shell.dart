import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../../theme/tokens.dart';
import '../groceries/groceries_page.dart';
import '../library/library_page.dart';
import '../pantry/pantry_page.dart';
import '../plan/plan_page.dart';
import '../recipe/recipe_page.dart';
import '../settings/settings_page.dart';

/// The desktop frame: a 34px title bar of our own, a permanent 216px sidebar,
/// and the main column.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final nav = context.watch<NavController>();

    return Scaffold(
      backgroundColor: t.ground,
      body: Column(
        children: [
          const _TitleBar(),
          Expanded(
            child: Row(
              children: [
                const _Sidebar(),
                Expanded(
                  child: ColoredBox(color: t.ground, child: _content(nav)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(NavController nav) {
    // A recipe opens inside the Library's column rather than as its own tab.
    if (nav.tab == AppTab.library && nav.recipeId != null) {
      return RecipePage(recipeId: nav.recipeId!, key: ValueKey(nav.recipeId));
    }
    return switch (nav.tab) {
      AppTab.library => const LibraryPage(),
      AppTab.pantry => const PantryPage(),
      AppTab.groceries => const GroceriesPage(),
      AppTab.plan => const PlanPage(),
      AppTab.settings => const SettingsPage(),
    };
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Title bar
// ═══════════════════════════════════════════════════════════════════════════

class _TitleBar extends StatelessWidget {
  const _TitleBar();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        await windowManager.isMaximized()
            ? windowManager.unmaximize()
            : windowManager.maximize();
      },
      child: Container(
        height: 34,
        color: t.titleBar,
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            Text(
              'Recipe Book',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11.5,
                color: t.textMuted,
              ),
            ),
            const Spacer(),
            _WindowButton(icon: Icons.remove, onTap: windowManager.minimize),
            _WindowButton(
              icon: Icons.crop_square_outlined,
              iconSize: 11,
              onTap: () async => await windowManager.isMaximized()
                  ? windowManager.unmaximize()
                  : windowManager.maximize(),
            ),
            _WindowButton(
              icon: Icons.close,
              onTap: () async {
                await context.read<AppState>().flush();
                await windowManager.close();
              },
              danger: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.icon,
    required this.onTap,
    this.iconSize = 13,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double iconSize;
  final bool danger;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 44,
          height: 34,
          color: _hover
              ? (widget.danger
                    ? const Color(0xFFC42B1C)
                    : t.text.withValues(alpha: 0.08))
              : Colors.transparent,
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: _hover && widget.danger ? Colors.white : t.textFaint,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Sidebar
// ═══════════════════════════════════════════════════════════════════════════

class _Sidebar extends StatelessWidget {
  const _Sidebar();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final nav = context.watch<NavController>();
    final app = context.watch<AppState>();

    return Container(
      width: 216,
      color: t.chrome,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
            child: Row(
              children: [
                Icon(Icons.menu_book_outlined, size: 20, color: t.accent),
                const SizedBox(width: 9),
                Text(
                  'My Cookbook',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          for (final tab in [
            AppTab.library,
            AppTab.pantry,
            AppTab.groceries,
            AppTab.plan,
          ])
            _NavItem(
              tab: tab,
              selected: nav.tab == tab,
              badge: tab == AppTab.groceries && app.openGroceryCount > 0
                  ? '${app.openGroceryCount}'
                  : null,
              onTap: () => context.read<NavController>().go(tab),
            ),
          const Spacer(),
          Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            color: t.divider,
          ),
          // Read-only here; the controls are in Settings.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.check, size: 16, color: t.accent),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    _syncLabel(app),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 12,
                      color: t.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _NavItem(
            tab: AppTab.settings,
            selected: nav.tab == AppTab.settings,
            onTap: () => context.read<NavController>().go(AppTab.settings),
          ),
        ],
      ),
    );
  }

  String _syncLabel(AppState app) {
    final last = app.settings.lastSync;
    if (app.settings.devices.isEmpty) return 'Not paired';
    if (last == null) return 'Never synced';
    final delta = DateTime.now().difference(last);
    if (delta.inMinutes < 1) return 'Synced · just now';
    if (delta.inMinutes < 60) return 'Synced · ${delta.inMinutes} min ago';
    if (delta.inHours < 24) return 'Synced · ${delta.inHours} h ago';
    return 'Synced · ${DateFormat.MMMd().format(last)}';
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final fg = widget.selected ? t.accent : t.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: widget.selected
                  ? t.accent.withValues(alpha: 0.14)
                  : _hover
                  ? t.text.withValues(alpha: 0.05)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(
                t.radiusControl > 100 ? 999 : t.radiusContainer,
              ),
            ),
            child: Row(
              children: [
                Icon(widget.tab.icon, size: 17, color: fg),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.tab.label,
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 13.5,
                      color: fg,
                    ),
                  ),
                ),
                if (widget.badge != null)
                  Text(
                    widget.badge!,
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 11,
                      color: widget.selected ? t.accent : t.textFaint,
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
