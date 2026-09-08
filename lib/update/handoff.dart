import 'dart:io';

import 'package:flutter/services.dart';

import 'release_check.dart';
import 'updater.dart';

/// Takes a downloaded artefact the last mile, and says what happened.
///
/// Failures throw [DownloadFailure] so the Settings row shows them the same
/// way it shows a download that broke off — in plain words, in place.
Future<String> handOffUpdate(File file, AvailableUpdate update) {
  if (Platform.isAndroid) return _installApk(file);
  if (Platform.isWindows) {
    // Routed on the artefact rather than on the flavour that asked for it.
    // The file in hand is what decides which method applies, and this way a
    // release that somehow served the wrong one is still handled correctly
    // rather than being unpacked because of what we expected to receive.
    return file.path.toLowerCase().endsWith('.exe')
        ? _runSetup(file)
        : _unpackBeside(file, update);
  }
  throw DownloadFailure('No update hand-off exists for this platform.');
}

/// Runs the downloaded installer without showing it.
///
/// An update is not a fresh install. Being made to click through a destination
/// page, a tasks page and a close-applications page — to receive a version you
/// already asked for, into the folder you are already in — is ceremony, and it
/// is the one part of updating that should feel like nothing happened.
///
/// Windows cannot replace a running exe, so the restart is not avoidable; it
/// is only made quiet. `/CLOSEAPPLICATIONS` lets the restart manager close
/// this copy at the moment it needs the files, and `/RESTARTAPP=1` asks the
/// installer to start it again afterwards, so what the user sees is the
/// window going and coming back on the new version.
///
/// `/RESTARTAPPLICATIONS` is deliberately not used, and was the bug in 0.7.4:
/// the Restart Manager only restarts applications that registered for it with
/// `RegisterApplicationRestart`, which a Flutter Windows app never calls. It
/// closed the app and then had nothing to bring back, so an update looked
/// like the app quitting. `/RESTARTAPP` is our own switch, handled by a
/// `[Run]` entry in the installer script.
Future<String> _runSetup(File setup) async {
  try {
    await Process.start(
      setup.path,
      const [
        '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        '/NORESTART',
        '/CLOSEAPPLICATIONS',
        '/RESTARTAPP=1',
      ],
      mode: ProcessStartMode.detached,
    );
  } on ProcessException catch (e) {
    throw DownloadFailure(
      'The installer could not be started: ${e.message}',
    );
  }
  return 'Updating — this window will close and come back on the new version.';
}

/// Hands the APK to the system installer through the app's own method
/// channel — the same no-plugin approach the share intake uses. Android
/// shows its own confirmation, which is correct and not worked around.
Future<String> _installApk(File file) async {
  const channel = MethodChannel('recipe_book/install');
  try {
    await channel.invokeMethod<void>('installApk', {'path': file.path});
  } on PlatformException catch (e) {
    throw DownloadFailure(
      'The installer could not be started: ${e.message ?? e.code}',
    );
  }
  return 'Handed to the Android installer — it takes over from here.';
}

/// Unpacks the zip beside the running install. A running exe cannot replace
/// its own folder, and a self-replacing updater is a large amount of
/// machinery for a two-device household — the new folder simply appears
/// next to this one.
Future<String> _unpackBeside(File zip, AvailableUpdate update) async {
  final installDir = File(Platform.resolvedExecutable).parent;
  final target = Directory(
    '${installDir.parent.path}${Platform.pathSeparator}'
    'recipe-book-${update.version}',
  );
  await target.create(recursive: true);

  // bsdtar ships with Windows 10 and later, and reads zip files; calling it
  // beats carrying an archive dependency for one extraction.
  final result = await Process.run('tar', [
    '-xf',
    zip.path,
    '-C',
    target.path,
  ]);
  if (result.exitCode != 0) {
    throw DownloadFailure(
      'Unpacking failed: ${result.stderr.toString().trim()}',
    );
  }
  return 'Unpacked to ${target.path} — close this app and run the new '
      'folder.';
}
