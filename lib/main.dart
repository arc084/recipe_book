import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'state/app_state.dart';
import 'state/nav.dart';
import 'theme/app_theme.dart';
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
        minimumSize:
            kMobilePreview ? const Size(360, 640) : const Size(940, 600),
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

class RecipeBookApp extends StatelessWidget {
  const RecipeBookApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: state),
        ChangeNotifierProvider(create: (_) => NavController()),
      ],
      child: Consumer<AppState>(
        builder: (context, app, _) => MaterialApp(
          title: 'Recipe Book',
          debugShowCheckedModeBanner: false,
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
/// The two platforms carry the same content and the same numbers; what differs
/// is navigation — a permanent sidebar against a bottom tab bar — and that
/// editing a recipe is desktop only.
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
