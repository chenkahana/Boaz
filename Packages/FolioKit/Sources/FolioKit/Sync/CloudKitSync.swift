import CloudKit
import Foundation
import GRDB
import Observation
import os

/// Mirrors the store to the user's private CloudKit database (zone "Folio") with `CKSyncEngine`.
///
/// Local writes are queued by database triggers, so every write path syncs without extra calls. Server changes are
/// applied through `FolioStore.applyServerChanges`, which merges with unsent local edits (`SyncMerge`).
/// Without the iCloud entitlement or an iCloud account it stays idle and says why in `status`.
@MainActor @Observable
public final class CloudKitSync {
    public enum Status: Equatable, Sendable {
        case idle
        /// Sync can't run in this build or on this device (missing entitlement, restricted account…).
        case unavailable(String)
        case noAccount
        case syncing
        case error(String)
        case upToDate(Date)
    }

    public static let defaultContainerIdentifier = "iCloud.com.chenkahana.folio"

    public private(set) var status: Status = .idle
    public let containerIdentifier: String
    /// Runs right before the engine starts (at launch or when an iCloud account appears), e.g. to retire another
    /// transport that drains the same pending queue.
    @ObservationIgnored public var willStartEngine: (@MainActor () async -> Void)?

    @ObservationIgnored private let store: FolioStore
    @ObservationIgnored private var engine: CKSyncEngine?
    @ObservationIgnored private var container: CKContainer?
    @ObservationIgnored private var queueTask: Task<Void, Never>?
    @ObservationIgnored private var accountObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var starting: Task<Void, Never>?
    /// The engine started without saved state, so `startEngine` already queued what this account should get.
    @ObservationIgnored private var startedFresh = false

    private static let log = Logger(subsystem: "com.chenkahana.folio", category: "sync")

    public init(store: FolioStore, containerIdentifier: String = CloudKitSync.defaultContainerIdentifier) {
        self.store = store
        self.containerIdentifier = containerIdentifier
    }

    public var isRunning: Bool { engine != nil }

    /// Starts syncing when the build is entitled and an iCloud account is signed in; otherwise sets `status` and
    /// waits for an account change. Safe to call repeatedly; a call during a start waits for that start.
    public func start() async {
        if let starting { return await starting.value }
        guard engine == nil else { return }
        let task = Task { await checkAccountAndStart() }
        starting = task
        await task.value
        starting = nil
    }

    private func checkAccountAndStart() async {
        if let reason = CloudKitEntitlements.missingReason(containerIdentifier: containerIdentifier) {
            Self.log.notice("Sync unavailable: \(reason, privacy: .public)")
            status = .unavailable(reason)
            return
        }
        let container = self.container ?? CKContainer(identifier: containerIdentifier)
        self.container = container
        observeAccountChanges()

        let account: CKAccountStatus
        do {
            account = try await container.accountStatus()
        } catch {
            Self.log.error("Account status failed: \(error, privacy: .public)")
            status = .error(error.localizedDescription)
            return
        }
        switch account {
        case .available:
            let user: String
            do { user = try await container.userRecordID().recordName } catch { return report(error) }
            await willStartEngine?()
            // Never upload one Apple ID's library into another (Apple's CKSyncEngine sample deletes local data on
            // sign-out and account switch). The same account signing back in just re-fetches; a different one
            // starts this device clean and takes that account's library.
            let previous = store.syncSetting(FolioStore.cloudUserKey)
            do {
                if let previous, previous != user { try startClean() }
                try store.setSyncSetting(user, for: FolioStore.cloudUserKey)
            } catch { return report(error) }
            guard store.syncSetting(FolioStore.cloudPurgedKey) == nil else {
                status = .error(Self.purgedMessage)
                return
            }
            startEngine(database: container.privateCloudDatabase, uploadAll: previous == nil)
        case .noAccount:
            status = .noAccount
        case .restricted:
            status = .unavailable("iCloud is restricted on this device.")
        case .temporarilyUnavailable:
            status = .unavailable("iCloud is temporarily unavailable. Try again in a moment.")
        case .couldNotDetermine:
            status = .error("Couldn't determine the iCloud account status.")
        @unknown default:
            status = .error("Unknown iCloud account status.")
        }
        Self.log.notice("Sync status: \(String(describing: self.status), privacy: .public)")
    }

