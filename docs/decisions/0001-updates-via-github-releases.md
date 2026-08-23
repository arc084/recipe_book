# 1. In-app updates come from GitHub Releases

- **Status:** accepted; private-repo consequence overtaken by events (see addendum)
- **Date:** 2026-08-19
- **Version at time of decision:** 0.7.0

## Context

Recipe Book is private and unpublished. It is not in any store, the Windows build
is a portable folder, and the Android build is a sideloaded APK. So an update
button has no obvious place to check — the distribution channel has to be chosen
before the feature can exist.

The practical pain is one-sided: rebuilding the desktop is a single
`flutter build windows --release`, but getting a new build onto the phone
currently means plugging it in and running `adb install`.

## Decision

**Check GitHub Releases** on the project repository, compare the newest release
tag against `kAppVersion` in `lib/app_version.dart`, and offer the matching
artefact for the running platform.

## Consequences

### The repository is private — this must be resolved first

The repo is private, so the releases API needs authentication. **Do not embed a
token in the app.** A token shipped inside a binary is readable by anyone who
has the binary, and it would carry `repo` scope over the whole account.

Two acceptable ways out, to be decided before implementation:

1. **Publish releases from a separate public repository** that holds only built
   artefacts and no source. The update check is then unauthenticated. Keeps the
   source private, which was the point of the private repo; costs a second repo
   and a release step that pushes there.
2. **Ask the user for a fine-grained personal access token**, stored in the app's
   settings file, scoped read-only to this one repository. No secret in the
   binary, but the user has to create and paste a token, and `settings.json` is
   plain text on disk.

Option 1 is preferred: nothing secret exists at all, so nothing can leak.

### Other consequences

- The app gains its first outbound network call that is not a user-initiated
  recipe import. It must stay strictly opt-in — checked when the button is
  pressed, never on launch — because "offline by design" is a stated property of
  this app and a silent background check would quietly break it.
- Releases must be built and tagged deliberately. The version now lives in two
  places kept in step by a test (`pubspec.yaml` and `lib/app_version.dart`); a
  release tag becomes a third, and should be derived from them rather than typed.
- Android needs `REQUEST_INSTALL_PACKAGES` to hand an APK to the installer. This
  is a permission with real weight and Android still shows its own confirmation.
- The desktop cannot overwrite its own running folder. An update there has to
  either unpack beside itself and swap on next launch, or simply open the release
  page and let the user replace the folder.

## Alternatives considered

### Serve the APK over the LAN from the desktop

The phone already pairs with the desktop and trusts it over a signed transport,
so the desktop could hand over an APK directly. Very much in keeping with an
offline-by-design app, and it solves the actual pain without any internet.

Rejected because it only helps the phone — the desktop would still have no update
path — and it makes the desktop a build-distribution server, which is a larger
role than "the other device that holds your recipes". Worth revisiting if the
GitHub route proves awkward, since the transport it needs already exists.

### Show the version and do not fetch at all

Honest, zero infrastructure, no security surface. Rejected because it is not an
update button; it is a label, and the app already has one beside the brand.

## Addendum — 2026-08-23

Overtaken by events: the repository went public with the open-sourcing at
0.7.x, and the releases API on a public repository answers unauthenticated.
Neither way out is needed — no artefact repo, no token, nothing secret
anywhere, which is where option 1 was trying to get by other means. The
check calls the public releases API on this repository directly.
