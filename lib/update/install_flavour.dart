import 'dart:io';

import 'release_check.dart';

/// How this Windows copy got here, and therefore which artefact updates it.
///
/// An artefact is not just the new bytes — it carries an installation method.
/// A zip's method is "unpack it and run it from there"; a setup exe's is
/// "close the registered install and replace it in place". Hand either to the
/// wrong kind of copy and the result is a *second* install rather than an
/// upgrade: a zip unpacked beside an installed copy leaves the Start-menu
/// entry and the uninstall record still pointing at the old version, and the
/// unpacked copy carries no marker, so it goes on choosing zips forever. The
/// divergence never heals on its own, which is why this is decided before the
/// app asks the releases API for anything.
enum InstallFlavour {
  /// Unpacked from the zip and run from wherever it landed.
  zip,

  /// Put here by the installer, with a Start-menu entry and an uninstall
  /// record that both name this folder.
  setup,
}

/// The empty file the installer leaves beside the executable.
///
/// The zip never contains one, so its presence is the whole test. Asking "am
/// I under Programs?" would be a heuristic about a coincidence — a zip can be
/// unpacked into Programs, and an installer can be pointed anywhere else —
/// while this is a fact recorded by whatever actually did the installing.
const kSetupMarker = 'installed-by-setup';

/// The flavour of the copy living in [installDir].
///
/// Takes the directory rather than finding it, so this can be tested against
/// a temp folder instead of a real install.
InstallFlavour flavourIn(Directory installDir) {
  final marker = File(
    '${installDir.path}${Platform.pathSeparator}$kSetupMarker',
  );
  return marker.existsSync() ? InstallFlavour.setup : InstallFlavour.zip;
}

/// Which artefact this build should ask the releases API for.
///
/// Pure, and takes the platform as an argument, so every combination can be
/// tested on one machine. Android has only ever had one artefact; the split
/// is a Windows question.
UpdatePlatform updateTargetFor({
  required bool isAndroid,
  required InstallFlavour flavour,
}) {
  if (isAndroid) return UpdatePlatform.android;
  return switch (flavour) {
    InstallFlavour.zip => UpdatePlatform.windows,
    InstallFlavour.setup => UpdatePlatform.windowsSetup,
  };
}
