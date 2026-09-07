import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recipe_book/update/install_flavour.dart';
import 'package:recipe_book/update/release_check.dart';

/// Which artefact a Windows build asks for, and why it is not a guess.
///
/// Crossing the two — a zip handed to an installed copy — does not fail
/// loudly. It quietly leaves a second, unregistered folder while the Start
/// menu still points at the old one, and the new copy carries no marker so it
/// goes on asking for zips forever. That is what these tests are guarding.
void main() {
  late Directory dir;

  File inDir(String name) =>
      File('${dir.path}${Platform.pathSeparator}$name');

  setUp(() => dir = Directory.systemTemp.createTempSync('rb_flavour'));
  tearDown(() => dir.deleteSync(recursive: true));

  group('reading the flavour off disk', () {
    test('a folder with no marker is an unpacked copy', () {
      expect(flavourIn(dir), InstallFlavour.zip);
    });

    test('the marker the installer writes makes it an installed copy', () {
      inDir(kSetupMarker).writeAsStringSync('');
      expect(flavourIn(dir), InstallFlavour.setup);
    });

    test('an empty marker still counts — presence is the whole signal', () {
      inDir(kSetupMarker).writeAsStringSync('');
      expect(inDir(kSetupMarker).lengthSync(), 0);
      expect(flavourIn(dir), InstallFlavour.setup);
    });

    test('the unpacked bundle is not mistaken for an install', () {
      // Exactly what the zip lays down: the exe, its DLLs and data/.
      inDir('recipe_book.exe').writeAsStringSync('');
      inDir('flutter_windows.dll').writeAsStringSync('');
      Directory('${dir.path}${Platform.pathSeparator}data').createSync();
      expect(flavourIn(dir), InstallFlavour.zip);
    });

    test('a missing folder reads as unpacked rather than throwing', () {
      // resolvedExecutable's parent always exists in practice, but a check
      // that can throw would take the whole Settings page down with it.
      final gone = Directory('${dir.path}${Platform.pathSeparator}nope');
      expect(flavourIn(gone), InstallFlavour.zip);
    });
  });

  group('choosing what to ask the releases API for', () {
    test('an unpacked Windows copy asks for the zip', () {
      expect(
        updateTargetFor(isAndroid: false, flavour: InstallFlavour.zip),
        UpdatePlatform.windows,
      );
    });

    test('an installed Windows copy asks for the setup exe', () {
      expect(
        updateTargetFor(isAndroid: false, flavour: InstallFlavour.setup),
        UpdatePlatform.windowsSetup,
      );
    });

    test('Android asks for the apk whatever the flavour reads', () {
      // There is one Android artefact and no marker file on that side, so
      // whatever flavourIn happened to return must not change the answer.
      for (final flavour in InstallFlavour.values) {
        expect(
          updateTargetFor(isAndroid: true, flavour: flavour),
          UpdatePlatform.android,
        );
      }
    });
  });
}