    /// Fetches then sends right away instead of waiting for the engine's schedule.
    public func syncNow() async {
        if engine == nil { await start() }
        guard let engine else { return }
        // Picks up changes queued by the share extension or widgets: this process's observation can't see them.
        if let queue = try? store.pendingSyncChanges() { hand(queue) }
        status = .syncing
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
            // An error or a sign-out reported meanwhile stands.
            if engine === self.engine, case .syncing = status { status = .upToDate(.now) }
        } catch {
            Self.log.error("Sync failed: \(error, privacy: .public)")
            if engine === self.engine { status = .error(error.localizedDescription) }
        }
    }

    /// After the user deleted Folio's iCloud data, sync stays off until they ask; this uploads this device's whole
    /// library again. Does nothing otherwise.
    public func resumeAfterPurge() async {
        guard store.syncSetting(FolioStore.cloudPurgedKey) != nil else { return }
        do {
            try store.setSyncSetting(nil, for: FolioStore.cloudPurgedKey)
            try store.queueAllForUpload()
        } catch { return report(error) }
        status = .idle
        await start()
    }

    /// Stops syncing. Local data and sync state are kept.
    public func stop() {
        queueTask?.cancel()
        queueTask = nil
        if let accountObserver { NotificationCenter.default.removeObserver(accountObserver) }
        accountObserver = nil
        engine = nil
        status = .idle
    }

    // MARK: Engine lifecycle

    /// `uploadAll`: this is the first account this library syncs with, so every local record goes up.
    private func startEngine(database: CKDatabase, uploadAll: Bool) {
        let saved = store.loadSyncEngineState()
        var configuration = CKSyncEngine.Configuration(database: database, stateSerialization: saved, delegate: self)
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        startedFresh = saved == nil
        if saved == nil {
            if uploadAll { reuploadEverything(engine) } else { addZone(engine) }
        }
        status = .idle

        Task { [store] in
            do { try await store.purgeTombstones() } catch {
                Self.log.error("Tombstone purge failed: \(error, privacy: .public)")
            }
        }

        queueTask?.cancel()
        let store = store
        queueTask = Task { [weak self] in
            do {
                for try await queue in store.pendingSyncChangeUpdates() { self?.hand(queue) }
            } catch {
                Self.log.error("Pending queue observation ended: \(error, privacy: .public)")
            }
        }
    }

    private func tearDownEngine() {
        queueTask?.cancel()
        queueTask = nil
        engine = nil
    }

    /// Hands queued local changes to the engine (it de-duplicates by record, we drop the opposite operation).
    private func hand(_ queue: [SyncPendingChange]) {
        guard let engine else { return }
        let existing = Set(engine.state.pendingRecordZoneChanges)
        var add: [CKSyncEngine.PendingRecordZoneChange] = [], remove: [CKSyncEngine.PendingRecordZoneChange] = []
        for change in queue {
            guard let id = change.cloudRecordID else { continue }
            let wanted: CKSyncEngine.PendingRecordZoneChange = change.isDeletion ? .deleteRecord(id) : .saveRecord(id)
            let opposite: CKSyncEngine.PendingRecordZoneChange = change.isDeletion ? .saveRecord(id) : .deleteRecord(id)
            if !existing.contains(wanted) { add.append(wanted) }
            if existing.contains(opposite) { remove.append(opposite) }
        }
        if !remove.isEmpty { engine.state.remove(pendingRecordZoneChanges: remove) }
        if !add.isEmpty { engine.state.add(pendingRecordZoneChanges: add) }
    }

    private func observeAccountChanges() {
        guard accountObserver == nil else { return }
        accountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) {
            [weak self] _ in
            Task { @MainActor in
                guard let self, self.engine == nil else { return }
                await self.start()
            }
        }
    }

    /// Queues every local record (keeping change tags and merge bases) and the zone.
    private func reuploadEverything(_ engine: CKSyncEngine) {
        do {
            try store.queueAllForUpload()
            Self.log.notice("Queued \((try? self.store.pendingSyncChanges().count) ?? 0, privacy: .public) records for upload")
        } catch { report(error) }
        addZone(engine)
    }

    private func addZone(_ engine: CKSyncEngine) {
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncMapping.zoneID))])
    }

    /// Another account took over: drop the previous account's library and sync state, then start from the
    /// starter space; this account's library arrives with the first fetch.
    private func startClean() throws {
        Self.log.notice("iCloud account changed: clearing the previous account's library")
        try store.deleteSyncedLibrary()
        // Something to browse in until the fetch lands, kept off the upload queue: this account's own library
        // (which may have dropped Personal) wins.
        try StarterLibrary.seedIfEmpty(store)
        try store.resetSyncState(reuploadAll: false)
    }

    static let purgedMessage = "Folio's iCloud data was deleted, so sync is off. Choose Sync Now to upload this library again."

    private func report(_ error: any Error) {
        Self.log.error("Sync error: \(error, privacy: .public)")
        status = .error(error.localizedDescription)
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudKitSync: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard syncEngine === engine else { return }
        switch event {
        case .stateUpdate(let update):
            do { try store.saveSyncEngineState(update.stateSerialization) } catch { report(error) }

        case .accountChange(let change):
            Self.log.notice("Account change: \(String(describing: change.changeType), privacy: .public)")
            switch change.changeType {
            case .signIn:
                // A fresh engine already queued what this account gets (`checkAccountAndStart`).
                guard !startedFresh else { startedFresh = false; break }
                reuploadEverything(syncEngine)
            case .signOut:
                // Keep local data and stop. Nothing is queued for the next account: `checkAccountAndStart` re-fetches
                // for the same Apple ID and starts clean for a different one.
                do { try store.clearSyncEngineState() } catch { report(error) }
                tearDownEngine()
                status = .noAccount
            case .switchAccounts:
                // A different Apple ID: the restart sees the stored account differ and starts this device clean,
                // so the previous account's library is never uploaded.
                tearDownEngine()
                Task { await start() }
            @unknown default:
                break
            }

        case .fetchedDatabaseChanges(let changes):
            for deletion in changes.deletions where deletion.zoneID == SyncMapping.zoneID {
                switch deletion.reason {
                case .purged:
                    // The user deleted Folio's iCloud data in Settings: keep local data, drop everything pending and
                    // stop, so nothing (not even a partial library) reappears until they choose Sync Now.
                    syncEngine.state.remove(pendingRecordZoneChanges: syncEngine.state.pendingRecordZoneChanges)
                    syncEngine.state.remove(pendingDatabaseChanges: syncEngine.state.pendingDatabaseChanges)
                    do {
                        try store.resetSyncState(reuploadAll: false)
                        try store.setSyncSetting("1", for: FolioStore.cloudPurgedKey)
                    } catch { report(error) }
                    tearDownEngine()
                    status = .error(Self.purgedMessage)
                    return
                default:
                    // Zone deleted or end-to-end keys reset: forget its change tags, recreate it and upload this
                    // device's copy.
                    do { try store.resetSyncState(reuploadAll: true) } catch { report(error) }
                    addZone(syncEngine)
                }
            }

        case .fetchedRecordZoneChanges(let changes):
            do {
                let requeue = try await store.applyServerChanges(modified: changes.modifications.map(\.record),
                                                           deleted: changes.deletions.map(\.recordID))
                syncEngine.state.add(pendingRecordZoneChanges: requeue.compactMap(\.engineChange))
            } catch {
                // Couldn't store them (e.g. the database is suspended in the background). The engine has already
                // moved past these changes, so drop it before its state is saved; the next start re-fetches from
                // the last saved state. Local edits stay queued in `syncPending`.
                report(error)
                tearDownEngine()
            }

        case .sentRecordZoneChanges(let sent):
            await handleSent(sent, engine: syncEngine)

        case .sentDatabaseChanges(let sent):
            for failure in sent.failedZoneSaves { report(failure.error) }

        case .willFetchChanges, .willSendChanges:
            status = .syncing

        case .didFetchChanges, .didSendChanges:
            if case .syncing = status { status = .upToDate(.now) }

        case .didFetchRecordZoneChanges(let fetch):
            if let error = fetch.error { report(error) }

        case .willFetchRecordZoneChanges:
            break

        @unknown default:
            Self.log.notice("Unhandled sync event: \(String(describing: event), privacy: .public)")
        }
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                          syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        let store = store
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
            try? store.cloudRecord(for: recordID)
        }
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, engine: CKSyncEngine) async {
        var requeue: [CKSyncEngine.PendingRecordZoneChange] = []
        var conflicts: [CKRecord] = [], unknown: [CKRecord.ID] = []
        var needsZone = false
        do {
            requeue += try store.didSave(serverRecords: sent.savedRecords).compactMap(\.engineChange)
            let goneAnyway = sent.failedRecordDeletes.filter { $0.value.code == .unknownItem }.map(\.key)
            try store.didDelete(recordIDs: sent.deletedRecordIDs + goneAnyway)
        } catch { report(error) }

        for failure in sent.failedRecordSaves {
            let id = failure.record.recordID
            switch failure.error.code {
            case .serverRecordChanged:
                if let server = failure.error.serverRecord { conflicts.append(server) }
            case .zoneNotFound:
                needsZone = true
                unknown.append(id)
            case .unknownItem:
                unknown.append(id)
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
                 .operationCancelled, .requestRateLimited:
                break // The engine retries these itself.
            case .quotaExceeded:
                status = .error("iCloud storage is full.")
            default:
                report(failure.error)
            }
        }
        do {
            if !unknown.isEmpty {
                try store.clearSystemFields(unknown)
                requeue += unknown.map { .saveRecord($0) }
            }
            if !conflicts.isEmpty {
                requeue += try await store.applyServerChanges(modified: conflicts).compactMap(\.engineChange)
            }
        } catch { report(error) }
        for (id, error) in sent.failedRecordDeletes where error.code != .unknownItem {
            Self.log.error("Delete of \(id.recordName, privacy: .private) failed: \(error, privacy: .public)")
        }
        if needsZone { engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncMapping.zoneID))]) }
        if !requeue.isEmpty { engine.state.add(pendingRecordZoneChanges: requeue) }
    }
}
