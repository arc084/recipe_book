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
  if (Platform.isWindows) return _unpackBeside(file, update);
  throw DownloadFailure('No update hand-off exists for this platform.');
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
