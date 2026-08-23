import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'state/app_state.dart';
import 'state/nav.dart';
import 'state/share_intake.dart';
import 'sync/sync_service.dart';
import 'theme/app_theme.dart';
import 'ui/cook/cook_mode.dart';
import 'ui/import/import_flow.dart';
import 'ui/settings/settings_page.dart';
import 'ui/shell/app_shell.dart';
import 'ui/shell/mobile_shell.dart';

/// True on the platforms that get the desktop frame.
///
/// `window_manager` is a desktop-only plugin, so every call into it has to sit
/// behind this — on Android the plugin simply is not there.
bool get isDesktop =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Runs the Android frame inside a phone-sized desktop window, so the mobile
/// layouts can be looked at without a device attached:
///
///     flutter run -d windows --dart-define=MOBILE_PREVIEW=true
///
/// It only swaps the frame — it does not emulate Android behaviour.
const kMobilePreview = bool.fromEnvironment('MOBILE_PREVIEW');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (isDesktop) {
    await windowManager.ensureInitialized();
    // The 34px title bar in the design is ours, so Windows' own is hidden.
    await windowManager.waitUntilReadyToShow(
      WindowOptions(
        // The design canvas, and resizable from there.
        size: kMobilePreview ? const Size(428, 908) : const Size(1180, 760),
        minimumSize: kMobilePreview
            ? const Size(360, 640)
            : const Size(940, 600),
        center: true,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
        title: 'Recipe Book',
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }

  final state = AppState();
  await state.load();

  runApp(RecipeBookApp(state: state));
}

class RecipeBookApp extends StatefulWidget {
  const RecipeBookApp({super.key, required this.state});

  final AppState state;

  @override
  State<RecipeBookApp> createState() => _RecipeBookAppState();
}

class _RecipeBookAppState extends State<RecipeBookApp>
    with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final ShareIntake _share = ShareIntake(onUrl: _importShared);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _share.start();

    // Opening the app is a resume too, but the lifecycle observer never hears
    // about it: it reports *transitions*, and at launch the app is already
    // resumed. Without this the first sync would wait until the user alt-tabbed
    // away and back, so a cold start always showed stale data.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncCloudFolder());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    // A link held back while cooking gets another chance on the way back in.
    if (_share.hasHeldLink) _share.flush();

    // Coming back to the app is the moment its data should be current: you
    // open the phone in the kitchen and the list is what the laptop last saw.
    // Only on focus, never on a timer and never in the background — reading a
    // folder is cheap, but a process that syncs while nobody is looking is not
    // what "local by default" means.
    _syncCloudFolder();
  }

  void _syncCloudFolder() {
    if (!widget.state.settings.hasCloudFolder) return;
    final context = _navigatorKey.currentContext;
    if (context == null) return;
    // Quiet when there is nothing to report: a snackbar on every app focus
    // saying "already up to date" would be noise.
    runCloudSync(context, widget.state, quietWhenIdle: true);
  }

  /// Routes a shared address into step 1 of the import.
  ///
  /// Returns false when the app is mid-cook, which holds the link rather than
  /// dropping it — being thrown out of the kitchen by a share would be worse
  /// than waiting.
  bool _importShared(String url) {
    if (CookMode.isActive) return false;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return false;

    // Let the frame settle before pushing over it on a cold start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _navigatorKey.currentContext;
      if (context != null) ImportFlow.startWithUrl(context, url);
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: widget.state),
        ChangeNotifierProvider(create: (_) => NavController()),
        // Owns the sockets. It only listens while a sync screen is open — the
        // app is offline by design.
        ChangeNotifierProvider(create: (_) => SyncService(widget.state)),
      ],
      child: Consumer<AppState>(
        builder: (context, app, _) => MaterialApp(
          title: 'Recipe Book',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          // Theme is per device — Light, Dark or System default.
          themeMode: app.settings.themeMode,
          home: const _Frame(),
        ),
      ),
    );
  }
}

/// Picks the frame.
///
/// The two platforms carry the same content and the same numbers; what
/// differs is navigation — a permanent sidebar against a bottom tab bar.
class _Frame extends StatelessWidget {
  const _Frame();

  @override
  Widget build(BuildContext context) {
    if (!isDesktop || kMobilePreview) return const MobileShell();
    // A desktop window dragged narrower than the sidebar layout can carry
    // still gets the desktop frame; the grid reflows instead.
    return const AppShell();
  }
}
