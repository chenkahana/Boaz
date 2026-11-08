# Review, round 3: checking the round 2 fixes

Scope: findings M1–M4 and m1–m8 from `tasks/review-round2.md`, checked against the current (uncommitted) code at the locations cited in the "Round 2 fixes" sections of `tasks/sync-report.md` and `tasks/arc-import-report.md`. Read-only. Nothing was built or run. GRDB's suspension behavior was checked in its source (`build/agent-sync/SourcePackages/checkouts/GRDB.swift/GRDB/Core/Database.swift:1174-1445`).

Counts: Critical 0 · High 1 · Medium 4 · Low 5

## Verdict per round 2 finding

| # | Verdict | Note |
|---|---|---|
| M1 | FIXED | `dataStoreID` is no longer written (`SyncMapping.swift:133-138`). It is kept on every incoming copy (`SyncStore.swift:224`, `FolderSync.swift:162`), and the starter profile is stamped `starterStamp` (`StarterLibrary.swift:20`). No path that overwrites an existing row's `dataStoreID` was found. The 3-way merge is also safe: when the base holds the derived id, server and local are equal after `keepDeviceLocalFields`, so the merge keeps the local value. See N9 for a side effect of the derived id. |
| M2 | FIXED (data-loss question: no misfire found) | Upgrade from a build before the fix: `cloudUser` is nil, so nothing is wiped. The key is just recorded, and `uploadAll` matters only when there is no saved engine state (`CloudKitSync.swift:87-96,161`). `userRecordID` failure: returns before the comparison (`:82`). Temporary or undetermined account status: never reaches the comparison (`:97-106`). Sign-out keeps data and clears only the engine state (`:257-262`). The wipe happens only when the stored and current record names differ, or on the engine's own `.switchAccounts`. New issues: N2, N9. |
| M3 | PARTIAL | Rows tombstoned in Folio are skipped (`ArcSidebarImporter.swift:232`). After the tombstone is purged (30 days), the row comes back (N3). Edits made in Folio to Arc-derived rows (rename, move) are still reverted (N10). |
| M4 | FIXED, with a regression | Busy timeout, migrations only in the app, and the extension hand-off through `syncNow` are all in place (`FolioStore.swift:9-31`, `CloudKitSync.swift:116`). Suspending the database while CKSyncEngine is running loses server changes (N1). |
| m1 | FIXED | `startedFresh` ignores the first `.signIn` (`CloudKitSync.swift:160,255`). `queueAllForUpload` keeps meta and bases (`SyncStore.swift:79-81`). |
| m2 | FIXED | Pending engine state is removed, and the flag survives `resetSyncState` (`SyncStore.swift:72-73`). Sync cannot get stuck off for good: both Sync Now buttons pass `userInitiated: true` (`LibrarySync.swift:84`, `LibrarySheet.swift:192`, `LibraryViews.swift:97`), and `deleteSyncedLibrary` clears the flag on an account switch. Each device that saw the purge needs its own Sync Now. That is by design. |
| m3 | FIXED | `CloudKitSync.swift:122,125`. |
| m4 | FIXED | Generation check at `LibrarySync.swift:92-96`. The synchronous prefix of `FolioSync.setFolder` (`FolderSync.swift:411-421`) saves the bookmark before its first await, and `retireFolder` then waits for the pass and deletes the bookmark. No orphan is left. |
| m5 | FIXED | `prepareSync()`/`backgroundSync()` (`AppModel.swift:86-102`). |
| m6 | PARTIAL | Covered only while the engine is running. See N8. |
| m7 | PARTIAL | Orphans under a removed folder are reparented. Orphans under a removed space are still left invisible (`ArcSidebarImporter.swift:286`, N7). The new reparenting also moves pinned content into Today, where it is auto-archived (N5). |
| m8 | PARTIAL | The favorites ping-pong is fixed (`foreignFavoritesIDs`, `:89-94,252`). The profile id collision between two Macs is not fixed, and a new flip-flop was introduced (N4). The two Macs' favorites containers now both stay live under one profile (N6). |

---

## High

