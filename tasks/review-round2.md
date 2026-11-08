# Review, round 2 (uncommitted work on top of 07f6b2d)

Scope: iCloud sync (priority 1), Arc import (2), iPhone Duo layout (3). Read-only review: each finding was checked against the code. Nothing was built or run; the build results in `tasks/sync-report.md` and `tasks/arc-import-report.md` were not re-checked.

Counts: Critical 0 · Major 4 · Minor 12

---

## Major

### M1. A device joining with a slow or failed first fetch overwrites the shared "default" profile, including the Mac's `dataStoreID`, so the Mac loses its logins
- `Packages/FolioKit/Sources/FolioKit/Store/StarterLibrary.swift:19-23`: when no profile exists, the seed creates `Profile(id: "default", …, modifiedAt: now)`. The default `dataStoreID: UUID()` is random, and the record is stamped `now`, not `starterStamp` (the space and containers on lines 25-30 use `starterStamp`).
- `Apps/iOS/App/AppModel.swift:72-73`, `Apps/macOS/Model/MacModel.swift:56-57`: the seed runs once `sync.start()` returns. That happens after the 10 s cap (`LibrarySync.swift:73`), right away when the fetch fails (for example today's "Invalid bundle ID for container"), or right away when the account is `temporarilyUnavailable` (the engine never starts).
- `SyncStore.swift:198-202` + `SyncMerge.swift:13-15`: when the Mac's profile arrives, the local row has a pending save and no base, so the merge is last-writer-wins on the whole record. The iPhone's `now` is newer, so the iPhone's profile wins and is re-queued (`outcome.requeue`). The Mac then applies it as server truth (`SyncStore.swift:206-208`).
- Failure: the Mac's `"default".dataStoreID` changes, so `MacModel.swift:181-183` opens a new, empty `WKWebsiteDataStore`. Every login in the Personal space disappears on the Mac. Any rename of that profile is also reverted.
- Fix: seed the profile with `modifiedAt: starterStamp` and a deterministic `dataStoreID`, for example a UUID derived from the profile id. Better, keep `dataStoreID` out of the synced fields: it identifies a local WebKit store, so make it device-local (a separate table or UserDefaults keyed by profile id) and stop mapping it in `SyncMapping.swift:129/139`.

### M2. Account switch, or sign-out followed by sign-in with another Apple ID, merges two people's libraries into both accounts
- `Packages/FolioKit/Sources/FolioKit/Sync/CloudKitSync.swift:206-214`: `.signOut` and `.switchAccounts` call `resetSyncState(reuploadAll: true)`, which keeps every local row and queues it all (`SyncStore.swift:68-79`). `.switchAccounts` then restarts at once. After `.signOut`, the next `CKAccountChanged` restarts (`CloudKitSync.swift:167-176`), and `startEngine` with nil state queues everything again (line 129).
- Failure: on a shared Mac or iPad, user A signs out of iCloud and user B signs in. All of A's spaces, tabs, favorites and archive (URLs) are uploaded into B's private database, and B's library is merged into A's local data. The merge cannot be undone.
- Fix: follow Apple's CKSyncEngine sample. On `.signOut` and `.switchAccounts`, delete local synced data (or at least stop and ask), then start clean. Never auto-upload a previous account's data under a new account. Keep the `.signIn` re-upload only for the case where there is no previous user record (store the user record ID from `change.changeType` and compare).

### M3. Arc re-import resurrects tabs the user closed, archived or deleted in Folio, and reverts Folio-side edits; sync then spreads this to every device
- `Packages/FolioKit/Sources/FolioKit/Import/ArcSidebarImporter.swift:203-215, 217-219`: `upsert` copies only `dataStoreID` from the existing row (`adopt`, lines 313-324). Everything else comes from Arc, including `deletedAt = nil`. A tombstoned row differs from the snapshot, so it is updated live again with `modifiedAt = now`.
- `Packages/FolioKit/Sources/FolioKit/Store/Library.swift:114-122`: closing or archiving a tab tombstones its sidebar row. `archiveStaleTabs` (`Library.swift:87-93`) does this automatically, using `COALESCE(lastActiveAt, createdAt)`, and imported Today tabs carry Arc's old `lastActiveAt` (`ArcSidebarImporter.swift:116`).
- Failure: import, then the Mac's next activation auto-archives the stale Today tabs, then re-import. They are back in the sidebar, and their `ArchiveItem`s stay in the archive. Every re-import repeats this and adds new archive rows. The same happens to any Arc-derived tab or folder the user deleted, renamed or moved in Folio. The sheet says re-import "leaves anything you made in Folio alone" (`ArcImportView.swift:94`), but user deletions are undone on every device.
- Fix: in `upsert`, if `existing.deletedAt != nil`, skip the row (count it as "removed in Folio"). Optionally, keep Folio-side edits by comparing against the last imported snapshot (a stored hash per arc id) and only overwrite fields that changed in Arc.

### M4. A shared App Group SQLite database is opened by three processes with default GRDB configuration: no busy timeout, no suspension handling, and no cross-process change feed into CKSyncEngine
- `Packages/FolioKit/Sources/FolioKit/Store/FolioStore.swift:18-24`: `DatabasePool(path:)` with the default `Configuration` (`busyMode = .immediateError`, `observesSuspensionNotifications = false`) is used by the app, `ShareExtension/ShareModel.swift:21,66` (writes) and `Widgets/FolioSearchWidget.swift:26`. Each process also runs `migrator.migrate` on open (line 10).
- Failures:
  1. The share extension saves while the app is in a write, for example `applyServerChanges` during a push-triggered sync. The extension gets `SQLITE_BUSY` at once and the share fails.
  2. The app is suspended (push or BG refresh sync, `FolioApp.swift:27-30, 50-55`) while holding a lock on a file in the shared container, and iOS kills it with 0xdead10cc.
  3. The extension's new tab is queued in `syncPending` by the trigger, but the app's `pendingSyncChangeUpdates()` observation (`CloudKitSync.swift:136-142`) only sees commits made in its own process. The change is not handed to the engine until the app makes another local write or relaunches, so "Add to Folio" does not reach other devices.
- Fix: follow GRDB's "Sharing a Database" guide. Use `configuration.busyMode = .timeout(…)` and `observesSuspensionNotifications = true`, and post `Database.suspendNotification` / `resumeNotification` on background and foreground. Run migrations only in the app. On foreground (and in `syncNow`), re-read `pendingSyncChanges()` and call `hand(_:)`.

---

## Minor

### m1. The first engine start (and every `.signIn`) wipes the merge bases and change tags while the engine runs, so every record round-trips as a conflict
- `CloudKitSync.swift:204-205` → `reuploadEverything` → `SyncStore.swift:70` deletes `syncRecordMeta`, `syncPending` and all of `syncState` (including the live engine serialization). `sync-report.md` confirms `.signIn` arrives about 1 s after a first start, which is after the initial fetch has stored bases.
- Failure: a joining device re-uploads every record it just fetched, with no change tag. Each one fails with `serverRecordChanged` and goes through `applyServerChanges` with `base == nil`. Any record that also has a concurrent local edit merges as whole-record last-writer-wins instead of per field, so a concurrent field edit made on another device can be lost.
- Fix: when `saved == nil` was already handled in `startEngine`, ignore the first `.signIn`. Otherwise, re-queue without deleting `syncRecordMeta`.

### m2. `.purged` ("delete iCloud data") is re-uploaded anyway
- `CloudKitSync.swift:222-224` clears `syncPending` and meta but not `engine.state.pendingRecordZoneChanges`. The next local edit is also handed to the engine. Either way the result is `zoneNotFound`, then `needsZone`, and the zone is recreated with whatever was pending (`CloudKitSync.swift:286-288, 312`).
- Failure: the user deletes Folio's iCloud data in Settings, and a partial library reappears in iCloud a moment later. New devices then join with that partial copy.
- Fix: on `.purged`, remove every pending change from `engine.state` and stop the engine, or require an explicit "Sync again", rather than relying on the comment's intent.

### m3. `syncNow` reports "Up to date" over errors and over a sign-out that happened during the sync
- `CloudKitSync.swift:99-107`: per-record failures don't throw, so `.quotaExceeded` (line 295) or `report(...)` set `.error`, and then line 103 overwrites it with `.upToDate(.now)`. If `.signOut` arrives during the awaits, `tearDownEngine` and `status = .noAccount` are overwritten the same way, so `LibrarySync.offersFolder` (`LibrarySync.swift:52-57`) becomes false and the folder fallback is hidden.
- Fix: only set `.upToDate` if the status is still `.syncing` and `engine === self.engine` after the awaits.

### m4. Picking a folder while iCloud comes up leaves an orphaned `FolioSync` writing the bookmark back and running beside CloudKit
- `LibrarySync.swift:86-91`: `setFolder` keeps a local `folder` reference across `await folder.start()`. If `CKAccountChanged` → `retireFolder` (`104-114`) runs in that window, it stops the folder, sets `self.folder = nil` and deletes the bookmark (`resetSyncState` clears `syncState`). `folder.setFolder(url)` then resumes on the orphan: it re-saves the bookmark, re-adds the presenter, and runs a pass that drains `syncPending` (`FolderSync.swift:84-91`) while CKSyncEngine is live. This can drop a "re-edited while in flight" requeue in `didSave` (`SyncStore.swift:112-113`). The orphan's 60 s loop (`FolderSync.swift:399-404`) is never cancelled, and on the next launch `retireFolder` runs again, forcing a full re-upload.
- Fix: after the awaits in `setFolder`, re-check `offersFolder` and `self.folder === folder`. Make `retireFolder` set a generation token that `setFolder` checks.

### m5. iOS push and background-refresh sync are no-ops when the app wasn't already running with a scene
- `FolioApp.swift:21`: `model.start()` (which creates `model.sync`) runs only from the `WindowGroup`'s `.task`. A background launch for a CloudKit push (`FolioApp.swift:50-55`) or a BG app refresh (`27-30`) has `model.sync == nil`, so it returns `.noData` or does nothing.
- Fix: start the store and sync from `application(_:didFinishLaunchingWithOptions:)`, or lazily inside both handlers.

### m6. Starter favorites (and purged starter records) are pushed to every device when a joining device's fetch hasn't landed
- `StarterLibrary.swift:56-70`: `finishSetup` adds `starter-favorites` and three tabs whenever the local library has 0 tabs. On a joining device whose first fetch failed or is still running, that check passes, and the records sync to the Mac's library under profile `default`. The "never revive" guard (line 65) only sees local rows, so starter items the user removed more than 30 days ago (tombstones purged, `SyncStore.swift:225-241`) also come back.
- Fix: skip the favorites when `syncing` is true. Let the device that created the library own its starter content.

### m7. Re-import orphans Folio-made rows under Arc folders or spaces that were removed from Arc
- `ArcSidebarImporter.swift:221-237` tombstones Arc-derived folders, containers and spaces, but live non-`arc-` children (a tab the user added to an imported folder, or a Today tab in an imported space) keep a `parentID` or `spaceID` that points at a tombstone. `Sidebar.fetch` filters those parents out, so the user's rows become invisible on every device, although they are still stored and synced.
- Fix: before tombstoning a container, move its live non-Arc children to the space's unpinned container, or to a "From Arc" fallback.

### m8. Importing on two Macs makes the favorites ping-pong, and profile ids collide across Macs
- `ArcSidebarImporter.swift:70-85`: each Mac picks its own machine's `topApps` container. Line 221-230 tombstones the other Mac's container (same profile id, `arc-` prefix, not in this snapshot), so whichever Mac imported last deletes the other's favorites everywhere. `profileID(directory:)` (line 44-46) ignores `machineID`, so "Profile 1" on Mac A and a different "Profile 1" on Mac B become the same Folio profile (and share a synced `dataStoreID`, see M1).
- Fix: limit the tombstone pass to items whose container was picked by this Mac (record the machine id on import), and include the machine id in non-local profile ids.

### m9. Moving between the wide and laptop poses rebuilds `TabBrowser`, against the shell's own contract
- `Apps/iOS/Views/RootView.swift:80-98`: `.laptop` puts `browserPane` inside `ArrangementView`, while every other pose puts it in the `ZStack/HStack`. That is a different structural position, so half-closing a landscape-unfolded device recreates `TabBrowser` with a new `hostID`, which dismisses an open Reader or Downloads sheet (`TabBrowser.swift:24-25, 84-85`), resets pull and rail state, and shows the snapshot placeholder (`TabBrowser.swift:39-48`) during the hand-off. The header comment (lines 54-58) says "never rebuilt as the hinge moves".
- Fix: keep `browserPane` at one structural position and lay out `DeskControls` with a conditional `VStack`/frame around it, or accept the rebuild and correct the comment.

### m10. The floating card's open state goes stale across poses and doesn't follow "pick the current tab"
- `RootView.swift:64, 103-107`: `cardOpen` changes only on `activeTabID` changes. Open the card in narrow, switch to wide or book, and the card reappears when you come back to narrow. In narrow, tapping the already-active tab in the card (`TodayRow`, `PinnedRow`, "Back to pinned page") doesn't change `activeTabID`, so the card stays over the page.
- Fix: reset `cardOpen` in `.onChange(of: pose)`. Have row taps close the card through the `SidebarControl` (or a model callback) instead of relying on `activeTabID` changing.

### m11. In the book pose the page starts under the crease
- `RootView.swift:73, 116`: the sidebar width is `fold.minX`, and the page follows after a 0.5 pt separator, so the page's leading edge is at `fold.minX` while the division region runs `minX…maxX`. If the reported division has any width (FoldGlow assumes it may, line 238), the page's leading content sits under the hinge.
- Fix: put a spacer of `fold.width` (or start the page at `fold.maxX`) between the sidebar and the page.

### m12. Accessibility gaps in the new chrome
- `SpaceHome.swift:296-303`: the space dots are `Capsule().onTapGesture`, with no label, no button trait and no value, so VoiceOver cannot switch spaces from the bar. Fix: use a `Button` with `accessibilityLabel(space.title)`, or a single adjustable element.
- `TabBrowser.swift:302`: the bottom-bar Reload/Stop `BarButton` has no label (the rail version, line 208, does).
- `SpaceHome.swift:510-519`: `FavoriteTile` has no label. Only a monogram is spoken.
- `SpaceHome.swift:450-455`: the `TabCard` close button has no label.
- `RootView.swift:96, 123-140`: while the floating card is open, the page beneath stays in the VoiceOver order. Add `.accessibilityAddTraits(.isModal)` to the card, or hide the page.

---

## Checked, no finding
- Folder-to-CloudKit hand-off when nothing races (`LibrarySync.retireFolder`): the final pass flushes, then `resetSyncState(reuploadAll:)` re-queues every row, tombstones included. Nothing is lost when both transports drain `syncPending` in sequence.
- `CloudKitSync.start()` joins an in-flight start, and `CKAccountChanged` and `switchAccounts` restarts join it as well.
- Edits made while a record is in flight are re-queued by `didSave` (`SyncStore.swift:108-121`).
- Cookies: read only when the "Keep me signed in" toggle is set (default off, `ArcImportView.swift:27, 241-253`). The Keychain secret is read once and kept in memory. Cookies go only to `WKWebsiteDataStore(forIdentifier:)` and are never written to the store or synced. Only this Mac's profile directories are used, and paths are filtered. `ArcPasswordImporter` (synchronizable Keychain writes) is compiled in but unreachable from the UI. Keep it that way, or remove it until the security review is done.
- `Favicons.seed`: never replaces an existing icon. The importer limits files to PNG under 512 KB, and the host key comes from `URL.host()`, so there is no path traversal.
- `WindowTheme` background parsing: decoding is lenient and there are no force unwraps on input. In the HSB math, `delta > 0` guarantees `high > 0`.
