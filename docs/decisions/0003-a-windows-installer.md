# 3. A Windows installer, and an updater that knows which copy it is

Date: 2026-09-06. Status: accepted. Supersedes [0002](0002-installer-timing.md).

## Context

Decision 0002 deferred the installer until two things held:

1. the in-app update loop had carried a real release end to end, and
2. people other than the household were actually installing.

**Both now hold.** The update loop has been exercised on a second device and
confirmed working, and the app has been requested by someone outside the
household.

Neither fact is visible from this repository, which is the main reason this
record exists. At the time of writing there is one release, no stars, no forks
and no issues from anyone, and the only download counts are the author's own. A
friend asking for a build leaves no trace in the GitHub metrics, and an update
installed successfully on another device leaves none either. Anyone — including
a future reader — who checks the numbers instead of asking will conclude the
conditions are still unmet and that this work jumped the gun. It did not.

0002 also said what the work would include when the moment came: the updater's
installer-flavoured artefact and hand-off, a signing decision, and the Linux
packaging question. Only the first is taken up here.

## Decision

Build the Windows installer, and split the update artefact in two.

**Releases publish both** `recipe-book-<version>-windows-x64.zip` and
`recipe-book-<version>-windows-x64-setup.exe`. They are not interchangeable,
because an artefact is not just the new bytes — it carries an installation
method. A zip's method is "unpack it and run it from there"; the setup exe's is
"close the registered install and replace it in place". Crossing them does not
fail loudly, it quietly produces a second copy:

- a zip unpacked beside an installed copy leaves the Start-menu entry and the
  uninstall record still naming the old version, and the new folder has no
  marker, so it goes on asking for zips forever — the divergence never heals;
- a setup exe run by an unpacked copy turns an update into a parallel
  *installed* copy, while the folder the user actually launches stays stale.

Publishing only one format does not avoid the problem. Always-zip leaves
installed users unable to really update; always-setup drags unpacked users into
a registered install at a path they never chose, which would end the "unpack and
run" route the README offers.

**A copy knows which it is by a marker file.** The installer writes an empty
`installed-by-setup` beside the executable; the zip never contains one, so
presence is the whole test. Asking "am I under Programs?" would test a
coincidence — a zip can be unpacked there, an installer can be pointed
elsewhere — while the marker is a fact recorded by whatever did the installing.
It also makes the routes self-correcting: run the installer over an unpacked
copy and it becomes an installed one from then on, with nothing to migrate.

**The APK is still signed with the debug key,** and is built on the author's
machine rather than in CI. A fresh runner generates its own random
`~/.android/debug.keystore`, so a CI-built APK would carry a different signature
from the copies already installed and Android would refuse the upgrade. Real
signing stays deferred: adopting a release key means an uninstall, and on
Android an uninstall takes the app's data with it.

## Consequences

- `UpdatePlatform` gains a third value rather than growing a separate flavour
  concept; `checkRelease` needs no new logic, because the suffixes cannot
  collide and `NotForThisPlatform` already covers a release that published only
  one of them. An installed copy offered a zip-only release is told there is
  nothing for it, which is correct — better than an update that breaks it in
  two.
- Releases are now built by `.github/workflows/release.yml` on a version tag,
  which is also the first time the Windows build has been automated at all. The
  APK step stays manual and is documented in that file's header.
- The installer's `AppId` GUID is fixed forever. Changing it would install each
  release beside the last instead of replacing it.
- Windows binaries are still unsigned, so SmartScreen still warns, exactly as
  0002 said. That remains a certificate question, not an installer one.
- Linux packaging is still unanswered.
