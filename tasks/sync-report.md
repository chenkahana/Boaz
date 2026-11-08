# iCloud sync: report (2026-11-08)

## Transport policy
- iCloud (CloudKit, private DB, zone "Folio", container `iCloud.com.chenkahana.folio`) is the default. If the build is entitled and an iCloud account is signed in, `CloudKitSync` runs and the folder transport does not.
- The folder (`FolioSync`) is a fallback only. It is offered only while iCloud reports no account or is unavailable (`LibrarySync.offersFolder`), and it auto-starts only if a folder was picked before.
- At most one transport runs at a time. Before the engine starts (at launch or when an account appears), `CloudKitSync.willStartEngine` calls `LibrarySync.retireFolder()`. That runs one last folder pass (peers' edits in, our unsent edits out), stops and forgets the folder, then resets sync state and queues every record for upload.
- Both apps use one facade, `LibrarySync`. It exposes `status`, `syncNow()`, `start()`, `offersFolder`, `folderURL`, `isConnected` and `setFolder(_:)`.

## Changes by file
- `project.yml`: iOS and Mac entitlements `icloud-services [CloudKit]`, `icloud-container-identifiers [iCloud.com.chenkahana.folio]`, push (`aps-environment` on iOS, `com.apple.developer.aps-environment` on Mac). iOS `UIBackgroundModes` gains `remote-notification`. Bundle ids are unchanged (Mac keeps `com.example.folio.mac`). Regenerated the project and the entitlements and Info.plist files.
- `Packages/FolioKit/Sources/FolioKit/Sync/LibrarySync.swift` (new): the facade and transport policy. On an iCloud device the first fetch is awaited for at most 10 s, so an empty device receives the library before seeding. Also holds the status copy and symbols.
- `Sync/CloudKitSync.swift`:
  - Removed the PARKED note, set the real container and the logger subsystem `com.chenkahana.folio`.
  - `start()` now joins a start already in flight (replaces the `isStarting` early return, which could make a racing caller skip the first fetch).
  - New `willStartEngine` hook.
  - A start with no saved engine state queues every local record.
  - Account changes and re-upload counts are logged.
- `Sync/FolderSync.swift`: logger subsystem. `syncNow()` now waits for a pass already running instead of returning early, so retiring the folder can't drain the queue after iCloud's re-upload. `bookmarkKey` is now internal.
- `Sync/CloudKitEntitlements.swift`, `Sync/SyncStore.swift`: concise unavailable text; dropped the "parked" comment.
- `Apps/Shared/SyncStatusLabel.swift` (new): live status row (iCloud symbol, rotates while syncing, green check when up to date).
- iOS:
  - `App/AppModel.swift`: `sync: LibrarySync?`. RootView's `model.sync?.syncNow()` on foreground compiles unchanged.
  - `App/FolioApp.swift`: an app delegate owns the model, registers for remote notifications and calls `syncNow()` on a CloudKit push.
  - `Views/LibrarySheet.swift`: "iCloud Sync" section with status, Sync Now, and the folder rows only when iCloud is unavailable.
  - `Onboarding/OnboardingView.swift`: "Your library syncs with iCloud" with a live status card, success haptic on up to date, and the folder button only as the fallback. `finishSetup(syncing: isConnected)`.
- Mac:
  - `Model/MacModel.swift`: `LibrarySync`; also syncs on app activation.
  - `FolioMacApp.swift`: registers for remote notifications and syncs on a CloudKit push.
  - `Views/LibraryViews.swift`: "iCloud Sync" section, same rules as iOS.
  - `Onboarding/OnboardingView.swift`: same wording and fallback rules as iOS.

## Migration proof (Mac runtime log, subsystem `com.chenkahana.folio`)
- First CloudKit start (no saved engine state): `Queued 36 records for upload` came from our explicit reset. One second later the engine sent `Account change: signIn(...)`, which queued the same 36 again. So CKSyncEngine does emit signIn on a first start with nil state. The explicit reset stays as a deterministic guarantee. The two are idempotent: the same rows are queued via INSERT OR REPLACE.
- The local DB, read-only after the run: syncPending 36 (2 spaces, 28 sidebar items, 1 profile, 5 archive items; 0 deletions), syncRecordMeta 0, syncState keys `engine` only.
- This Mac had no sync folder configured (no `folderBookmark` key, no "Moving from folder sync to iCloud" line), so the folder-retire path was not exercised at runtime.
- Empty device joining: `start()` awaits the first fetch (up to 10 s) before `StarterLibrary.seedIfEmpty`, mirroring the folder logic. Starter ids are fixed and epoch-stamped, so a seed that races the fetch still merges into the remote Personal space. `finishSetup` keeps Personal while `isConnected`.

## Build results
- iOS (simulator `4807AAA7…`, `build/agent-sync`): BUILD SUCCEEDED. The first two attempts failed in files owned by others, `TabBrowser.swift:48` and `Import/ArcSidebarImporter.swift:86`; both were fixed by their owners.
- iOS device (`generic/platform=iOS`, `build/agent-sync-device`, `-allowProvisioningUpdates`): BUILD SUCCEEDED. Team profiles were created for `com.chenkahana.folio`, `.share` and `.widgets`. The app is signed with the container and `aps-environment` development.
- Mac (`build/agent-sync-mac`): the first try failed with "Device IL-DXRXMXRY44 isn't registered". Re-running with `-allowProvisioningUpdates -allowProvisioningDeviceRegistration` registered this Mac on team DPF8459C2J and created the iCloud container and "Mac Team Provisioning Profile: com.example.folio.mac". The profile includes `iCloud.com.chenkahana.folio` (Development and Production) and aps. BUILD SUCCEEDED.

## Runtime result (Mac): blocked on the server
- iCloud account found, engine started, status idle, then every fetch failed: `CKError "Permission Failure" (10/2007); server message = "Invalid bundle ID for container"`. Seen at 00:09, 00:12 and 00:18, about 10 minutes after the container was created.
- The settings and onboarding status show "Couldn't sync: …". The 36 records stay queued; nothing is lost and nothing was uploaded.

## Owner must do
1. Wait or fix the container link for the Mac App ID. If Mac sync still shows "Invalid bundle ID for container" later today, open Folio.xcodeproj › target Folio-macOS › Signing & Capabilities › iCloud. Make sure `iCloud.com.chenkahana.folio` is ticked and click the refresh (↻) under Containers. Alternatively, at developer.apple.com › Identifiers › `com.example.folio.mac` › iCloud › Configure, assign the container and save. Then relaunch Folio and press Sync Now.
2. Run the iOS app on the Duo (Xcode › Run) so that device is registered and the iOS profile covers it.
3. Before release: CloudKit Console › container › Deploy Schema Changes to Production (record types are created in Development on first upload).

## Unverified
- Any successful upload or fetch (blocked by the error above), and so cross-device merge, the empty-device join and push-triggered sync.
- The folder-to-iCloud migration on a device that has a folder (this Mac had none).
- The iOS app at runtime (simulator in use; only built). Whether a background push launch without a connected scene reaches sync.
- The UI was not inspected visually.

## Round 2 fixes (review-round2.md: M1, M2, M4, m1–m6)
Paths are under `Packages/FolioKit/Sources/FolioKit/` unless they start with `Apps/`.

- **M1, `dataStoreID` is now device-local.** `Profile.write(to:)` no longer writes it, and old records that still carry it are ignored (`Sync/SyncMapping.swift:131`). A profile first seen from another device gets a stable id derived from its profile id (`SyncMapping.swift:144,153`). The new `SyncableRecord.keepDeviceLocalFields(from:)` hook (`SyncMapping.swift:44,49,150`) keeps the local row's `dataStoreID` on every incoming copy, for CloudKit (`Sync/SyncStore.swift:224`) and for the folder (`Sync/FolderSync.swift:162`). Existing profiles, including the Mac's, keep their current id and logins. The starter profile is now stamped `starterStamp` (`Store/StarterLibrary.swift:20`), so any real profile wins over it.
- **M2, account changes.** Before the engine starts, `checkAccountAndStart` fetches the user record ID and compares it with the stored `cloudUser` (`Sync/CloudKitSync.swift:82-96`). On the first account, every local record is uploaded. When the same account signs back in, the device only re-fetches. When a different account signs in, `startClean()` runs (`CloudKitSync.swift:227`): it deletes the synced library and all sync state (`SyncStore.deleteSyncedLibrary`, `SyncStore.swift:94`), then re-seeds Personal. `.signOut` now forgets only the engine state and queues nothing (`CloudKitSync.swift:257`). `.switchAccounts` runs `startClean()` and restarts (`:263-265`). `resetSyncState` keeps the `cloudUser` and `cloudPurged` keys (`SyncStore.swift:69`).
- **M4, shared database.**
  - `onDisk` now sets `busyMode = .timeout(5)` and `observesSuspensionNotifications = true` (`Store/FolioStore.swift:29-30`).
  - Only the app runs migrations. The extensions pass `migrate: false` (`FolioStore.swift:9,22`, `Apps/Extensions/ShareExtension/ShareModel.swift:21`, `Apps/Extensions/Widgets/FolioSearchWidget.swift:26`).
  - The iOS app suspends the database in the background and resumes it otherwise (`Apps/iOS/App/FolioApp.swift:26-33`, helpers at `FolioStore.swift:36-37`). It also resumes the database around push and background-refresh syncs, then suspends it again (`Apps/iOS/App/AppModel.swift:97`).
  - `syncNow` re-reads `pendingSyncChanges()` and hands them to the engine (`CloudKitSync.swift:116`). Foreground (iOS RootView) and app activation (Mac) already call `syncNow`, so changes from the extension reach the engine.
- **m1, merge bases are kept.** A fresh engine sets `startedFresh` (`CloudKitSync.swift:160`), and the `.signIn` that follows it is ignored (`:253`). `reuploadEverything` now queues records with `queueAllForUpload()` and no longer deletes `syncRecordMeta` (`CloudKitSync.swift:213`, `SyncStore.swift:79`). The zone-deleted or key-reset path still resets the change tags on purpose.
- **m2, `.purged`.** Every pending zone and database change is removed from `engine.state`, sync state is reset, the `cloudPurged` key is set, the engine is torn down, and the status becomes an error that says why (`CloudKitSync.swift:275`). `start()` stays off while the key is set. `resumeAfterPurge()` (`:131`), reached through `LibrarySync.syncNow(userInitiated: true)` (`Sync/LibrarySync.swift:83`), queues the whole library and restarts.
- **m3, `syncNow` status.** The status changes to `.upToDate` only when it is still `.syncing` and the engine is unchanged. The error path also checks that the engine is unchanged (`CloudKitSync.swift:122`).
- **m4, `setFolder` race.** `retireFolder` increments `folderGeneration` (`LibrarySync.swift:114`). After `await folder.start()`, `setFolder` checks the generation, `self.folder === folder` and `offersFolder` before it continues (`:92-96`).
- **m5, background launch.** `AppModel.prepareSync()` opens the store and sync once (`AppModel.swift:86`). `start()` and the new `backgroundSync()` both use it, so push and app-refresh launches without a scene now sync (`FolioApp.swift:36,60`).
- **m6, starter favorites.** `finishSetup` adds no favorites while `syncing` (`StarterLibrary.swift:56`).

### Build results (round 2)
- iOS (`build/agent-sync`, simulator 4807AAA7…): BUILD SUCCEEDED.
- Mac (`build/agent-sync-mac`, `-allowProvisioningUpdates`): BUILD SUCCEEDED.

### Open items
- **Views follow-up (not in my files):** the "Sync Now" buttons (`Apps/iOS/Views/LibrarySheet.swift:192`, `Apps/macOS/Views/LibraryViews.swift:97`) should call `sync.syncNow(userInitiated: true)`. Until they do, sync stays off after a purge, which is the safe default.
- Engine start now needs `userRecordID()`. If that call fails (for example on a launch with no network), sync shows the error and retries on the next `syncNow` (foreground or activation) or account change.
- iOS: an automatic engine sync that runs while the database is suspended (rather than through the push or refresh handlers) fails its writes with "Database is suspended" and reports an error. Not verified at runtime.
- Nothing was run. Account switch, purge and extension hand-off are verified by reading the code only.
