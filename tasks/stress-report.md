# FolioKit stress test (2026-11-08)

The harness was a throwaway SwiftPM executable at `/Users/chenk/tmp/codex/folio-stress`, outside the repo. It depended on FolioKit by local path, with GRDB mirrored to the local checkout, so nothing was fetched from the network. It has been deleted.

- All data was synthetic: no user data, no real Arc files, no CloudKit server. The server was simulated in memory through `SyncStore`'s public API.
- Seeds are fixed (SplitMix64).
- Files changed: only `Packages/FolioKit/Sources/FolioKit/**` and this report. Line numbers below are for the current files.

## Summary

| # | Bug | Severity | Fix |
|---|---|---|---|
| B1 | A self or two-node cycle in Arc `childrenIds` crashed the import (unbounded recursion; stack overflow on the import's 512 KB `Task.detached` thread). | crash | `ArcSidebarImporter.swift:107-117,155,164,176` |
| B2 | An item listed twice, under two parents, or a duplicate space/container produced duplicate rows. Re-import then updated them on every run (sync churn). | data churn | same `visited` set; profiles deduped by id at `:101` |
| B3 | A 20 000-deep folder chain overflowed the stack. | crash | `maxDepth = 64` (`:114,324`); deeper levels are counted in `skippedItems` |
| B4 | `descendantIDs` recursed forever on a cycle. The orphan walk-up looped forever on a parent loop in the store. | crash / hang | iterative and cycle-safe at `:327`; bounded walk-up at `:266` |
| B5 | An Arc timestamp outside years 1–9999 (for example `createdAt: 1e20`) was stored as `""` or as year 33689. GRDB can't decode that row back, so every later read of `sidebarItem` threw and the whole sidebar stopped loading for good. | corruption | `ArcSidebarImporter.date(_:)` at `:317` |
| B6 | An Arc item without `createdAt` got `.now` on each import, so every re-import updated it. | data churn | `SidebarItem.adopt` keeps the stored `createdAt` (`:416`) |
| B7 | One CloudKit record this build can't read threw from `applyServerChanges` and lost the whole batch. The record might be from another app version (`kind: "note"`), miss `modifiedAt`/`profileID`/`name`/`url`, or have its type differ from its name. The N1 path then tears the engine down, and the next start re-fetches the same batch, so sync stopped for good. | sync wedge | records that can't be decoded are skipped (`SyncStore.swift:225`) |
| B8 | A CloudKit `NaN` position failed the NOT NULL constraint and threw the batch, with the same wedge as B7. | sync wedge | `CKRecord.double` returns finite values only (`SyncMapping.swift:125`) |
| B9 | A CloudKit date outside years 1–9999 corrupted the table as in B5. | corruption | `SyncableRecord.survivesStorage` (`SyncMapping.swift:53`), checked at `SyncStore.swift:225` |
| B10 | A folder peer entry this build can't read (unknown kind, wrong field type, missing field, date 1e20) threw on every folder pass. The peer's later files and the other entries in the same file never arrived. | sync wedge | entry skipped before anything is stored (`FolderSync.swift:163`) |
| B11 | A folder peer snapshot with `"seq": 9223372036854775807` trapped on integer overflow in `cursor + 1` (SIGTRAP, exit 133). Because the cursor is saved, this crashed every pass after that. | crash (loop) | `&+` at `FolderSync.swift:257,265-266` |
| B12 | After iCloud had drained the queue, choosing a sync folder sent nothing. A new peer joining the folder got 0 of 116 items. | data loss (library never shared) | `resetFolderSyncProgress` queues every record (`FolderSync.swift:178`) |
| B13 | Folders moved into each other on two devices (F1 into F2 on one, F2 into F1 on the other) converged to a parent loop. Both folders and everything inside them became invisible on every device, with both transports. | data loss | `FolioStore.breakParentLoops` (`FolioStore.swift:238`) cuts the loop at its smallest id, the same row on every device, and moves it into its space's pinned section (or the profile's favorites). Called from `SyncStore.swift:208` and `FolderSync.swift:140`. |

Build check: `xcodebuild -project Folio.xcodeproj -scheme Folio-macOS -derivedDataPath build/agent-stress -allowProvisioningUpdates build` → **BUILD SUCCEEDED**, with no warnings in the changed files.

## Scenario 1: cross-process concurrency

- **Setup:** three separate worker processes, each with its own `DatabasePool` on one file. The configuration matches `FolioStore.onDisk`: `busyMode .timeout(5)`, suspension notifications, WAL. Each ran for 30 s with a write thread and a read thread. Worker 0 opened with `migrate: true`; worker 2 reopened its pool every second, like an extension launching.
- **Write ops:**
  - tabs: new tab, close/archive, move or reorder with midpoint positions, rename (Unicode)
  - spaces: new space, delete or reorder
  - folders: new folder, toggle
  - store-wide: `archiveStaleTabs`, `recordVisit`, `rebalancePositions`, plus `applyServerChanges` of `srv-` records
