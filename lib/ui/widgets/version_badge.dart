import 'package:flutter/material.dart';

import '../../app_version.dart';
import '../../theme/tokens.dart';

/// The version, sat beside the brand on both platforms.
///
/// Quiet by default — on a release build it is muted meta text that reads as
/// part of the masthead rather than competing with it. A debug or profile
/// build takes the accent and an outline instead, because that is worth
/// noticing: those builds behave differently enough that mistaking one for the
/// real thing sends you chasing problems that are only the build.
class VersionBadge extends StatelessWidget {
  const VersionBadge({super.key, this.fontSize = 10.5});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final flagged = isPrereleaseBuild;

    return Tooltip(
      message: flagged
          ? 'Version $kAppVersion, ${BuildFlavour.current.label} build — '
                'slower and larger than a release'
          : 'Version $kAppVersion',
      child: Container(
        padding: flagged
            ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
            : EdgeInsets.zero,
        decoration: flagged
            ? BoxDecoration(
                color: t.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.fromBorderSide(
                  BorderSide(color: t.accent.withValues(alpha: 0.5)),
                ),
              )
            : null,
        child: Text(
          versionLabel,
          style: TextStyle(
            fontFamily: t.bodyFamily,
            fontSize: fontSize,
            height: 1.2,
            letterSpacing: 0.2,
            color: flagged ? t.accent : t.textFaint,
          ),
        ),
      ),
    );
  }
}
