# Android Cloud Folder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an Android phone join cloud-folder sync through a fixed relay folder under `Android/media/<package>/`, with the sync engine unchanged.

**Architecture:** A pure path-derivation function (`androidMediaRelay`) maps the app-files directory to the app's shared-media directory. The Settings cloud section moves into its own widget (`CloudFolderSection`) with the platform gate switched to `defaultTargetPlatform` so widget tests can drive the Android branch on Linux; on Android it offers one setup action that creates the relay and sets `cloudFolderPath`, after which the existing configured card shows the mover-facing path with a Copy button instead of the desktop's folder picker. `CloudFolder`/`CloudSync`/the focus-triggered sync run as-is.

**Tech Stack:** Flutter/Dart, `path_provider` (already a dependency), `flutter_test` with `debugDefaultTargetPlatformOverride`.

**Spec:** `docs/plans/android-cloud-folder.md` — read it first; this plan implements it exactly.

## Global Constraints

- After every task: `flutter test` fully green and `flutter analyze` clean before committing. **Capture test output to a file and check the exit code — never trust `flutter test | tail`** (the pipe masks failure; this bit us in the label-search build).
- Widget tests must not let a debounced `JsonStore` save fire under fake async: after any action that touches settings, drain with `await tester.runAsync(app.flush)` before further pumping.
- All filesystem work in UI handlers is synchronous (`createSync`) — same reasoning as the draft store: nothing to park in a fake zone, nothing to die with a process.
- Work happens in worktree `.claude/worktrees/android-cloud-folder` on branch `worktree-android-cloud-folder`. Do not touch other worktrees.
- Every commit message ends with the two trailer lines used by this session's earlier commits:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_01UpCDB13untHJkHJXwB5aGs`

---

### Task 1: Derive the relay path, purely

**Files:**
- Create: `lib/sync/cloud/android_relay.dart`
- Test: `test/android_relay_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `String? androidMediaRelay(String externalFilesPath)` — Task 3 calls it from `package:recipe_book/sync/cloud/android_relay.dart`.

- [ ] **Step 1: Write the failing tests**

`test/android_relay_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/sync/cloud/android_relay.dart';

