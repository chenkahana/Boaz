import CloudKit
import Foundation
import GRDB

/// A local change waiting for upload. Rows are written by the `v3-sync` triggers on every local write.
public struct SyncPendingChange: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "syncPending"
    public var recordType: String
    public var recordID: String
    public var isDeletion: Bool

    public init(_ type: SyncRecordType, _ id: String, isDeletion: Bool = false) {
        recordType = type.rawValue; recordID = id; self.isDeletion = isDeletion
    }

    public var cloudRecordID: CKRecord.ID? {
        SyncRecordType(rawValue: recordType).map { SyncMapping.recordID($0, recordID) }
    }

    public var engineChange: CKSyncEngine.PendingRecordZoneChange? {
        cloudRecordID.map { isDeletion ? .deleteRecord($0) : .saveRecord($0) }
    }
}

/// Last server copy of a record: system fields (change tag) plus its values as JSON, the base for 3-way merges.
struct SyncRecordMeta: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "syncRecordMeta"
    var recordType: String
    var recordID: String
    var systemFields: Data
    var base: Data?
}

/// CloudKit sync bookkeeping on the store; public so it can be exercised offline.
extension BoazStore {
    // MARK: Pending queue

    public func pendingSyncChanges() throws -> [SyncPendingChange] {
        try writer.read { db in try SyncPendingChange.fetchAll(db) }
    }

    /// Emits the whole queue after every commit that touches it.
    public func pendingSyncChangeUpdates() -> AsyncValueObservation<[SyncPendingChange]> {
        ValueObservation.tracking { db in try SyncPendingChange.fetchAll(db) }.values(in: writer)
    }

    // MARK: Engine state

    private static let engineStateKey = "engine"

    public func loadSyncEngineState() -> CKSyncEngine.State.Serialization? {
        let data = try? writer.read { db in
            try Data.fetchOne(db, sql: "SELECT value FROM syncState WHERE key = ?", arguments: [Self.engineStateKey])
        }
        return data.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
    }

