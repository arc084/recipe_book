# 2. A desktop installer waits for the update loop and real users

Date: 2026-08-23. Status: accepted — deliberately deferred.

## Context

The desktop ships as a zip on GitHub releases, run from wherever it is
unpacked. An installer (Inno Setup on Windows; an AUR PKGBUILD or Flatpak on
Linux) would add a Start-menu entry, an uninstall record, and less first-run
confusion for people who are not the author.

Three things argue against building one now:

- **The updater is built on the zip.** The update flow downloads
  `recipe-book-<version>-windows-x64.zip`, unpacks beside the install, and
  says to switch. An installed app cannot be updated that way — the updater
  would have to download and hand off an installer instead, the artefact
  convention would grow a third format, and `release_check` would need to
  know which flavour is running. Redesigning that mechanism before it has
  survived a single real release cycle would be churn on an unproven flow.
- **The scariest first-run hurdle is not the zip.** Windows SmartScreen warns
  on unsigned binaries either way; an unsigned installer removes nothing. The
  actual fix is a code-signing certificate, an ongoing cost that only makes
  sense once download counts justify it.
- **Nothing forces the timing.** The databases live in app support, not the
  install folder, so whenever the switch happens, existing users' data
  survives untouched.

## Decision

No installer yet. Revisit when **both** hold:

1. The in-app update loop has carried at least one real release end to end
   (publish, offer, download, install over the top), and
2. people other than the household are actually installing — issues from
   strangers, or meaningful release download counts.

`lib/app_version.dart` reserves 1.0.0 for "every planned feature built and
debugged"; the run-up to that release is the natural moment, and the installer
work then includes: the updater's installer-flavoured artefact and handoff, a
signing decision, and the Linux packaging question (AUR / Flatpak).

## Consequences

- Releases stay zip + APK, exactly as decision 0001 and the update plan
  assume.
- Until then, the README carries the "unpack and run" instruction, and
  SmartScreen warnings are answered with documentation rather than a
  certificate.