/// The one bit of Android path knowledge in the app: app-files directory in,
/// shared-media directory out. Strict on purpose — a layout it does not
/// recognise yields null, and the caller says so, rather than pointing a sync
/// app at a guess.
void main() {
  test('derives the media directory from the documented layout', () {
    expect(
      androidMediaRelay(
        '/storage/emulated/0/Android/data/com.example.recipe_book/files',
      ),
      '/storage/emulated/0/Android/media/com.example.recipe_book',
    );
  });

  test('tolerates a trailing slash', () {
    expect(
      androidMediaRelay(
        '/storage/emulated/0/Android/data/com.example.recipe_book/files/',
      ),
      '/storage/emulated/0/Android/media/com.example.recipe_book',
    );
  });

  test('an SD-card path yields null — the relay lives on primary storage', () {
    expect(
      androidMediaRelay(
        '/storage/A1B2-C3D4/Android/data/com.example.recipe_book/files',
      ),
      isNull,
    );
  });

  test('a path that is not an app-files directory yields null', () {
    expect(androidMediaRelay('/data/user/0/com.example/files'), isNull);
    expect(androidMediaRelay('/storage/emulated/0/Download'), isNull);
    expect(androidMediaRelay(''), isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/android_relay_test.dart > /tmp/claude-1000/-home-overr/243fc2e6-f698-4ec4-86a6-e4be2d7688d0/scratchpad/t1.log 2>&1; echo $?`
Expected: nonzero exit — the library does not exist.

- [ ] **Step 3: Write the implementation**

`lib/sync/cloud/android_relay.dart`:

```dart
/// The app's shared-media directory, derived from its app-files path.
///
/// `path_provider` hands Android apps
/// `/storage/emulated/<user>/Android/data/<package>/files`. The sibling
/// `Android/media/<package>` is the one app-specific directory that other
/// apps — the Syncthings and FolderSyncs that actually move files — can still
/// reach under scoped storage, which is what makes it the relay.
///
/// Returns null when the layout is not the documented one — including SD
/// cards, deliberately: the relay lives on primary storage, and a vendor
/// surprise fills nothing rather than pointing a sync app at a guess.
String? androidMediaRelay(String externalFilesPath) {
  final m = RegExp(
    r'^(/storage/emulated/\d+)/Android/data/([^/]+)/files/?$',
  ).firstMatch(externalFilesPath);
  if (m == null) return null;
  return '${m.group(1)}/Android/media/${m.group(2)}';
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/android_relay_test.dart > .../t1b.log 2>&1; echo $?` (same scratchpad) — expect exit 0 and `All tests passed!` in the log.

- [ ] **Step 5: Analyze and commit**

`flutter analyze` — no issues.

```bash
git add lib/sync/cloud/android_relay.dart test/android_relay_test.dart
git commit -m "Derive the Android relay folder, purely

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UpCDB13untHJkHJXwB5aGs"
```

---

### Task 2: Give the cloud section its own file

Behaviour-preserving extraction, so Task 3's Android work lands in a widget a
test can pump without the whole Settings page (whose database-size IO and sync
providers made us skip page-level tests in the label-search build).

**Files:**
- Create: `lib/ui/settings/cloud_folder_section.dart`
- Modify: `lib/ui/settings/settings_page.dart` (remove `runCloudSync` at lines 20–57, `_canUseCloudFolder` around line 142, `_cloudSection` and `_chooseCloudFolder` around lines 145–290; call site in `build`'s children)
- Modify: `lib/main.dart` (import of `runCloudSync`, line 14 area)
- Test: `test/cloud_folder_section_test.dart`

**Interfaces:**
- Consumes: existing `runCloudSync`, `_cloudSection`, `_chooseCloudFolder` bodies (moved verbatim), `_Section` (which stays in settings_page.dart — the new widget builds its own copy, see below).
- Produces: `class CloudFolderSection extends StatelessWidget` with constructor `const CloudFolderSection({super.key, this.relayRoot})` where `relayRoot` is `final Future<String?> Function()?` (used in Task 3; declared now so the constructor is stable). The widget takes no `app` field: `build` starts with `final app = context.watch<AppState>();` — the watch is what rebuilds the section when a tap mutates settings, a job the page's own watch used to do; top-level `Future<void> runCloudSync(BuildContext context, AppState app, {bool quietWhenIdle = false})` exported from the new file.

- [ ] **Step 1: Write the failing test**

`test/cloud_folder_section_test.dart`:

```dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:recipe_book/state/app_state.dart';
import 'package:recipe_book/theme/app_theme.dart';
import 'package:recipe_book/ui/settings/cloud_folder_section.dart';

/// The cloud section on its own: the desktop offer, and (from Task 3) the
/// Android relay. Platform is driven through defaultTargetPlatform so the
/// Android branch runs on this Linux machine.
void main() {
  late Directory dir;
  late AppState app;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('rb_cloud_section');
    app = AppState(directory: dir);
    await app.load();
  });

  tearDown(() async {
    await app.flush();
    dir.deleteSync(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    // The setUp load armed debounced saves; run them in the real zone before
    // fake-time pumps can fire them (see drain in mobile_recipe_edit_test).
    await tester.runAsync(app.flush);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CloudFolderSection(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a desktop with no folder chosen is offered the picker',
      (tester) async {
    await pump(tester);
    expect(find.text('Choose a folder'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run with output captured and exit code checked, as in Task 1.
Expected: compilation failure — the library does not exist.

- [ ] **Step 3: Extract the widget**

Create `lib/ui/settings/cloud_folder_section.dart`. Move into it, from
`settings_page.dart`, **verbatim**:

- the whole `runCloudSync` function (with its doc comment),
- the `_canUseCloudFolder` getter,
- the `_cloudSection` method body,
- the `_chooseCloudFolder` method.

Shape of the new file:

```dart
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

// runCloudSync moves here verbatim, doc comment and all.

/// The Settings section for the cloud folder, on its own so tests can pump
/// it without the rest of the Settings page.
class CloudFolderSection extends StatelessWidget {
  const CloudFolderSection({super.key, this.relayRoot});

  /// Where the Android relay lives. Set in tests; derived from the platform
  /// app-files directory otherwise. Unused until the relay ships (Task 3).
  final Future<String?> Function()? relayRoot;

  /// Whether this platform can open a chosen folder as an ordinary
  /// directory. Driven by [defaultTargetPlatform] rather than dart:io's
  /// Platform so a test can put this widget on Android.
  bool get _canUseCloudFolder =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    // then _cloudSection's body verbatim, with `_Section` renamed to the
    // local `_SectionShell` below.
  }

  Future<void> _chooseCloudFolder(BuildContext context, AppState app) async {
    // moved verbatim
  }
}
```

Two mechanical adjustments while moving, both because the widget leaves the
page:

1. `settings_page.dart`'s private `_Section` cannot be shared across
   libraries. Copy its build into this file as a private `_SectionShell`
   with the same `{title, subtitle, child}` shape and appearance (copy the
   `_Section` widget verbatim under the new name). It is ~30 lines; a shared
   public widget is not worth coupling the two files over.
2. The exact import list above: `file_selector` provides `getDirectoryPath`
   (check the name used at the old call site and keep whatever package the
   page imported for it).

In `settings_page.dart`: delete the moved code, add
`import 'cloud_folder_section.dart';`, and replace the call site
`_cloudSection(context, app)` with `const CloudFolderSection()`.

In `main.dart`: `runCloudSync` now comes from
`ui/settings/cloud_folder_section.dart` — update the import (line 14 area)
if `settings_page.dart` no longer re-exports it.

- [ ] **Step 4: Run the new test, then the full suite**

Both green, exit codes checked from captured logs. The full suite is the
real assertion here: the extraction must change nothing.

- [ ] **Step 5: Analyze and commit**

```bash
git add lib/ui/settings/cloud_folder_section.dart lib/ui/settings/settings_page.dart lib/main.dart test/cloud_folder_section_test.dart
git commit -m "Give the cloud folder section a file of its own

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UpCDB13untHJkHJXwB5aGs"
```

---

### Task 3: The relay on the phone

**Files:**
- Modify: `lib/ui/settings/cloud_folder_section.dart`
- Test: `test/cloud_folder_section_test.dart` (extend)

**Interfaces:**
- Consumes: `androidMediaRelay` (Task 1), `CloudFolderSection.relayRoot` (Task 2), `AppState.setCloudFolder` / `setCloudSyncEnabled` (existing — note `setCloudFolder(path)` already flips `cloudSyncEnabled` on).
- Produces: nothing later tasks need.

- [ ] **Step 1: Write the failing tests**

Append to `test/cloud_folder_section_test.dart` (and extend `pump` with an
optional relayRoot):

```dart
  Future<void> pumpAndroid(
    WidgetTester tester, {
    Future<String?> Function()? relayRoot,
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.runAsync(app.flush);
    await tester.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CloudFolderSection(relayRoot: relayRoot),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Android is offered the relay, not the picker', (tester) async {
    await pumpAndroid(tester);
    expect(find.text('Set up the relay folder'), findsOneWidget);
    expect(find.text('Choose a folder'), findsNothing);
    expect(find.textContaining('Not on Android yet'), findsNothing);
  });

  testWidgets('setting up creates the relay and turns sync on',
      (tester) async {
    final root = '${dir.path}/media/com.example.recipe_book';
    await pumpAndroid(tester, relayRoot: () async => root);

    await tester.tap(find.text('Set up the relay folder'));
    await tester.pumpAndSettle();
    await tester.runAsync(app.flush); // the settings save this armed

    expect(app.settings.cloudFolderPath, root);
    expect(app.settings.cloudSyncEnabled, isTrue);
    // The subfolder the mover syncs exists, ready to be pointed at.
    expect(Directory('$root/recipe-book').existsSync(), isTrue);
    // The card shows the mover-facing path and offers to copy it.
    expect(find.textContaining('$root/recipe-book'), findsOneWidget);
    expect(find.text('Copy path'), findsOneWidget);
    expect(find.text('Change'), findsNothing);
  });

  testWidgets('a phone the relay cannot be derived on says so',
      (tester) async {
    await pumpAndroid(tester, relayRoot: () async => null);
    await tester.tap(find.text('Set up the relay folder'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Could not find the shared media folder'),
      findsOneWidget,
    );
    expect(app.settings.cloudFolderPath, isNull);
  });
```

- [ ] **Step 2: Run to verify the new tests fail**

Captured log, exit code checked. Expected: the first new test fails on
`find.text('Set up the relay folder')` (the section still shows the
"Not on Android yet" panel); the others fail the same way.

- [ ] **Step 3: Implement the Android branch**

All in `lib/ui/settings/cloud_folder_section.dart`.

Add imports:

```dart
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../sync/cloud/android_relay.dart';
```

Add to `CloudFolderSection`:

```dart
  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// The production [relayRoot]: app-files directory in, media directory out.
  static Future<String?> _defaultRelayRoot() async {
    final files = await getExternalStorageDirectory();
    return files == null ? null : androidMediaRelay(files.path);
  }

  /// One tap: derive the relay, create the mover-facing subfolder, point
  /// sync at it. Deliberately does not run a first sync — the mover is not
  /// configured yet at this moment, and the card's own Sync now covers it.
  Future<void> _setUpRelay(BuildContext context, AppState app) async {
    final root = await (relayRoot ?? _defaultRelayRoot)();
    if (!context.mounted) return;
    if (root == null) {
      // A vendor layout we do not recognise. Saying so beats a silent no-op —
      // the spec's contingency (getExternalMediaDirs over a channel) starts
      // from this message being reported.
      final t = context.tokens;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Could not find the shared media folder on this phone.',
              style: TextStyle(fontFamily: t.bodyFamily, fontSize: 12.5),
            ),
            backgroundColor: t.surface,
            behavior: SnackBarBehavior.floating,
            width: 380,
          ),
        );
      return;
    }
    // Synchronous on purpose: nothing to park in a test's fake zone, nothing
    // to die with the process.
    Directory('$root/recipe-book').createSync(recursive: true);
    app.setCloudFolder(root); // also turns cloudSyncEnabled on
  }
```

In `build`, three edits to the moved `_cloudSection` body:

1. Replace the `if (!_canUseCloudFolder) Panel(…Not on Android yet…)` branch
   with:

```dart
          if (!_canUseCloudFolder && !_isAndroid)
            Panel(
              padding: const EdgeInsets.all(14),
              child: Text(
                'Not available on this platform yet.',
                style: TextStyle(
                  fontFamily: t.bodyFamily,
                  fontSize: 12.5,
                  height: 1.5,
                  color: t.textMuted,
                ),
              ),
            )
          else if (path == null && _isAndroid)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'The app keeps a relay folder that Syncthing, or a sync '
                    'app mirroring OneDrive or Dropbox, can move for it. '
                    'Uninstalling the app deletes the relay; it is only a '
                    'copy.',
                    style: TextStyle(
                      fontFamily: t.bodyFamily,
                      fontSize: 12.5,
                      height: 1.5,
                      color: t.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AppButton(
                  'Set up the relay folder',
                  kind: ButtonKind.primary,
                  onPressed: () => _setUpRelay(context, app),
                ),
              ],
            )
          else if (path == null)
            // the existing desktop 'Choose a folder' Row, unchanged
```

2. In the configured card, the path `Text(path, …)` becomes the mover-facing
   path on Android:

```dart
                            Text(
                              _isAndroid ? '$path/recipe-book' : path,
```

3. The `Change` button becomes `Copy path` on Android:

```dart
                      AppButton(
                        _isAndroid ? 'Copy path' : 'Change',
                        fontSize: 12,
                        onPressed: _isAndroid
                            ? () => Clipboard.setData(
                                ClipboardData(text: '$path/recipe-book'),
                              )
                            : () => _chooseCloudFolder(context, app),
                      ),
```

- [ ] **Step 4: Run the section tests, then the full suite**

Captured logs, exit codes. All green.

- [ ] **Step 5: Analyze, update the spec status, and commit**

`flutter analyze` clean. In `docs/plans/android-cloud-folder.md` flip the
status line to built-with-on-device-checks-outstanding, in the voice of the
other plan docs.

```bash
git add lib/ui/settings/cloud_folder_section.dart test/cloud_folder_section_test.dart docs/plans/android-cloud-folder.md
git commit -m "Offer the relay folder on Android

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01UpCDB13untHJkHJXwB5aGs"
```

---

## After the tasks

- On-device, by hand (Deniz): set up the relay on the phone, point Syncthing
  at `…/Android/media/<package>/recipe-book` (and separately a OneDrive
  mirror app), confirm posts flow both ways. If setup reports the
  could-not-find message, the spec's `getExternalMediaDirs` contingency
  becomes the next task.
- Out of scope, recorded in the spec: a user-chosen folder with All Files
  Access; any SAF IO layer.
