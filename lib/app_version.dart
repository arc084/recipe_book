import 'package:flutter/foundation.dart';

/// The app's version, shown beside the brand on both platforms.
///
/// **1.0.0 is reserved** for the release where every planned feature is built
/// and debugged. Until then this stays below it, so the number itself says the
/// app is still being built rather than finished.
///
/// This is a plain constant rather than something read off the platform at
/// runtime, which would mean another native plugin for one string. The cost is
/// that it could drift from `pubspec.yaml` — so a test asserts the two agree,
/// and will fail the build if one is bumped without the other.
const String kAppVersion = '0.7.1';

/// How the app was compiled.
///
/// Worth showing because the two behave differently in ways that matter when
/// something looks wrong: a debug build carries the debug engine, runs
/// noticeably slower, and is roughly three times the size. Knowing which one
/// is on screen saves chasing a performance problem that is only the build.
enum BuildFlavour {
  debug('debug'),
  profile('profile'),
  release('release');

  const BuildFlavour(this.label);
  final String label;

  static BuildFlavour get current {
    if (kDebugMode) return BuildFlavour.debug;
    if (kProfileMode) return BuildFlavour.profile;
    return BuildFlavour.release;
  }
}

/// What the user sees: `0.7.0` on a release, `0.7.0 · debug` otherwise.
///
/// A release build says nothing extra — the ordinary case should not be
/// labelled, or the label stops carrying information.
String get versionLabel {
  final flavour = BuildFlavour.current;
  return flavour == BuildFlavour.release
      ? kAppVersion
      : '$kAppVersion · ${flavour.label}';
}

/// True when this build is not a release, for anything that wants to draw
/// attention to it rather than just state it.
bool get isPrereleaseBuild => BuildFlavour.current != BuildFlavour.release;