- **Read ops:** `sidebar()`, `pendingSyncChanges()`, `history`, `archivedItems`.
- **Result:**
  - Before the fixes: about 15 800 ops (about 7 400 reads), 0 errors.
  - After the fixes: 16 674 ops (7 859 reads), **0 errors** (no SQLITE_BUSY).
  - `PRAGMA integrity_check` = ok. 4 927 synced rows, **0 missing from `syncPending`**, 0 leftover `syncSuppress` rows.
- **Why it holds:** GRDB opens write transactions IMMEDIATE (`Database.beginTransaction`), so the read-then-write paths (`recordVisit`, `archiveStaleTabs`) can't hit an un-retryable SQLITE_BUSY lock upgrade.
- No bugs found.

## Scenario 2: scale

- **Data:** 100 spaces across 3 profiles, 20 000 sidebar items (about 10 % folders, nested), 50 000 history visits, 5 000 archive items. On-disk pool, release build, best of 3 runs.
- **Times:** after the fixes. Before them, the 400-record `applyServerChanges` batch took 92 ms; the rest was unchanged within noise.

| Call (where the apps run it) | ms |
|---|---|
| `sidebar()` full fetch (ValueObservation, off main; but **main** in `ArcImportView.swift:245` and the share extension) | **100** |
| `children(of:)` tree for one space / all 100 spaces (main, views) | 0.7 / 54 |
| `historySuggestions` per keystroke (main, CommandBar) | 15–17 |
| `history(matching:)` miss / default (main, iOS Library) | 11 / 0.9 |
| `recordVisit`, `archivedItems`, `Sidebar.upsert` (main) | 0.2 / 1.8 / 0.9 |
| `archiveStaleTabs`, 3 196 stale Today tabs (main, `MacModel.archiveStaleTabs`, `AppModel`) | **160** (2.3 when nothing is stale) |
| `queueAllForUpload` (main, `CloudKitSync.reuploadEverything`) | 28 |
| `purgeTombstones` with about 5 700 synced tombstones (main, `CloudKitSync.startEngine`) | **53** (19 when there is nothing to purge) |
| `applyServerChanges`, 400-record batch (main: `CloudKitSync.handleEvent` is `@MainActor`) | **114** |
| `didSave`, 400-record batch (main) | 32 |
| `cloudRecord(for:)` per record (main, batch provider) | 0.083 (about 33 per 400) |
| Folder pass: first flush of the whole library / nothing new / new peer bootstrapping (off main) | 149 / 1.5 / 13 |

Main-actor calls over 50 ms (flagged; not changed, since they need app-side or concurrency changes):
1. `CloudKitSync` applies every fetched batch (114 ms per 400 records), `didSave` and `purgeTombstones` on the main actor, because the class is `@MainActor` and the store calls are synchronous. A first sync of a 20 000-item library causes dozens of 100 ms hitches. A fix would run the store calls off the main actor, for example with a `nonisolated` helper or `Task.detached` around the `FolioStore` calls in `handleEvent`.
2. `archiveStaleTabs` after a long absence: 160 ms for 3 200 tabs on activation (`MacModel.swift:89`, iOS `AppModel.swift:109`). Steady state is 2 ms.
3. `store.sidebar()` called synchronously on the main actor: 100 ms at 20 000 items (`ArcImportView.swift:245`; share extension `ShareModel.swift:27,57`). Fetching only `Profile` there would be cheap.
4. `purgeTombstones` at engine start: 53 ms with a large tombstone backlog.

Note: the scale run's own folder-pass line ("B has 52 live items") shows B12 in the scale data. The scale run drains the queue through the CloudKit API and then passes without `setFolder`. The fixed path goes through `resetFolderSyncProgress`, which is the B12 evidence below.

## Scenario 3a: sync convergence fuzz (CloudKit model)

**How the simulation works**
- **Server:** an in-memory zone with `ifServerRecordUnchanged` semantics. A save with no tag or a stale tag gets `serverRecordChanged` with the server copy; a tag on a deleted record gets `unknownItem`. Real change tags are set on the `CKRecord`s, so system fields round-trip through `syncRecordMeta`. Changes come from a log.
- **Device:** each device mirrors `CloudKitSync` exactly: `hand()`, `nextRecordZoneChangeBatch` → `cloudRecord(for:)`, and `handleSent` → `didSave` / `didDelete` / `clearSystemFields` / conflict `applyServerChanges` with requeue.
- **Steps:** 600 per run: local ops (the scenario 1 mix plus folder moves), sends and fetches on random devices. Then rounds until every device's queue is empty and every device has the latest token.

