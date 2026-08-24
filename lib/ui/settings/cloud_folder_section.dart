import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../sync/cloud/cloud_folder.dart';
import '../../sync/cloud/cloud_sync.dart';
import '../../sync/sync_service.dart';
import '../../theme/tokens.dart';
import '../widgets/primitives.dart';

/// Runs one pass through the folder and says what it did.
///
/// Shared with the on-focus trigger in `main.dart`, so a sync started either
/// way reports the same way and a tie raised either way lands on the same
/// review screen.
Future<void> runCloudSync(
  BuildContext context,
  AppState app, {
  bool quietWhenIdle = false,
}) async {
  final path = app.settings.cloudFolderPath;
  if (path == null) return;

  final sync = context.read<SyncService>();
  final outcome = await CloudSync(
    app,
    CloudFolder(Directory(path)),
    reviews: sync,
  ).run();

  if (!context.mounted) return;

  // A sync that ran on app focus and found nothing should not interrupt;
  // one the user asked for should always answer.
  if (quietWhenIdle && outcome.isEmpty && outcome.conflicts == 0) return;

  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(outcome.message)));

  if (outcome.skipped.isNotEmpty) {
    // Usually another device mid-write, which resolves itself. Worth saying
    // once rather than never, because a file that never parses looks exactly
    // the same from here.
    debugPrint(
      'Cloud sync skipped ${outcome.skipped.length} unreadable '
      '${outcome.skipped.length == 1 ? 'post' : 'posts'}: '
      '${outcome.skipped.map((s) => s.fileName).join(', ')}',
    );
  }
}

/// The Settings section for the cloud folder, on its own so tests can pump
/// it without the rest of the Settings page.
class CloudFolderSection extends StatelessWidget {
  const CloudFolderSection({super.key, this.relayRoot});

  /// Where the Android relay lives. Set in tests; derived from the platform
  /// app-files directory otherwise.
  final Future<String?> Function()? relayRoot;

  /// Whether this platform can open a chosen folder as an ordinary directory.
  ///
  /// Android's picker hands back a `content://` URI, which `dart:io` cannot
  /// open — reaching a Dropbox folder there needs the Storage Access Framework
  /// and a platform channel. Driven by [defaultTargetPlatform] rather than
  /// dart:io's Platform so a test can put this widget on Android.
  bool get _canUseCloudFolder =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = context.tokens;
    final path = app.settings.cloudFolderPath;

    return _SectionShell(
      title: 'Cloud folder',
      subtitle:
          'Optional. Point this at a folder Dropbox, OneDrive, Drive or '
          'Syncthing already keeps in step, and your devices swap changes '
          'through it. The app never talks to the provider — it only reads '
          'and writes files.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_canUseCloudFolder)
            Panel(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Not on Android yet. Android hands apps a document reference '
                'rather than a folder path, which needs work this build does '
                'not have. Use the local network sync above, or set the folder '
                'up on the desktop.',
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12.5,
                  height: 1.5,
                  color: t.textMuted,
                ),
              ),
            )
          else if (path == null)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'No folder chosen. Your data stays on this device.',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 12.5,
                      color: t.textMuted,
                    ),
                  ),
                ),
                AppButton(
                  'Choose a folder',
                  kind: ButtonKind.primary,
                  onPressed: () => _chooseCloudFolder(context, app),
                ),
              ],
            )
          else ...[
            Panel(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.folder_outlined, size: 18, color: t.accent),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              path,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: t.bodyFamily,
                                fontSize: 12.5,
                                color: t.text,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              app.settings.cloudSyncEnabled
                                  ? 'Syncing when you open the app'
                                  : 'Paused',
                              style: TextStyle(
                                fontFamily: t.bodyFamily,
                                fontSize: 11,
                                color: t.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      AppButton(
                        app.settings.cloudSyncEnabled ? 'Pause' : 'Resume',
                        fontSize: 12,
                        onPressed: () => app.setCloudSyncEnabled(
                          !app.settings.cloudSyncEnabled,
                        ),
                      ),
                      const SizedBox(width: 7),
                      AppButton(
                        'Change',
                        fontSize: 12,
                        onPressed: () => _chooseCloudFolder(context, app),
                      ),
                      const SizedBox(width: 7),
                      AppButton(
                        'Stop using',
                        fontSize: 12,
                        onPressed: () => app.setCloudFolder(null),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Nothing is deleted from the folder when you stop using '
                    'it.',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 11,
                      color: t.textFaint,
                    ),
                  ),
                ),
                AppButton(
                  'Sync now',
                  kind: ButtonKind.primary,
                  onPressed: () => runCloudSync(context, app),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _chooseCloudFolder(BuildContext context, AppState app) async {
    final chosen = await getDirectoryPath(confirmButtonText: 'Use this folder');
    if (chosen == null || !context.mounted) return;
    app.setCloudFolder(chosen);
    await runCloudSync(context, app);
  }
}

/// The section frame, matching the Settings page's own `_Section` — private
/// to that file, and ~30 lines is not worth coupling the two files over.
class _SectionShell extends StatelessWidget {
  const _SectionShell({
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
