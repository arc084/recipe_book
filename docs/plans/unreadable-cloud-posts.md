# Plan: say so when a cloud post cannot be read

**Status:** planned, not started.

## Context

A cloud sync that could not read another device's post currently reports success.
Observed on the desktop against a real OneDrive folder on 2026-08-24.

`CloudFolder.readOthers` already does the careful thing: every post is read
inside its own `try`, and a failure becomes a `CloudSkip` rather than taking the
whole run down. That value is carried faithfully into `CloudOutcome.skipped` —
and then dropped. It reaches neither `isEmpty` nor `message`:

```dart
bool get isEmpty =>
    received == 0 && photosPulled == 0 && photosPushed == 0 && !unavailable;
```

An unreadable post leaves `received` at zero, so the run looks idle. What the
user gets:

| Situation | What the app says today |
| --- | --- |
| Auto-sync on launch or focus | nothing at all — `quietWhenIdle` returns first |
| Sync now, one post unreadable | *"Already up to date."* |
| Sync now, the only post unreadable | *"Nothing else has synced to that folder yet."* |

The last is the worst of the three: the file is sitting in the folder, and the
app says nothing has arrived. The skip does reach `debugPrint` in `runCloudSync`,
which is invisible in a release build.

The in-app updates plan already settled this principle for the same reason:
*"a failed check that looks like 'up to date' is worse than no button"*. A sync
that could not read everything must not claim it is up to date.

## The tension this has to resolve

The reason it was left at `debugPrint` is good, and any fix that ignores it will
be worse than the bug. The comment says it plainly:

> Usually another device mid-write, which resolves itself.

That is true. `readOthers` sees a partial file whenever another device is mid-write
or the provider is mid-download — the existing test names exactly that case. Those
skips heal on the next run, seconds later. A snackbar on every one would nag on
app focus about a race that has already resolved, and the user would learn to
ignore the message that matters.

So the fix is not "report skips". It is **never claim to be up to date when you
were not**, while staying quiet about a race that fixes itself.

## Design

### 1. A skip is either transient or permanent

They are not the same event and should not read the same way.

- **Permanent** — `PostTooNewException`. A device is running a newer build. This
  never heals on its own and the user must act, so it is said the first time, on
  any path, quiet or not.
- **Transient** — a parse failure or an I/O error. Might be a mid-write race,
  might be a file the provider has not delivered. Indistinguishable at the moment
  it happens; only time tells them apart.

Add the classifier to `CloudSkip`, beside the error it already holds, rather
than making callers pattern-match on exception types:

```dart
bool get isPermanent => error is PostTooNewException;
```

### 2. `isEmpty` must account for skips

The one-line correctness fix, and the reason the quiet path currently swallows
everything:

```dart
bool get isEmpty =>
    received == 0 &&
    photosPulled == 0 &&
    photosPushed == 0 &&
    skipped.isEmpty &&
    !unavailable;
```

A run that skipped something is not an empty run. On its own this makes the app
honest but noisy — step 3 is what buys the quiet back.

### 3. The quiet path waits for a second opinion

`runCloudSync` is called two ways, and they want different manners. The existing
comment has it right: *"one the user asked for should always answer."*

- **Sync now** (`quietWhenIdle: false`) — always says what happened, including a
  transient skip. The user asked; answer honestly.
- **Launch and focus** (`quietWhenIdle: true`) — speaks about a permanent skip
  immediately, but about a transient one only when the *same file* was skipped
  on the previous run too. One mid-write race stays silent. A file that is still
  unreadable a run later is not a race, and is worth saying.

Hold the previous run's skipped filenames in memory on `SyncService`, not in
`settings.json`. A race resolves within one focus cycle, so surviving a restart
buys nothing and it is not worth a schema change:

```dart
/// Filenames skipped by the previous run, so a skip that repeats can be told
/// apart from a device caught mid-write. Deliberately not persisted.
Set<String> lastSkipped = const {};
```

### 4. Wording

`message` gains a branch before the `isEmpty` one, so a skip is never described
as being up to date. Plain, and never blames the user's provider by name — the
app cannot actually know it was OneDrive's fault:

- permanent — *"A device is running a newer build than this one. Update here to
  sync with it."*
- transient, nothing else moved — *"Could not read 1 device's copy. It may still
  be arriving."*
- transient, alongside real traffic — append to the existing `Synced · …` line:
  *"Synced · 3 in · 1 copy unreadable"*

Follow `_photos` for pluralisation rather than inventing a second style.

## Verification

`test/cloud_sync_test.dart` already builds the two cases this needs — a
truncated post and a `postVersion` from the future — so the tests are extensions
of what is there, under the existing `a folder is not a database` group:

- a skipped post makes the outcome **not** `isEmpty`
- `message` never says "already up to date" when `skipped` is non-empty
- `message` never says "nothing else has synced" when the only post was skipped
- a `PostTooNewException` reads as permanent; a truncated file does not
- a `.part` file still produces no skip at all — the existing guarantee, which
  this must not turn into a false alarm
- a transient skip seen once is quiet on the focus path, and speaks on the
  second consecutive run naming the same file
- a run that skipped a post still writes its own post — reporting a skip must
  not become a reason to stop publishing

On the desktop, against a real folder: rename a device post to invalid JSON,
open the app, and confirm it does not claim to be up to date.

## Not in scope

Retrying a skipped post inside one run. If a file is mid-write, the next sync is
soon enough, and a retry loop against a syncing folder is a good way to read a
second partial write.