**Chaos mode**
- Fetch batches are delivered in random order, with duplicate batches.
- A lost state save re-fetches from an older token.
- Local edits land while a batch is in flight.
- Rarely, a zone reset (`resetSyncState(reuploadAll: true)`).

**Purge mode** runs `purgeTombstones` against concurrent edits.

**Checks**
- All devices are identical, and identical to the server's records.
- An oracle built from every device's local-write journal (triggers that skip `syncSuppress` writes):
  - The row's final `modifiedAt` equals the newest local write's (no lost edits).
  - Deleted if and only if the newest write was a delete (no resurrected deletes, no edit lost to an older delete).
  - Rows only go missing through a purge.
- The oracle runs in the configs without clock skew. With skew, LWW by timestamp is the documented rule, so only convergence is checked there.
- New: no live item may sit in a parent loop.

| Config (20 seeds each) | Result |
|---|---|
| 3 devices, clean | **20/20 converged**, oracle holds, 0 loops |
| 3 devices, chaos | **20/20 converged**, oracle holds, 0 loops |
| 3 devices, chaos + clock skew (−7 s / 0 / +7 s) | **20/20 converged**, 0 loops (oracle not applied) |
| 2 devices, chaos + purge | **20/20 converged**, oracle holds, 0 loops |
| 3 devices, chaos + skew + purge | **20/20 converged**, 0 loops (oracle not applied) |

Typical run (seed 0, chaos): 279 records, 821 server changes, 134 conflicts, 2 rounds to quiescence. Seed 0 of the purge configs hard-deleted 21 and 29 records.

**Before the fixes:** all 100 runs converged with the oracle holding. One false alarm turned out to be correct behavior. The harness first used a simulated clock 40 days in the past, while `applyServerChanges` stamps rebalances with the real `Date.now`. A device that saw a newer rebalance and then deleted the row correctly won, causally. The harness now uses real time.

**B13 (targeted check, `loops`):**

| | CloudKit model | Folder transport |
|---|---|---|
| Before | `F1→F2`, `F2→F1`; 3 live items in a loop on both devices; identical; all invisible | the same |
| After | `F1→personal-pinned`, `F2→F1`; 0 in a loop; identical | the same |

## Scenario 3b: folder transport fuzz

**Setup:** 3 devices (in-memory stores) sharing a temp folder, run through `runFolderSyncPass`. 500 steps per run. The placeholder mode hides random peer files as `.<name>.icloud` and restores them later.

**Checks:**
- All devices are identical after quiescence.
- A late joiner bootstrapping from snapshots and logs gets the same number of live items.
- No item sits in a parent loop.

| Config (10 seeds) | Result |
|---|---|
| 3 devices, clean | **10/10 converged**; late joiner identical; 0 loops |
| 3 devices, placeholders | **10/10 converged**; late joiner identical; 0 loops |

**B12 evidence** (`folderAfterCloudKit`): device A with 116 live items and 18 spaces uploads everything to the fake iCloud server, so its queue holds 0. A then calls `resetFolderSyncProgress` and passes; new peer B passes.
- Before: B had **0 items, 0 spaces**.
- After: B has **116 items, 18 spaces**.
- Regression run with folder moves: 127 of 127 items, 25 of 25 spaces.

## Scenario 4: Arc import fuzz

**Input:** synthetic `StorableSidebar.json` built per `ArcSidebarImporter`'s schema:
- `sidebar.containers[1]` with alternating id/object arrays
- `spaceItems` / `topApps` containers, tabs / `list` folders / `splitView`s / easels / `arc://` tabs
- default and custom profiles on two machine IDs
- emoji / SF Symbol icons and `windowTheme` with `background.single`
- `StorableWindows.json` `expandedItems` and `Local State` names

