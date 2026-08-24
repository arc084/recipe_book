# Plan: the cloud folder on Android

**Status:** designed, not started.

## Context

Cloud-folder sync is desktop-only, and the Settings page says why: Android's
folder picker hands back a `content://` URI, which `dart:io` cannot open. The
phone — the device most likely to be pulled out in a shop with a stale grocery
list — is the one device that cannot join the folder.

The desktop design's core idea points at the fix. *The app never talks to
Dropbox, OneDrive, Drive or Syncthing — it reads and writes ordinary files and
lets whatever the user already runs do the moving.* On Android, the programs
that actually move files in the background — Syncthing, FolderSync, Dropsync —
all mirror a **real folder on device storage**. The cloud-provider document
gateways that SAF would unlock do not background-sync at all, so a full
`content://` IO layer would be a large amount of machinery for a folder the
sync model cannot use anyway.

So Android gets a real folder, and `dart:io` — and with it `CloudFolder`,
`CloudSync`, the one-writer-per-file layout and the `.part` rename contract —
works unchanged.

## The relay folder

One fixed location, offered rather than picked. The app's shared-media
directory becomes the `cloudFolderPath`, and `CloudFolder` lays out its
standard `recipe-book/` subfolder inside it exactly as it does on a desktop:

```
/storage/emulated/0/Android/media/<package>/      ← cloudFolderPath
  recipe-book/                                    ← what the mover syncs
    devices/<deviceId>.json
    photos/<sha256>
```

App-specific *media* storage: the app writes it with no permission, and —
unlike `Android/data`, which is walled off from other apps since Android 11 —
sync apps can reach it. Syncthing and FolderSync both already hold the storage
access they need for any folder they sync.

The path is derived, not hardcoded: take `path_provider`'s app-files directory
(`.../Android/data/<package>/files`), walk up to `Android/`, step across to
`media/<package>`. That derivation is a pure function —

```dart
/// The app's shared-media directory, derived from its app-files path.
/// Returns null when the layout is not the one Android documents — a vendor
/// surprise fills nothing rather than pointing sync at a guess.
String? androidMediaRelay(String externalFilesPath);
```

— so the string surgery gets unit tests instead of a phone.

**Recorded contingency:** if a vendor ROM refuses raw-path writes to the
app's own `Android/media` directory, the fallback is a one-method platform
channel to `Context.getExternalMediaDirs()`. Not built until a device shows
the need.

**Uninstall deletes the relay.** Acceptable, and worth saying in the UI: the
relay is a copy kept for the mover, regenerated from the databases and the
other devices' posts. Nothing lives only there.

## Settings on the phone

The cloud section stops saying "desktop only". On Android it shows:

- **Before setup:** one action — "Set up the relay folder" — which creates
  the folder, sets `cloudFolderPath` to it, and turns sync on.
- **After setup:** the full path of the `recipe-book` subfolder — the thing
  the mover should sync — with a **Copy path** button (it gets pasted into
  Syncthing or FolderSync, and nobody types that path by thumb), the existing
  Pause/Resume, and one line covering both movers: *point Syncthing at this
  folder, or have a sync app mirror it to OneDrive or Dropbox.*

Desktop behaviour is untouched. The platform gate moves from `dart:io`'s
`Platform` to Flutter's `defaultTargetPlatform`, because tests on a Linux
machine can override the latter and exercise the Android UI.

## What does not change

`CloudFolder`, `CloudSync`, device posts, content-addressed photos, `.part`
renames, and the sync trigger in `main.dart` — on focus, never on a timer,
never in the background. All of it runs as-is against the real path. That is
the entire payoff of choosing a real folder.

## Verification

- Unit tests over `androidMediaRelay`: the documented layout, an SD-card
  style path, a path that is not an app-files directory — the last two yield
  null, never a guess
- Widget tests with `debugDefaultTargetPlatformOverride`: the phone cloud
  section offers setup; tapping it creates the folder, sets the path and
  enables sync; the path and Copy button appear afterwards
- The existing cloud-sync tests already prove the engine on any real
  directory; nothing there changes
- On a phone, by hand: set up the relay, point Syncthing (and separately a
  OneDrive mirror app) at it, confirm posts flow both ways

## Out of scope now, planned later (low priority)

- **A user-chosen folder** via the system picker plus All Files Access
  (`MANAGE_EXTERNAL_STORAGE` — viable for a sideloaded app). Only worth its
  broad permission if the fixed relay location ever chafes.
- Any SAF/`content://` IO layer, for the reason in the context section.