### N1. The iOS app suspends the database while CKSyncEngine keeps running, so server changes fetched in that window are dropped for good
- `Apps/iOS/App/FolioApp.swift:27-29` suspends as soon as the scene phase is `.background`. `AppModel.swift:101` suspends again after a push or refresh sync. Neither stops the engine, which has `automaticallySync = true` (`CloudKitSync.swift:157`) and can still deliver events while the process runs. With GRDB suspension, every write throws `SQLITE_ABORT "Database is suspended"`; only WAL reads are allowed (GRDB `Database.swift:1398-1441`).
- Failure: the engine delivers `.fetchedRecordZoneChanges` while the database is suspended. `applyServerChanges` throws, and the event handler only calls `report(error)` (`CloudKitSync.swift:295-300`). The engine's in-memory state has already advanced its change token. The `.stateUpdate` save fails too (`:247-248`), but the next `.stateUpdate` after resume persists the advanced token. Those records are never fetched again, so this device permanently misses other devices' edits, new tabs and deletions, until a record changes again or the sync state is reset.
- Ways in:
  1. The user backgrounds the app while a `syncNow` or an automatic fetch is running (the suspension happens right away).
  2. A push and a background refresh overlap, and the first `backgroundSync` to finish suspends while the other is still fetching. Suspend and resume are not reference-counted.
  3. The engine's own automatic sync runs after `backgroundSync` has already suspended the database.
- `.sentRecordZoneChanges` in the same window loses `didSave` (no change tag stored). This recovers through a conflict round trip, so no data is lost there.
- Fix: don't let fetched changes be acknowledged while writes are impossible.
  - Simplest: in the `.fetchedRecordZoneChanges` (and `.fetchedDatabaseChanges`) handler, when `applyServerChanges` throws, tear down the engine and `clearSyncEngineState()`, so the next start re-fetches from scratch. Or keep the last persisted serialization and restart from it.
  - Better: suspend only when the app is really about to be suspended. Wrap background work in `beginBackgroundTask`, suspend in its expiration handler, call `engine.cancelOperations()` before suspending, and count resumes and suspends so overlapping background syncs don't suspend each other.

## Medium

### N2. On an account switch, the starter library is queued and uploaded into the new account before its library is fetched
- `CloudKitSync.swift:227-231`: `startClean()` deletes everything and then calls `StarterLibrary.seedIfEmpty`. That is an ordinary write, so the `v3-sync` triggers queue `default`, `personal`, `personal-pinned` and `personal-today` in `syncPending`. On the `.switchAccounts` path (`:263-267`), `deleteSyncedLibrary` also deletes the `cloudUser` key (`SyncStore.swift:97-99`). So the following `start()` sees `previous == nil` and takes `uploadAll: true` (`:96`), which queues them again.
- Failure: account B's library no longer has "Personal". For example, B imported from Arc, `finishSetup` tombstoned the empty Personal space, and `purgeTombstones` hard-deleted it on the server 30 days later. After a switch to B on this device, a new empty Personal space and its containers are created in B's iCloud and appear on all of B's devices. When B's server still has those records, the `starterStamp` LWW correctly lets the server win, so there is no harm in that case.
- Fix: in `startClean()`, don't seed. Let the normal launch flow seed after the first fetch (`AppModel.start`/`MacModel.start` already do `isEmpty → sync.start → seedIfEmpty`), or seed inside `syncSuppress` so the rows aren't queued. Also keep `cloudUser` across `deleteSyncedLibrary` (or set it to the new user in the `.switchAccounts` branch), so both paths behave the same.

### N3. M3 holds only for 30 days: after the tombstone is purged, re-import resurrects the tab or folder
- `ArcSidebarImporter.swift:227-232`: the guard checks only `existing.deletedAt`. `SyncStore.swift:261-272` hard-deletes synced tombstones older than 30 days (on every engine and folder start), and the deletion is synced. After that, `existing == nil` and the row is inserted again with `modifiedAt = now`.
- Failure: import, Today tabs auto-archive (tombstoned), 30+ days pass, the user re-imports, and the tabs are back on every device. The next activation archives them again and creates duplicate `ArchiveItem`s. This is the original M3 failure on a delay. Imported Today tabs keep Arc's old `lastActiveAt`, so they are archived on the first activation.
- Fix: exempt `arc-` rows from `purgeTombstones` (they are small). Or keep a device-local, unsynced set of Arc ids removed in Folio, and skip them on import.