    /// Runs on the database's queue, like the other writes the engine's events make.
    public func saveSyncEngineState(_ state: CKSyncEngine.State.Serialization) async throws {
        let data = try JSONEncoder().encode(state)
        try await writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO syncState(key, value) VALUES (?, ?)",
                           arguments: [Self.engineStateKey, data])
        }
    }

    /// Forgets everything CloudKit told us (engine state, change tags, merge bases) but keeps local data and which
    /// iCloud account and CloudKit environment this library belongs to. With `reuploadAll`, every local record
    /// (tombstones included) is queued for upload.
    public func resetSyncState(reuploadAll: Bool) throws {
        try writer.write { db in
            try db.execute(sql: """
                DELETE FROM syncState WHERE key NOT IN (?, ?, ?); DELETE FROM syncRecordMeta; DELETE FROM syncPending
                """, arguments: [Self.cloudUserKey, Self.cloudEnvironmentKey, Self.cloudPurgedKey])
            if reuploadAll { try Self.queueAll(in: db) }
        }
    }

    /// Queues every local record (tombstones included) for upload, keeping change tags and merge bases.
    public func queueAllForUpload() throws {
        try writer.write { db in try Self.queueAll(in: db) }
    }

    static func queueAll(in db: Database) throws {
        for type in SyncRecordType.allCases {
            try db.execute(sql: """
                INSERT OR REPLACE INTO syncPending(recordType, recordID, isDeletion)
                SELECT ?, id, 0 FROM \(type.tableName)
                """, arguments: [type.rawValue])
        }
    }

    /// Deletes the synced library (profiles, spaces, sidebar, archive, devices) and all sync state, without queueing the
    /// deletions: used when another iCloud account takes over this device. History stays (it never syncs).
    public func deleteSyncedLibrary() throws {
        try writer.write { db in
            for type in SyncRecordType.allCases { try db.execute(sql: "DELETE FROM \(type.tableName)") }
            try db.execute(sql: """
                DELETE FROM syncState; DELETE FROM syncRecordMeta; DELETE FROM syncPending;
                DELETE FROM syncFieldState; DELETE FROM syncPeer
                """)
        }
    }

    /// Forgets the engine's state only, so the next engine starts fresh against whichever account is signed in.
    public func clearSyncEngineState() throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM syncState WHERE key = ?", arguments: [Self.engineStateKey])
        }
    }

    /// The iCloud user record name this library last synced with.
    static let cloudUserKey = "cloudUser"
    /// The CloudKit environment ("Development" or "Production") that account's library last synced with.
    static let cloudEnvironmentKey = "cloudEnvironment"
    /// Set when the user deleted Boaz's iCloud data; sync stays off until they ask for it again.
    static let cloudPurgedKey = "cloudPurged"

    // MARK: Outgoing

    /// The record to upload for a pending save, carrying the last known change tag. Nil if the row is gone.
    public func cloudRecord(for recordID: CKRecord.ID) throws -> CKRecord? {
        guard let (type, id) = SyncMapping.parse(recordID) else { return nil }
        return try writer.read { db in try Self.cloudRecord(type.recordType, id: id, in: db) }
    }

    private static func cloudRecord<R: SyncableRecord>(_: R.Type, id: String, in db: Database) throws -> CKRecord? {
        guard let value = try R.fetchOne(db, key: id) else { return nil }
        let meta = try SyncRecordMeta.fetchOne(db, key: ["recordType": R.syncType.rawValue, "recordID": id])
        return SyncMapping.record(for: value, systemFields: meta?.systemFields)
    }

    /// Records the server's copy of uploaded records. A record edited again while in flight stays queued and is
    /// returned so the caller can hand it back to the engine.
    public func didSave(serverRecords: [CKRecord]) async throws -> [SyncPendingChange] {
        try await writer.write { db in
            var requeue: [SyncPendingChange] = []
            for record in serverRecords {
                guard let (type, id) = SyncMapping.parse(record.recordID) else { continue }
                if let change = try Self.didSave(type.recordType, record: record, id: id, in: db) { requeue.append(change) }
            }
            return requeue
        }
    }

    private static func didSave<R: SyncableRecord>(_: R.Type, record: CKRecord, id: String, in db: Database) throws
        -> SyncPendingChange? {
        let sent = try? R(cloudRecord: record)
        try storeMeta(record, id: id, base: sent, in: db)
        guard let pending = try SyncPendingChange.fetchOne(db, key: ["recordType": R.syncType.rawValue, "recordID": id])
        else { return nil }
        if !pending.isDeletion, let sent, let local = try R.fetchOne(db, key: id),
           abs(local.modifiedAt.timeIntervalSince(sent.modifiedAt)) < 0.001,
           (local.deletedAt == nil) == (sent.deletedAt == nil) {
            try pending.delete(db)
            return nil
        }
        return pending
    }

    /// Forgets records the server confirmed as deleted.
    public func didDelete(recordIDs: [CKRecord.ID]) async throws {
        try await writer.write { db in
            for recordID in recordIDs {
                guard let (type, id) = SyncMapping.parse(recordID) else { continue }
                let key: [String: any DatabaseValueConvertible] = ["recordType": type.rawValue, "recordID": id]
                _ = try SyncRecordMeta.deleteOne(db, key: key)
                try SyncPendingChange.filter(key: key).filter(Column("isDeletion") == true).deleteAll(db)
            }
        }
    }

    /// Drops change tags for records the server no longer knows (zone or record gone), so the next upload creates them.
    public func clearSystemFields(_ recordIDs: [CKRecord.ID]) async throws {
        try await writer.write { db in
            for recordID in recordIDs {
                guard let (type, id) = SyncMapping.parse(recordID) else { continue }
                _ = try SyncRecordMeta.deleteOne(db, key: ["recordType": type.rawValue, "recordID": id])
            }
        }
    }

    // MARK: Incoming

    /// Applies server changes without queueing them for upload. Records with unsent local edits are merged with
    /// `SyncMerge`; when the local side contributes something the server lacks, the record stays queued and is
    /// returned for re-upload. Parents whose children ended up crowded are rebalanced (as a local, synced edit).
    @discardableResult
    /// Runs on the database's queue: a fetch batch of a few hundred records takes ~100 ms.
    public func applyServerChanges(modified: [CKRecord], deleted: [CKRecord.ID] = []) async throws
        -> [SyncPendingChange] {
        try await writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO syncSuppress(id) VALUES (1)")
            var requeue: [SyncPendingChange] = []
            var parents = Set<String>(), profiles = Set<String>()
            for record in modified {
                guard let (type, id) = SyncMapping.parse(record.recordID) else { continue }
                let outcome = try Self.apply(type.recordType, record: record, id: id, in: db)
                if let change = outcome.requeue { requeue.append(change) }
                parents.formUnion(outcome.parents)
                profiles.formUnion(outcome.profiles)
            }
            for recordID in deleted {
                guard let (type, id) = SyncMapping.parse(recordID) else { continue }
                let key: [String: any DatabaseValueConvertible] = ["recordType": type.rawValue, "recordID": id]
                try db.execute(sql: "DELETE FROM \(type.tableName) WHERE id = ?", arguments: [id])
                _ = try SyncRecordMeta.deleteOne(db, key: key)
                _ = try SyncPendingChange.deleteOne(db, key: key)
            }
            try db.execute(sql: "DELETE FROM syncSuppress")

            let now = Date.now
            try Self.breakParentLoops(from: parents, at: now, in: db)
            for parent in parents { _ = try Self.rebalanceChildren(of: parent, force: false, at: now, in: db) }
            for profile in profiles { _ = try Self.rebalanceSpaces(of: profile, force: false, at: now, in: db) }
            return requeue
        }
    }

    private struct ApplyOutcome {
        var requeue: SyncPendingChange?
        var parents: [String] = []
        var profiles: [String] = []
    }

    private static func apply<R: SyncableRecord>(_: R.Type, record: CKRecord, id: String, in db: Database) throws
        -> ApplyOutcome {
        // A record this build can't read (another version, or a bad copy) is skipped: throwing would lose the whole
        // batch, and the engine would fetch the same batch again forever.
        guard var server = try? R(cloudRecord: record), server.survivesStorage, server.hasOnlyWebAddresses
        else { return ApplyOutcome() }
        let local = try R.fetchOne(db, key: id)
        if let local { server.keepDeviceLocalFields(from: local) }
        let key: [String: any DatabaseValueConvertible] = ["recordType": R.syncType.rawValue, "recordID": id]
        let base = try SyncRecordMeta.fetchOne(db, key: key)?.base.flatMap { try? JSONDecoder().decode(R.self, from: $0) }
        try storeMeta(record, id: id, base: server, in: db)

        let pending = try SyncPendingChange.fetchOne(db, key: key)
        var outcome = ApplyOutcome()
        outcome.parents = [local, server].compactMap { ($0 as? SidebarItem)?.parentID }
        outcome.profiles = [local, server].compactMap { ($0 as? Space)?.profileID }

        switch (pending, local) {
        case let (pending?, local?) where !pending.isDeletion:
            let merged = SyncMerge.resolve(local: local, server: server, base: base)
            if merged != local { try merged.save(db) }
            if merged == server { try pending.delete(db) } else { outcome.requeue = pending }
        case let (pending?, nil) where pending.isDeletion:
            // Deleted here (tombstone purge) while the server still has it: the purge wins.
            outcome.requeue = pending
        default:
            // Nothing unsent here, so the server copy is the truth, even if this device's clock says otherwise.
            if local != server { try server.save(db) }
            if let pending { try pending.delete(db) }
        }
        return outcome
    }

    private static func storeMeta<R: SyncableRecord>(_ record: CKRecord, id: String, base: R?, in db: Database) throws {
        try SyncRecordMeta(recordType: R.syncType.rawValue, recordID: id,
                           systemFields: SyncMapping.encodeSystemFields(record),
                           base: base.flatMap { try? JSONEncoder().encode($0) }).save(db)
    }

    // MARK: Tombstones

    /// Hard-deletes tombstones older than `age` that were already synced (CloudKit or folder log) with nothing unsent.
    /// Arc-imported rows keep theirs: re-importing from Arc must not bring back what was removed in Boaz.
    /// The delete is queued like any local change, so the engine removes the CloudKit record too.
    @discardableResult
    public func purgeTombstones(olderThan age: TimeInterval = 30 * 24 * 3600, now: Date = .now) async throws -> Int {
        let cutoff = now.addingTimeInterval(-age)
        return try await writer.write { db in
            var count = 0
            for type in SyncRecordType.allCases {
                try db.execute(sql: """
                    DELETE FROM \(type.tableName)
                    WHERE deletedAt IS NOT NULL AND deletedAt < ?
                      AND id NOT LIKE 'arc-%'
                      AND id IN (SELECT recordID FROM syncRecordMeta WHERE recordType = ?
                                 UNION SELECT recordID FROM syncFieldState WHERE recordType = ?)
                      AND id NOT IN (SELECT recordID FROM syncPending WHERE recordType = ?)
                    """, arguments: [cutoff, type.rawValue, type.rawValue, type.rawValue])
                count += db.changesCount
            }
            return count
        }
    }
}
