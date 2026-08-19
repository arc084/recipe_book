import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/nav.dart';
import '../../theme/tokens.dart';
import '../settings/settings_page.dart';
import '../widgets/version_badge.dart';

/// The Library header: brand on the left, the read-only sync chip on the
/// right. The chip is the phone's equivalent of the desktop sidebar footer —
/// the controls it reports on live in Settings, which is reached from here
/// because the bottom bar only has four tabs.
class MobileHeader extends StatelessWidget {
  const MobileHeader({super.key, required this.title, this.showSync = true});

  final String title;
  final bool showSync;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Row(
        children: [
          Icon(Icons.menu_book_outlined, size: 22, color: t.accent),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          const SizedBox(width: 7),
          const VersionBadge(),
          const Spacer(),
          if (showSync)
            _SyncChip(
              paired: app.settings.devices.isNotEmpty,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const _MobileSettingsRoute()),
              ),
            ),
        ],
      ),
    );
  }
}

class _SyncChip extends StatelessWidget {
  const _SyncChip({required this.paired, required this.onTap});

  final bool paired;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: t.brContainer,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(
          color: t.text.withValues(alpha: 0.04),
          borderRadius: t.brContainer,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              paired ? Icons.check : Icons.settings_outlined,
              size: 15,
              color: t.accent,
            ),
            const SizedBox(width: 6),
            Text(
              paired ? 'Synced' : 'Settings',
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: 11.5,
                color: t.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileSettingsRoute extends StatelessWidget {
  const _MobileSettingsRoute();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.ground,
      body: SafeArea(
        child: Column(
          children: [
            const MobileTopBar(title: 'Settings'),
            const Expanded(child: SettingsPage(isPhone: true)),
          ],
        ),
      ),
    );
  }
}

/// A back bar for pushed phone screens.
class MobileTopBar extends StatelessWidget {
  const MobileTopBar({
    super.key,
    required this.title,
    this.actions = const <Widget>[],
    this.onBack,
  });

  final String title;
  final List<Widget> actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 12, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, size: 21, color: t.textSecondary),
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// A horizontally scrolling chip row — meal types and tags on the phone.
class ChipRow extends StatelessWidget {
  const ChipRow({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// A phone chip — bigger touch target than the desktop tag.
class TouchChip extends StatelessWidget {
  const TouchChip({
    super.key,
    required this.label,
    this.count,
    this.selected = false,
    this.onTap,
    this.fontSize = 12.5,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback? onTap;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? t.tagAccentBg : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.fromBorderSide(
            BorderSide(color: selected ? Colors.transparent : t.accent),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontFamily: t.bodyFamily,
                fontSize: fontSize,
                color: selected ? t.tagAccentFg : t.accent,
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 5),
              Text(
                '$count',
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: fontSize,
                  color: selected
                      ? t.tagAccentFg.withValues(alpha: 0.7)
                      : t.textFaint,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The bottom sheet the phone uses wherever the desktop opens a dialog.
Future<T?> showPhoneSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget Function(BuildContext) builder,
}) {
  final t = context.tokens;
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: t.surface,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(t.radiusLarge)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 14),
                decoration: BoxDecoration(
                  color: t.divider,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 12.5,
                    height: 1.5,
                    color: t.textMuted,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Flexible(child: builder(context)),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

/// A tappable row inside a phone sheet.
class SheetRow extends StatelessWidget {
  const SheetRow({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.trailing,
    this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 19, color: accent ? t.accent : t.textMuted),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 14.5,
                      color: accent ? t.accent : t.text,
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail!,
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 11.5,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// The Library's floating action button.
class PhoneFab extends StatelessWidget {
  const PhoneFab({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          // Nocturne's primary is an outline, so the FAB is a ringed surface;
          // Organic's is a fill, so the FAB fills.
          color: t.primaryButtonIsFilled ? t.accent : t.surface,
          borderRadius: BorderRadius.circular(t.radiusControl > 100 ? 999 : 16),
          border: t.primaryButtonIsFilled
              ? null
              : Border.fromBorderSide(BorderSide(color: t.accent)),
          boxShadow: t.shadowLg,
        ),
        child: Icon(
          Icons.add,
          size: 24,
          color: t.primaryButtonIsFilled ? t.ground : t.accent,
        ),
      ),
    );
  }
}

/// Confirms an action in place, so adding to groceries never moves the user.
void phoneToast(BuildContext context, String message) {
  final t = context.tokens;
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 13,
            color: t.text,
          ),
        ),
        backgroundColor: t.surface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: t.brContainer),
      ),
    );
}

/// Opens a recipe on the phone as a full screen rather than in a column.
void openMobileRecipe(BuildContext context, String recipeId, Widget page) {
  context.read<NavController>().openRecipe(recipeId);
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)).then((_) {
    if (context.mounted) context.read<NavController>().closeRecipe();
  });
}