Parse and import ran on a thread with a 512 KB stack (like the app's `Task.detached`), with a 30 s hang watchdog. Each importable input was imported into a fresh store, then re-imported 4 more times.

**Checks:**
- Rounds 2–5 have 0 inserted and 0 updated.
- Live counts are identical over all 5 imports.
- Every pending row still builds a `CKRecord`.
- `archiveStaleTabs` and `sidebar()` still read.

**Inputs (3 236):**
- Baseline: 6 spaces, 400 items.
- 35 targeted attacks: self cycle, two-node cycle, a 20 000-deep folder chain, a child under two parents and twice in one, a duplicate item id with other data, a duplicate space sharing containers, a favorites container also used as both sections.
- 200 truncations of the sidebar and windows files.
- 3 000 random mutations, 1–6 each. Mutations: delete key, wrong type, extra key, duplicate array entry, ±1e300 / 1e20 / Int.max numbers, NUL, RTL override, 10 KB and combining strings, ids pointing at other ids, `../../x` profile directories, and mutated windows / Local State.

**Results:**

| | Before fixes | After fixes |
|---|---|---|
| Crashes | SIGSEGV (stack overflow) on the first self-cycle input (B1); B3 and B4 have the same cause | **0 crashes, 0 hangs, 0 non-idempotent, 0 corruptions** (1 060 imported, 1 902 rejected, 274 mutations not encodable as JSON and skipped) |
| Non-idempotent re-imports | 9: the 20k chain updated 64 rows per run; mutations without `createdAt` updated 1 row per run (B6) | |
| Corruptions (store unreadable) | 2, for example `createdAt` stored as `""`, after which `SELECT … FROM sidebarItem` throws "could not decode Date" (B5) | |
| Accepted / rejected | 999 imported, 1 950 rejected | |

GRDB date range (probe): years 0001–9999 round-trip. Year 10240 or later, or ±1e20 s, is stored (as `"10240-01-28…"` or `""`) but can't be decoded. `-6.4e10` s comes back as a different date.

## Scenario 5: untrusted input

**CloudKit records** (each in a batch between two good records; before → after):
- **Threw before** (B7 / B8 / B9): missing `modifiedAt`; unknown `kind` "note"; `kind` as a number; missing `profileID`; `modifiedAt` as a string; record type ≠ record name; archive without `url`; profile without `name`; NaN position.
- **Accepted before but unreadable after storing:** `createdAt` in year 11507; `modifiedAt` 1e20.
- **After:** every case returns normally, the good records apply, and the library still reads and uploads.
- **Already fine:** position as a string (defaults to 0), unknown record type, a name with no type, an empty id, `url` not a string, a 2 MB title, `distantFuture` `modifiedAt`. `distantFuture` wins LWW forever; that is documented LWW, not a crash.

**Folder files from a peer:**

| Input | Before | After |
|---|---|---|
| Unknown kind next to a good entry in the same file | every pass threw; the good entries in that file and the next file were never applied | the bad entry is skipped; the good entries and the next file apply |
| Position as a string; missing `modifiedAt` | every pass threw | entry skipped |
| `createdAt` 1e20 | would corrupt the table | entry skipped |
| Snapshot `seq` = Int.max | SIGTRAP on every pass | passes complete |
| Unknown entry type; hard delete of a starter row | | applied as designed |

Known limit, not changed: a garbage or seq-mismatched peer log file can't be told apart from one still downloading. That peer stays "waiting" (retry every 5 s) until it writes its next snapshot (at most 50 logs later), and then readers resume from the snapshot. Folio writes atomically under file coordination, so only a damaged or foreign file can cause this.

**Force unwraps, preconditions and array indexes in FolioKit:**
- `ChromiumSafeStorage.swift:34`: `precondition` on PBKDF2 with fixed inputs. Not reachable from input.
- `BookmarkImporter.swift:293`: `try!` on a constant regex.
- `stack[…]` / `top.remove(at:)` in the Netscape parser: always valid, since the stack keeps at least one entry and the index is recorded at append.
- `sections(of:)` `list[i + 1]` is bounded by `count - 1`.
- `StarterLibrary.swift:66`: `URL(string:)!` on constants.
- `breakParentLoops`: `loop.min()!` runs on a non-empty array.
- The only reachable traps were B1, B3, B4 and B11, all fixed.

## Not covered or left as is
- Real CKSyncEngine scheduling, push and the iOS suspension window (N1) are not modeled. The fake engine follows the delegate code paths.
- **Orphans under a parent deleted on another device:** a tab added into a folder that another device tombstoned stays live but invisible. Apps never tombstone folders today; only Arc re-import (m7) does, so the fuzz found 0. Left as the existing N7-style limitation.
- **Concurrent moves breaking a loop:** when another device's move closes a loop, the cut row moves to the end of its space's pinned section. With three or more devices racing, more than one row of the same loop can be cut. That is still visible and converged.
- **Main-actor timings over 50 ms (scenario 2):** flagged only, because the fixes are in `CloudKitSync`'s actor isolation and in app code.

## Follow-up: main-actor hitches (2026-11-08)

The four calls flagged above over 50 ms now run on the database's queue instead of the main thread:
`applyServerChanges` and `purgeTombstones` (`SyncStore`), `archiveStaleTabs` (`Library`) are `async` and use
GRDB's async `writer.write`; `FolioStore.loadSidebar()` is an async read for the Arc import view, the share
extension and iOS `reloadSidebar`. CKSyncEngine awaits `handleEvent`, so fetched changes are still stored before
the next event (and its state save). Verified on the simulator: 3,000 stale Today tabs archived at launch with the
UI responsive and `integrity_check` ok; a row inserted by another process while the app was backgrounded appears on
return. Not re-timed at 20k items (the harness was removed); the main thread no longer runs these transactions.