### N4. m8 profile ids: each Mac's own profile directory still gets the plain id, and the new suffix makes the same space flip between two profiles on each import
- `ArcSidebarImporter.swift:98-111,162`: an id is suffixed only when the directory is not local to the Mac doing the parse.
  - Collision not fixed: Mac A's "Profile 1" and Mac B's different "Profile 1" are each local on their own Mac, so both import as `arc-profile-profile-1`. This is the exact case in m8.
  - New flip-flop: a space whose profile directory is local on Mac B but not on Mac A gets `arc-profile-profile-1-<B>` when A imports, and `arc-profile-profile-1` when B imports. Space and item ids (`arc-<arcID>`) are the same on both Macs, so each import updates `profileID` to its own value. With sync on, the space moves between two Folio profiles, and so between two WebKit stores (logins), every time either Mac imports. Each Mac's tombstone pass is scoped to its own `profileIDs`, so the other variant's profile and its favorites container are left behind.
  - This relies on the premise m8 and its fix both rely on: each Mac resolves a different `localMachine`.
- Fix: when a ref has a `machineID`, always include it in the profile id, and keep the plain id only for machine-less refs. Migrate existing plain-id rows once: on re-import, re-point rows of the local machine's plain id to the suffixed one, keeping that profile's `dataStoreID`.

### N5. m7's reparenting moves pinned Folio-made rows into Today, where they are auto-archived
- `ArcSidebarImporter.swift:266-275`: every orphan with a `spaceID` goes to the space's `unpinned` container, including orphans whose removed parent was in the pinned section. `Library.swift:79-93` auto-archives any tab that is a direct child of an `unpinned` container and has `COALESCE(lastActiveAt, createdAt)` older than the interval (default one day).
- Failure: the user adds a tab in Folio to a pinned folder that came from Arc. Later the folder is removed in Arc and the user re-imports. The tab moves to Today, and on the next activation it is archived on every device. Pinned items are documented as never archived (`Library.swift:77`).
- Fix: resolve the orphan's section by walking up to its root container. Reparent to the same space's `pinned` container for pinned-section orphans, and to `unpinned` only for Today ones.

## Low

### N6. With favorites imported on two Macs, both containers stay live under one profile, and the UI shows only one
- After the m8 fix, neither Mac tombstones the other's `topApps` container (`ArcSidebarImporter.swift:92-94,252`). Because of N4, both containers carry the same plain profile id. `Sidebar.favoritesContainer(profileID:)` and `favorites(profileID:)` (`FolioStore.swift:282-290`) take the first match by position, then id, so one Mac's favorites are hidden on every device. New favorites also go into whichever container sorts first.
- Fix: falls out of N4, because each Mac's favorites then belong to their own profile id. Otherwise, pick the container deterministically per device, or merge the two.

### N7. m7: Folio-made rows under a space removed in Arc are still invisible
- `ArcSidebarImporter.swift:268-286`: when the whole space is stale, its `unpinned` container is stale too, so `destination` is nil and the row is left in place. The space is then tombstoned (`:297-303`). The user's rows stay stored and synced but don't appear anywhere. The fix notes call this "not a regression", but it is half of m7's original scope.
- Fix: fall back to the profile's first live space (its matching section container), or keep the space alive while it has live Folio-made content.

### N8. m6: starter favorites are still added when iCloud is signed in but the engine didn't start
- `StarterLibrary.swift:56` checks `syncing`, which callers pass as `LibrarySync.isConnected`, and that means `cloud.isRunning` (`LibrarySync.swift:65`). The engine isn't running when `userRecordID()` fails (`CloudKitSync.swift:82`, for example on a launch with no network), or when the status is `temporarilyUnavailable` or `couldNotDetermine`. Onboarding then adds `starter-favorites` and three tabs. When the engine starts later with `previous == nil`, they are uploaded (`:96`). Where the user's library has hard-deleted them (tombstone purged), they come back on every device.
- Fix: treat "an iCloud account is available, or the status is not yet determined" as `syncing` for `finishSetup`. For example, expose `LibrarySync.mayHaveRemoteLibrary` (true unless the status is `.noAccount`, `.unavailable` with no folder, or `.unavailable` for a missing entitlement).

