# Plan: the update button in Settings

Follows [decision 0001](../decisions/0001-updates-via-github-releases.md).
Nothing here is built yet.

## Blocked on one decision

Pick how the private repository is handled — a **separate public artefact repo**
(preferred) or a **user-supplied read-only token**. See the decision record. The
rest of this plan is the same either way; only `_releasesUri` and whether an
`Authorization` header is sent change.

## Shape

```
lib/update/
  release_check.dart    // pure: parse the API response, compare versions
  updater.dart          // fetch, download, hand off to the platform
```

Keep the comparison pure and in its own file, the way `lib/domain/` is. It is the
part with the edge cases and the part worth testing; the download is plumbing.

```dart
/// A release newer than what is running.
class AvailableUpdate {
  final String version;      // "0.8.0", tag stripped of any leading v
  final String notes;        // the release body, shown before downloading
  final Uri artefact;        // the asset matching this platform
  final int sizeBytes;
  final DateTime publishedAt;
}

/// Compares two semantic versions. Returns null when [latest] is not newer.
/// Pure, so the awkward cases get tests rather than a live API call.
AvailableUpdate? newerThan(String running, Map<String, dynamic> releaseJson);
```

Cases the tests must cover, because each has bitten someone:

- `0.10.0` is newer than `0.9.0` — string comparison gets this wrong
- `v0.8.0` and `0.8.0` are the same version
- equal versions offer nothing
- a **lower** release than the running build offers nothing, so a laptop running
  an unreleased local build is not told to downgrade
- a release with no artefact for this platform is reported as "not available for
  Windows/Android", not silently treated as up to date
- a malformed or empty response fails visibly rather than looking up to date

## Artefact naming

The check has to find the right asset. Settle a convention now and have the
release step follow it:

```
recipe-book-0.8.0-windows-x64.zip
recipe-book-0.8.0-android.apk
```

## Platform behaviour

**Android.** Download to app storage, then hand the file to the system installer
via an intent. Needs `REQUEST_INSTALL_PACKAGES` in the manifest and a
`FileProvider` — an APK cannot be handed over as a raw `file://` path on modern
Android. The system shows its own confirmation, which is correct and should not
be worked around.

**Windows.** A running exe cannot replace its own folder. Simplest honest
behaviour: download the zip, unpack beside the current install, and tell the user
to close the app and run the new folder. Do not attempt a self-replacing updater
— that is a large amount of machinery for a two-device household.

## Where it lives

Settings, next to the version. The button reads **"Check for updates"** and
states the running version beside it. It must never check on launch: this app is
offline by design, and a background call would quietly make that untrue.

States to handle, all in the same row rather than a dialog:

- idle — "Version 0.7.0 · check for updates"
- checking — a spinner, cancellable
- up to date — "0.7.0 is the newest release", with when it was checked
- available — "0.8.0 is available (12 MB)", the release notes, and Download
- downloading — progress, cancellable
- failed — the reason in plain words, and the failure must be visible; a failed
  check that looks like "up to date" is worse than no button

## Verification

- Unit tests over `newerThan` for every case listed above — no network
- A fake release payload checked into `test/fixtures/`
- On the phone: build 0.7.0, publish a 0.8.0 release, confirm it is offered,
  downloads, and installs over the top without clearing app data
- Confirm a **debug** build still reports its own version honestly rather than
  claiming to be the release
