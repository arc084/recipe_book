import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../data/settings.dart';
import '../../state/app_state.dart';
import '../../theme/tokens.dart';
import '../widgets/primitives.dart';

/// There is no onboarding — pairing and permissions live here from the first
/// run.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _librarySize = 0;
  int _pantrySize = 0;

  @override
  void initState() {
    super.initState();
    _refreshSizes();
  }

  Future<void> _refreshSizes() async {
    final app = context.read<AppState>();
    final l = await app.librarySize();
    final p = await app.pantrySize();
    if (!mounted) return;
    setState(() {
      _librarySize = l;
      _pantrySize = p;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final app = context.watch<AppState>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 30),
      children: [
        Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 3),
        Text(
          'No account, no server. Everything here is this device only unless '
          'it says otherwise.',
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: 12,
            color: t.textMuted,
          ),
        ),
        const SizedBox(height: 22),
        _syncSection(context, app),
        const SizedBox(height: 22),
        _databasesSection(context, app),
        const SizedBox(height: 22),
        _themeSection(context, app),
        const SizedBox(height: 22),
        _permissionsSection(context, app),
      ],
    );
  }

  // ── Sync ────────────────────────────────────────────────────────────────

  Widget _syncSection(BuildContext context, AppState app) {
    final t = context.tokens;
    return _Section(
      title: 'Sync',
      subtitle: 'Direct between devices on your local network — no account, '
          'no server.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Panel(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Paired devices',
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 13,
                          color: t.text,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        app.settings.devices.isEmpty
                            ? 'Nothing paired yet.'
                            : '${app.settings.devices.length} paired',
                        style: TextStyle(
                          fontFamily: t.bodyFamily,
                          fontSize: 11.5,
                          color: t.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                AppButton(
                  'Pair a device',
                  kind: ButtonKind.primary,
                  onPressed: () => _showPairingCode(context, app),
                ),
              ],
            ),
          ),
          for (final device in app.settings.devices) ...[
            const SizedBox(height: 8),
            Panel(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    device.platform == 'android'
                        ? Icons.phone_android
                        : Icons.desktop_windows,
                    size: 18,
                    color: t.textMuted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          device.name,
                          style: TextStyle(
                            fontFamily: t.bodyFamily,
                            fontSize: 13,
                            color: t.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${device.recipeCount} recipes · '
                          '${device.pantryCount} pantry items · '
                          '${device.lastSync == null ? 'never exchanged' : 'last exchanged ${DateFormat('d MMM, HH:mm').format(device.lastSync!)}'}',
                          style: TextStyle(
                            fontFamily: t.bodyFamily,
                            fontSize: 11,
                            color: t.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Unpairing is per device and never deletes anything.
                  AppButton(
                    'Unpair',
                    fontSize: 11.5,
                    onPressed: () => app.unpair(device.id),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'When the same thing changes in two places',
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 12.5,
              color: t.text,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final policy in ConflictPolicy.values) ...[
                Tag(
                  policy.label,
                  style: app.settings.conflictPolicy == policy
                      ? TagStyle.accent
                      : TagStyle.outline,
                  onTap: () => app.setConflictPolicy(policy),
                ),
                const SizedBox(width: 7),
              ],
              const SizedBox(width: 4),
              Text(
                'It is your call — the default is to ask.',
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 11,
                  color: t.textFaint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showPairingCode(BuildContext context, AppState app) {
    final code = app.newPairingCode();
    showDialog<void>(
      context: context,
      builder: (context) {
        final t = context.tokens;
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 420,
            padding: EdgeInsets.all(t.space(6)),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: t.brLarge,
              boxShadow: t.shadowLg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Enter this on the other device',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                SizedBox(height: t.space(2)),
                Text(
                  'It is typed, not scanned — no camera permission for a '
                  'one-off setup. The code expires.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 12,
                    height: 1.5,
                    color: t.textMuted,
                  ),
                ),
                SizedBox(height: t.space(6)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final digit in code.split(''))
                      Container(
                        width: 46,
                        height: 58,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: t.ground,
                          borderRadius: t.brContainer,
                          border: Border.fromBorderSide(
                            BorderSide(color: t.accent),
                          ),
                        ),
                        child: Text(
                          digit,
                          style: TextStyle(
                            fontFamily: t.bodyFamily,
                            fontSize: 28,
                            color: t.text,
                          ),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: t.space(6)),
                AppButton(
                  'Done',
                  kind: ButtonKind.primary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Databases ───────────────────────────────────────────────────────────

  Widget _databasesSection(BuildContext context, AppState app) {
    return _Section(
      title: 'Databases',
      subtitle: 'Two of them, listed separately. Each has its own back up, '
          'import and export, so a library can be replaced without touching '
          'the pantry.',
      child: Column(
        children: [
          _databaseRow(
            context,
            name: 'library',
            detail: '${app.library.recipes.length} recipes · '
                '${app.library.groceries.length} grocery items · '
                '${app.library.plan.length} planned meals',
            bytes: _librarySize,
            onExport: () async {
              final path = await getSaveLocation(
                suggestedName: 'library.json',
              );
              if (path == null) return;
              await app.exportLibrary(path.path);
              await _refreshSizes();
            },
            onImport: () async {
              final file = await openFile(
                acceptedTypeGroups: const [
                  XTypeGroup(label: 'Recipe Book library', extensions: ['json']),
                ],
              );
              if (file == null) return;
              final linked = await app.importLibrary(file.path);
              if (!context.mounted) return;
              await _refreshSizes();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                  'Library replaced. $linked ingredient '
                  '${linked == 1 ? 'name' : 'names'} matched your pantry on '
                  'the way in.',
                ),
                behavior: SnackBarBehavior.floating,
                width: 440,
              ));
            },
          ),
          const SizedBox(height: 8),
          _databaseRow(
            context,
            name: 'pantry',
            detail: '${app.pantry.items.length} ingredients · '
                '${app.itemsNeedingMacros.length} without macros',
            bytes: _pantrySize,
            onExport: () async {
              final path = await getSaveLocation(suggestedName: 'pantry.json');
              if (path == null) return;
              await app.exportPantry(path.path);
              await _refreshSizes();
            },
            onImport: () async {
              final file = await openFile(
                acceptedTypeGroups: const [
                  XTypeGroup(label: 'Recipe Book pantry', extensions: ['json']),
                ],
              );
              if (file == null) return;
              await app.importPantry(file.path);
              await _refreshSizes();
            },
          ),
        ],
      ),
    );
  }

  Widget _databaseRow(
    BuildContext context, {
    required String name,
    required String detail,
    required int bytes,
    required VoidCallback onExport,
    required VoidCallback onImport,
  }) {
    final t = context.tokens;
    return Panel(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.storage_outlined, size: 18, color: t.textMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 13,
                        color: t.text,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatBytes(bytes),
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 11,
                        color: t.textFaint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: TextStyle(
                    fontFamily: t.bodyFamily,
                    fontSize: 11.5,
                    color: t.textMuted,
                  ),
                ),
              ],
            ),
          ),
          AppButton('Back up', fontSize: 11.5, onPressed: onExport),
          const SizedBox(width: 7),
          AppButton('Import', fontSize: 11.5, onPressed: onImport),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes == 0) return 'not saved yet';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ── Theme ───────────────────────────────────────────────────────────────

  Widget _themeSection(BuildContext context, AppState app) {
    return _Section(
      title: 'Theme',
      subtitle: 'Per device — the kitchen laptop and the phone can differ.',
      child: Row(
        children: [
          for (final mode in ThemeMode.values) ...[
            Tag(
              switch (mode) {
                ThemeMode.light => 'Light',
                ThemeMode.dark => 'Dark',
                ThemeMode.system => 'System default',
              },
              style: app.settings.themeMode == mode
                  ? TagStyle.accent
                  : TagStyle.outline,
              onTap: () => app.setThemeMode(mode),
            ),
            const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }

  // ── Permissions ─────────────────────────────────────────────────────────

  Widget _permissionsSection(BuildContext context, AppState app) {
    final t = context.tokens;
    return _Section(
      title: 'Permissions',
      subtitle: 'Asked for when first needed, and listed here afterwards.',
      child: Panel(
        clip: true,
        child: Column(
          children: [
            for (var i = 0; i < app.settings.permissions.length; i++)
              Container(
                decoration: BoxDecoration(
                  border: i == 0
                      ? null
                      : Border(top: BorderSide(color: t.divider)),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.settings.permissions[i].label,
                            style: TextStyle(
                              fontFamily: t.bodyFamily,
                              fontSize: 13,
                              color: t.text,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            app.settings.permissions[i].purpose,
                            style: TextStyle(
                              fontFamily: t.bodyFamily,
                              fontSize: 11.5,
                              color: t.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      app.settings.permissions[i].granted
                          ? 'Allowed'
                          : 'Not asked yet',
                      style: TextStyle(
                        fontFamily: t.bodyFamily,
                        fontSize: 11.5,
                        color: app.settings.permissions[i].granted
                            ? t.accent
                            : t.textFaint,
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

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(
            subtitle!,
            style: TextStyle(
              fontFamily: t.bodyFamily,
              fontSize: 11.5,
              height: 1.5,
              color: t.textFaint,
            ),
          ),
        ],
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}