### N9. An account switch leaves the previous account's browsing data reachable: history, and on the Mac the WebKit stores, which a derived `dataStoreID` can reopen
- `SyncStore.swift:94-101` deletes the synced tables but keeps `historyVisit`, and no `WKWebsiteDataStore` is removed. `SyncMapping.swift:144,153`: a profile first seen from iCloud gets `dataStoreID = SHA256("Profile.dataStoreID:" + id)`, which depends only on the profile id.
- Failure (Mac, same macOS user, different Apple ID): account A's `arc-profile-profile-1` came to this Mac through iCloud, so it got the derived id X. After a switch, account B's `arc-profile-profile-1` also arrives first through iCloud and gets X again. B browses with A's cookies and logins. A's history also shows in B's history and suggestions. Before the round 2 fix, `dataStoreID` was random per account, so this collision couldn't happen.
- Fix: in `startClean()`, delete `historyVisit` and remove the data stores of the deleted profiles (`WKWebsiteDataStore.remove(forIdentifier:)`, an app-side hook). Or give profiles first seen from iCloud a random id (it is kept locally anyway), or salt the derived id with a per-install value that `startClean()` rotates.

### N10. M3 (optional part): re-import still reverts Folio-side edits to Arc-derived rows
- `ArcSidebarImporter.swift:233-238`: a live existing row is overwritten with Arc's values. Only `dataStoreID` is adopted. A rename or move made in Folio is undone on every device, while `ArcImportView.swift:94` says re-import leaves Folio changes alone.
- Fix: store the last imported field values per Arc id (device-local), and overwrite only the fields Arc changed since then. Or reword the sheet.

---

## Checked, no finding
- M2 timing: `startClean` runs before the new engine exists. On `.switchAccounts`, `tearDownEngine()` runs in the same synchronous turn as `startClean()`, so no seeded row can be handed to the old engine (`hand` also reads `self.engine`).
- M1 folder transport: a profile first seen from a peer takes that peer's `dataStoreID` from the field state, not the derived id. That is harmless, because ids are per machine. `keepDeviceLocalFields` keeps existing rows stable, and the re-stamp of the local value does not loop.
- m2: purge with the database suspended (N1 window). The flag write fails but the engine is torn down. On the next start the zone deletion is fetched again, so the purge is not silently skipped.
- iOS foreground order: the App-level `scenePhase` resumes at `.inactive`, before `RootView`'s `.active` handler writes (`archiveStaleTabs`), so foreground writes don't hit a suspended database.
- Extensions never post the suspend notification and never create `CloudKitSync`. Suspension is per process (`NotificationCenter.default`).
- `lsp_diagnostics` was not run (no Swift LSP in this session). The sync and arc reports say the iOS and macOS builds succeeded. That was not re-checked.

---

## Resolution (orchestrator, 2026-11-08)
- N1 fixed: `CloudKitSync` `.fetchedRecordZoneChanges` — if `applyServerChanges` throws, report and tear down the engine before its advanced state can be saved; the next start (foreground `syncNow`) re-fetches from the last saved state. Local edits stay in `syncPending`.
- N2 fixed: `.switchAccounts` no longer wipes inline; it tears down and restarts, and `checkAccountAndStart` sees the stored account differ and runs `startClean` (so `cloudUser` is set to the new account and `uploadAll` is false). `startClean` seeds the starter space then clears the upload queue, so the new account's own library wins.
- N3 fixed: `purgeTombstones` never hard-deletes `arc-` rows, so Arc re-import keeps respecting removals made in Folio.
- N4 fixed by reverting the machine suffix: Arc profile ids are again plain per directory on every Mac (no flip-flop). The original cross-Mac name collision is now harmless for logins because `dataStoreID` is device-local (M1). `foreignFavoritesIDs` (m8 favorites part) stays.
- N5 fixed: m7 orphans move to the same section (pinned → space's pinned container; Today → unpinned) by walking up to their root container.
- N6–N10 (low) left as known limitations; N10's sheet wording ("leaves anything you made in Folio alone") still holds for rows created in Folio.
- Also: onboarding now shows immediately on an empty library (Mac and iOS) instead of after the up-to-10 s first fetch.
- Builds: iOS simulator and macOS BUILD SUCCEEDED after these changes.
