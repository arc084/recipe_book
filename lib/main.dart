import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'state/app_state.dart';
import 'state/nav.dart';
import 'theme/app_theme.dart';
import 'ui/shell/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // The 34px title bar in the design is ours, so Windows' own is hidden.
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      // The design canvas, and resizable from there.
      size: Size(1180, 760),
      minimumSize: Size(940, 600),
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
          home: const AppShell(),
        ),
      ),
    );
  }
}
