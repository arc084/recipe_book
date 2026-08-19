# Recipe Book

A private, local-only recipe manager for **Windows desktop and Android**, with
groceries, macro tracking and meal planning. No accounts and no cloud: the
library is a file on your own machine that syncs directly to paired devices over
the local network.

**Version 0.7.0.** 1.0 is reserved for the release where every planned feature is
built and debugged — the number is deliberately below it, and a test fails if the
major version is raised without that being true.

## Where things are

```
lib/
  app_version.dart      the version and build flavour shown beside the brand
  data/                 models, the two JSON databases, seed, migrations
  domain/               pure logic — macros, units, and the sync merge
  domain/sync/          stamps, tombstones, the merge engine, repair
  sync/                 the transport: protocol, server, client, discovery
  state/                AppState — every mutation and both databases
  ui/                   desktop screens, ui/mobile/ for the phone
docs/
  decisions/            why things are the way they are
  plans/                work that is designed but not built
test/                   139 tests, no network and no device needed
```

Two databases, deliberately separate and backed up independently: `library.json`
(recipes, meal types, aisles, groceries, plan) and `pantry.json` (ingredients and
their macros). Both live in the app-support directory, never in the repo.

## Building

Requires the Flutter SDK on `PATH`. `flutter doctor` should be clean for the
platform you are targeting.

```bash
flutter pub get
flutter test
flutter build windows --release
flutter build apk --release
```

The Windows build lands in `build/windows/x64/runner/Release/`. **The whole
folder is the app** — the `.exe` is 0.1 MB and will not run without the DLLs and
`data/` beside it.

For day-to-day work use `flutter run -d windows` or `flutter run -d <device>`,
which is slower to start but gives hot reload. To look at the phone layouts
without a phone attached:

```bash
flutter run -d windows --dart-define=MOBILE_PREVIEW=true
```

That swaps the frame to the Android one at the design's 428×908. It does not
emulate Android behaviour — only layout.

## Setting up a second machine

Things that are not obvious and cost real time the first time:

- **Windows desktop builds need Visual Studio** with the "Desktop development
  with C++" workload — Build Tools alone is not what `flutter doctor` looks for.
- **Windows needs Developer Mode enabled** or plugin builds fail with
  "Building with plugins requires symlink support".
- **Android needs its own SDK** with platform 36 and build-tools 36 — Flutter
  3.44 targets `compileSdk 36`. An SDK bundled with Visual Studio is likely far
  older and lives under `Program Files`, so every package install needs
  elevation. A user-local SDK at `%LOCALAPPDATA%\Android\Sdk` avoids that.
- **`sdkmanager --licenses` cannot always be driven from a script.** If piping
  `y` does not reach it, write the SHA-1 hash files into `<sdk>/licenses/`
  directly.

## Design

Built from a design handoff with two themes on identical layouts — **Nocturne**
(dark) and **Organic** (light). Nothing moves between them; only tokens change.

The tonal ramps **invert** between the themes, so a ramp step does not mean the
same thing in both: `neutral300` is a highlight on the dark ground and nearly
invisible on the cream one. Reach for the semantic roles in
`lib/theme/tokens.dart`, not a ramp index — and carry radius and spacing as theme
values too, since those are the biggest source of drift between the modes.

## The rule that governs the numbers

A recipe's macros are **always** calculated from its ingredients' linked pantry
items, scaled by quantity and basis. A recipe's own listed figures are shown only
during import, marked as about to be replaced. Where listed and calculated
disagree, calculated wins. An ingredient with no macros is flagged, never counted
as zero.

Counts, totals and step numbering must agree on every screen they appear on.
Treat a mismatch as a bug.
