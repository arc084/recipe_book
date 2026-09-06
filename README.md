# Recipe Book

My open-source **kitchen manager** for Windows desktop and Android: a group of
cooking tools that work together. I made this mostly for myself, but if you
happened to have stumbled upon this for whatever reason feel free to use as
you'd like.

- **Recipe book** — recipes grouped into components (Cutlets, Breading, Fry &
  finish), with continuous step numbering across them
- **Pantry** — what you have, by Fridge / Pantry / Freezer, with in-stock state,
  the loose names recipes use for each item, and the macros they carry
- **Groceries** — ordered the way you walk a shop, not the way recipes were
  written
- **Meal planning** — a week grid on the desktop, a day at a time on the phone
- **Macros tracking** — the number that ties the rest together

The pieces are connected on purpose. Macros come from your pantry items, not
from a recipe's own listed figures, so correcting one number in the pantry
updates every recipe drawing on it. Missing ingredients flow from a recipe into
groceries, and checking them off puts them back in the pantry.

Your data is **yours and local by default**: two plain JSON files on your own
machine. Cloud storage is an *optional hook* — point it at a folder your own
provider syncs, or don't, and nothing about the app changes. There are no
accounts, and there is no service to sign up to.

## Status

**0.7.2 — pre-1.0 and under active development.** 1.0.0 is reserved for the
release where every planned feature is built and debugged, so the version number
itself tells you the app is still being built. Expect rough edges; see
[Planned features and known bugs](#planned-features-and-known-bugs).

## Installing

Every release publishes both Windows artefacts on the
[releases page](https://github.com/arc084/recipe_book/releases):

| Artefact | What it does |
| --- | --- |
| `…-windows-x64-setup.exe` | Installs to `%LOCALAPPDATA%\Programs\Recipe Book` with a Start-menu entry and an uninstall record. No administrator prompt. |
| `…-windows-x64.zip` | The portable folder — unpack it anywhere and run `recipe_book.exe`. |

Take either. The app notices which kind of copy it is and asks for the matching
artefact when it updates, so an installed copy gets replaced in place and an
unpacked one gets a new folder beside it. What you should *not* do is unpack a
zip over an installed copy: you would end up with two, and the Start menu would
still point at the old one.

Either way the binaries are unsigned, so Windows SmartScreen warns the first
time. Your recipes live in `%APPDATA%`, not the install folder, so switching
between the two — or uninstalling — leaves them alone.

**Android** installs from `…-android.apk`, which is currently signed with a
**debug key**. That is fine for a build handed to you directly and not fine for
a stranger downloading it, so treat it as household software until that changes.

## Building

Needs the Flutter SDK (3.44+) on `stable`.

```bash
flutter pub get
flutter run -d windows     # or: flutter run -d <android-device-id>
```

Release builds:

```bash
flutter build windows --release      # build/windows/x64/runner/Release/
flutter build apk --release          # build/app/outputs/flutter-apk/
```

The Windows release is a **portable folder** — the `.exe` needs the DLLs and
`data/` beside it, so copy the whole `Release` directory rather than the
executable alone.

Windows desktop builds additionally need Visual Studio with the "Desktop
development with C++" workload. Android builds need the Android SDK
(compileSdk 36) and a JDK 17 or 21.

```bash
flutter test        # 288 tests, no device required
flutter analyze
```

## Where your data lives

Two JSON files, deliberately separate so a recipe library can be replaced
without touching the pantry that gives it its numbers:

| File | Holds |
| --- | --- |
| `library.json` | recipes, meal types, aisles, groceries, meal plan |
| `pantry.json` | ingredients, their macros and their other known names |
| `settings.json` | per-device settings — never synced |

They sit in the platform's app-support directory: on Windows,
`%APPDATA%\io.github.arc084\recipe_book\data`.

## Syncing

Direct device-to-device over the local network — no account, no server. Pairing
is a six-digit code typed on the joining device; requests are HMAC-signed with a
key both sides derive independently, so the code itself never crosses the
network. Conflicts resolve by newest-wins, and the one case timestamps cannot
settle — two copies changed at the same instant — is put to you on a review
screen.

## Planned features and known bugs

- **Cook mode voice commands and keep-screen-awake.** The UI lists both; neither
  works.
- **Sync reachability.** "Sync now" can only find a device that currently has
  the pairing dialog open.
- **Local-network sync only works on one network.** Syncing between networks
  over the internet is not built; a shared cloud folder is the way across.
- **Joining a cloud folder has no baseline step.** A fresh install pointed at an
  existing folder publishes its own seeded library, whose ids differ, and every
  device ends up with a duplicate of everything. Export from an existing device
  and import on the new one first.
- **Android reaches a cloud folder only through a relay.** Scoped storage means
  the app cannot open your provider's folder directly, so it keeps a relay
  folder that Syncthing — or any sync app — can carry to the desktop. You point
  that mover at it yourself, and uninstalling the app deletes the relay.
- Android release builds are signed with debug keys.

## Licence

[Apache License 2.0](LICENSE).

## Credits

The interface was designed with Claude Design and built with Claude Code. Fonts
are Inter, Figtree and Baloo 2, all under the SIL Open Font License and bundled
in `assets/fonts/`.
