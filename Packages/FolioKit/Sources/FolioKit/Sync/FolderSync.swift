import Foundation
import GRDB
import Observation
import os

// Folder transport: devices sync through a folder the user picks (iCloud Drive/Folio), no CloudKit entitlement needed.
//
//   <folder>/devices/<deviceID>/0000000001.json   append-only change logs, written only by that device
//   <folder>/devices/<deviceID>/snapshot.json     that device's full state, for bootstrapping and after compaction
//
// Each device reads every other device's logs from its own cursor (`syncPeer`) and merges entries with
// `RecordState.merge`, so no file is ever written by two devices and arrival order doesn't matter.

/// One record in a log or snapshot. `state == nil` is a hard delete (tombstone purge).
public struct FolderEntry: Codable, Hashable, Sendable {
    public var type: String
    public var id: String
    public var state: RecordState?
}

public struct FolderTouched: Sendable {
    public var parents: Set<String> = []
    public var profiles: Set<String> = []
    mutating func formUnion(_ other: FolderTouched) {
        parents.formUnion(other.parents); profiles.formUnion(other.profiles)
    }
}

public struct FolderLogFile: Codable, Sendable {
    public var device: String
    public var seq: Int
    public var entries: [FolderEntry]
}

// MARK: - Store side

extension FolioStore {
    func syncValue(_ key: String, in db: Database) throws -> String? {
        try Data.fetchOne(db, sql: "SELECT value FROM syncState WHERE key = ?", arguments: [key])
            .map { String(decoding: $0, as: UTF8.self) }
    }

    func setSyncValue(_ value: String?, for key: String, in db: Database) throws {
        if let value {
            try db.execute(sql: "INSERT OR REPLACE INTO syncState(key, value) VALUES (?, ?)", arguments: [key, Data(value.utf8)])
        } else {
            try db.execute(sql: "DELETE FROM syncState WHERE key = ?", arguments: [key])
        }
    }

    /// This device's id in the sync folder, created on first use.
    public func syncDeviceID() throws -> String {
        try writer.write { db in
            if let id = try syncValue("deviceID", in: db) { return id }
            let id = UUID().uuidString
            try setSyncValue(id, for: "deviceID", in: db)
            return id
        }
    }

    func syncSetting(_ key: String) -> String? { try? writer.read { db in try syncValue(key, in: db) } }
    func setSyncSetting(_ value: String?, for key: String) throws { try writer.write { db in try setSyncValue(value, for: key, in: db) } }

    private static func fieldState(_ type: SyncRecordType, _ id: String, in db: Database) throws -> RecordState? {
        try Data.fetchOne(db, sql: "SELECT state FROM syncFieldState WHERE recordType = ? AND recordID = ?",
                          arguments: [type.rawValue, id])
            .flatMap { try? JSONDecoder().decode(RecordState.self, from: $0) }
    }

    private static func setFieldState(_ state: RecordState?, _ type: SyncRecordType, _ id: String, in db: Database) throws {
        if let state {
            try db.execute(sql: "INSERT OR REPLACE INTO syncFieldState(recordType, recordID, state) VALUES (?, ?, ?)",
                           arguments: [type.rawValue, id, try JSONEncoder().encode(state)])
        } else {
            try db.execute(sql: "DELETE FROM syncFieldState WHERE recordType = ? AND recordID = ?", arguments: [type.rawValue, id])
        }
    }

    /// Turns the pending queue into one log file. `write` runs inside the transaction: if it throws, nothing is
    /// dequeued. Returns the sequence number written, or nil when there was nothing to send.
    @discardableResult
    public func flushToFolderLog(device: String, write: (FolderLogFile) throws -> Void) throws -> Int? {
        try writer.write { db in
            let pending = try SyncPendingChange.fetchAll(db)
            guard !pending.isEmpty else { return nil }
            var entries: [FolderEntry] = []
            for change in pending {
                guard let type = SyncRecordType(rawValue: change.recordType) else { continue }
                if let entry = try Self.flushEntry(type.recordType, id: change.recordID, in: db) { entries.append(entry) }
            }
            try SyncPendingChange.deleteAll(db)
            guard !entries.isEmpty else { return nil }
            let seq = (Int(try syncValue("folderSeq", in: db) ?? "0") ?? 0) + 1
            try write(FolderLogFile(device: device, seq: seq, entries: entries))
            try setSyncValue(String(seq), for: "folderSeq", in: db)
            return seq
        }
    }

    private static func flushEntry<R: SyncableRecord>(_: R.Type, id: String, in db: Database) throws -> FolderEntry? {
        let previous = try fieldState(R.syncType, id, in: db)
        guard let row = try R.fetchOne(db, key: id) else {
            guard previous != nil else { return nil }
            try setFieldState(nil, R.syncType, id, in: db)
            return FolderEntry(type: R.syncType.rawValue, id: id, state: nil)
        }
        let state = RecordState.stamped(try RecordState.fields(of: row), over: previous, groups: R.mergeGroups)
        try setFieldState(state, R.syncType, id, in: db)
        let value = try state.value(R.self)
        if value != row { try value.save(db) } // re-queued here, dequeued with the rest of the batch
        return FolderEntry(type: R.syncType.rawValue, id: id, state: state)
    }

    /// Merges a peer's entries without queueing them, then records how far that peer's log has been read.
    /// Unsent local edits are folded into the merge and stay queued. Returns the parents (sidebar parents and
    /// profiles) whose children changed, for `rebalanceFolderParents` once the whole pass is applied.
    @discardableResult
    public func applyFolderEntries(_ entries: [FolderEntry], from peer: String, cursor: Int) throws -> FolderTouched {
        try writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO syncSuppress(id) VALUES (1)")
            var parents = Set<String>(), profiles = Set<String>()
            for entry in entries {
                guard let type = SyncRecordType(rawValue: entry.type) else { continue }
                let touched = try Self.applyEntry(type.recordType, entry, in: db)
                parents.formUnion(touched.parents)
                profiles.formUnion(touched.profiles)
            }
            try db.execute(sql: "DELETE FROM syncSuppress")
            try db.execute(sql: "INSERT OR REPLACE INTO syncPeer(deviceID, cursor) VALUES (?, ?)", arguments: [peer, cursor])
            return FolderTouched(parents: parents, profiles: profiles)
        }
    }

    /// Renumbers crowded siblings (a local, synced edit). Run after all of a pass's peer files are applied, so
    /// transient ties between an old snapshot and newer logs don't cause churn.
    public func rebalanceFolderParents(_ touched: FolderTouched) throws {
        guard !touched.parents.isEmpty || !touched.profiles.isEmpty else { return }
        try writer.write { db in
            let now = Date.now
            try Self.breakParentLoops(from: touched.parents, at: now, in: db)
            for parent in touched.parents { _ = try Self.rebalanceChildren(of: parent, force: false, at: now, in: db) }
            for profile in touched.profiles { _ = try Self.rebalanceSpaces(of: profile, force: false, at: now, in: db) }
        }
    }

    private static func applyEntry<R: SyncableRecord>(_: R.Type, _ entry: FolderEntry, in db: Database) throws
        -> (parents: [String], profiles: [String]) {
        let row = try R.fetchOne(db, key: entry.id)
        guard let remote = entry.state else {
            if row != nil { try db.execute(sql: "DELETE FROM \(R.syncType.tableName) WHERE id = ?", arguments: [entry.id]) }
            try setFieldState(nil, R.syncType, entry.id, in: db)
            _ = try SyncPendingChange.deleteOne(db, key: ["recordType": R.syncType.rawValue, "recordID": entry.id])
            return ([], [])
        }
        var current = try fieldState(R.syncType, entry.id, in: db)
        if let row {
            let fields = try RecordState.fields(of: row)
            if fields != current?.fields { current = RecordState.stamped(fields, over: current, groups: R.mergeGroups) }
        }
        let merged = RecordState.merge(current ?? remote, remote, groups: R.mergeGroups)
        // A peer's record this build can't read is skipped before anything is stored: throwing would fail every
        // pass, and a stored unreadable state would also break this device's own flushes.
        guard var value = try? merged.value(R.self), value.survivesStorage else { return ([], []) }
        try setFieldState(merged, R.syncType, entry.id, in: db)
        if let row { value.keepDeviceLocalFields(from: row) }
        if value != row { try value.save(db) }
        let records = [row, value].compactMap { $0 }
        return (records.compactMap { ($0 as? SidebarItem)?.parentID }, records.compactMap { ($0 as? Space)?.profileID })
    }

    /// A different folder starts from scratch: peers are read from their snapshots and ours is rewritten. Every
    /// record is queued, since the queue may have been drained by another transport (iCloud) and the new folder
    /// has nothing of this library yet. Unchanged fields keep their stamps.
    public func resetFolderSyncProgress() throws {
        try writer.write { db in
            try db.execute(sql: "DELETE FROM syncPeer")
            try setSyncValue(nil, for: "folderSnapshotSeq", in: db)
            try Self.queueAll(in: db)
        }
    }

    public func folderPeerCursor(_ peer: String) -> Int {
        (try? writer.read { db in try Int.fetchOne(db, sql: "SELECT cursor FROM syncPeer WHERE deviceID = ?", arguments: [peer]) })
            .flatMap { $0 } ?? 0
    }

    /// Every synced record's state, for a snapshot.
    public func folderSnapshot(device: String) throws -> FolderLogFile {
        try writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT recordType, recordID, state FROM syncFieldState")
            let entries = rows.compactMap { row -> FolderEntry? in
                guard let data: Data = row["state"], let state = try? JSONDecoder().decode(RecordState.self, from: data)
                else { return nil }
                return FolderEntry(type: row["recordType"], id: row["recordID"], state: state)
            }
            return FolderLogFile(device: device, seq: Int(try syncValue("folderSeq", in: db) ?? "0") ?? 0, entries: entries)
        }
    }
}

// MARK: - One sync pass (file I/O, off the main actor)

struct FolderSyncPass: Sendable {
    let store: FolioStore
    let root: URL
    let device: String
    let presenter: FolderPresenter?

    static let snapshotName = "snapshot.json"
    static let snapshotEvery = 50

    struct Outcome: Sendable { var waitingForDownloads = false }

    var devicesDir: URL { root.appendingPathComponent("devices", isDirectory: true) }

    static func logName(_ seq: Int) -> String { String(format: "%010d.json", seq) }

    func run() throws -> Outcome {
        let own = devicesDir.appendingPathComponent(device, isDirectory: true)
        try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)

        try store.flushToFolderLog(device: device) { file in
            try write(try JSONEncoder().encode(file), to: own.appendingPathComponent(Self.logName(file.seq)))
        }

        var outcome = Outcome()
        var touched = FolderTouched()
        let peers = (try? FileManager.default.contentsOfDirectory(atPath: devicesDir.path)) ?? []
        for peer in peers where peer != device && !peer.hasPrefix(".") {
            if try readPeer(peer, touched: &touched) { outcome.waitingForDownloads = true }
        }
        try store.rebalanceFolderParents(touched)
        // Remote changes may have queued local edits (rebalancing): send them now rather than next pass.
        try store.flushToFolderLog(device: device) { file in
            try write(try JSONEncoder().encode(file), to: own.appendingPathComponent(Self.logName(file.seq)))
        }
        try snapshotIfDue(own)
        return outcome
    }

    /// Reads one peer's new log files in order. Returns true when it stopped at a file still downloading.
    private func readPeer(_ peer: String, touched: inout FolderTouched) throws -> Bool {
        let dir = devicesDir.appendingPathComponent(peer, isDirectory: true)
        var logs: [Int: (url: URL, placeholder: Bool)] = [:]
        var snapshot: (url: URL, placeholder: Bool)?
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] {
            // Not-yet-downloaded iCloud items show up as ".<name>.icloud".
            let placeholder = name.hasPrefix(".") && name.hasSuffix(".icloud")
            let real = placeholder ? String(name.dropFirst().dropLast(".icloud".count)) : name
            let url = dir.appendingPathComponent(real)
            if real == Self.snapshotName { snapshot = (url, placeholder) }
            else if real.hasSuffix(".json"), real.count == 15, let seq = Int(real.prefix(10)) { logs[seq] = (url, placeholder) }
        }

        var cursor = store.folderPeerCursor(peer)
        // `&+`: a peer's snapshot can claim any seq, Int.max included.
        if cursor == 0 || logs[cursor &+ 1] == nil, let snapshot {
            // New device, or the peer compacted logs this device never read: start from its snapshot.
            guard let file: FolderLogFile = load(snapshot) else { return true }
            if file.seq > cursor {
                touched.formUnion(try store.applyFolderEntries(file.entries, from: peer, cursor: file.seq))
                cursor = file.seq
            }
        }
        while let next = logs[cursor &+ 1] {
            guard let file: FolderLogFile = load(next), file.seq == cursor &+ 1 else { return true }
            touched.formUnion(try store.applyFolderEntries(file.entries, from: peer, cursor: file.seq))
            cursor = file.seq
        }
        return false
    }

    /// Reads a peer file; nil while it is still downloading or only partly written.
    private func load<T: Decodable>(_ item: (url: URL, placeholder: Bool)) -> T? {
        if item.placeholder {
            try? FileManager.default.startDownloadingUbiquitousItem(at: item.url)
            return nil
        }
        guard let data = try? read(item.url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func snapshotIfDue(_ own: URL) throws {
        let snapshot = try store.folderSnapshot(device: device)
        let last = Int(store.syncSetting("folderSnapshotSeq") ?? "0") ?? 0
        let missing = !FileManager.default.fileExists(atPath: own.appendingPathComponent(Self.snapshotName).path)
        guard snapshot.seq > 0, missing || last == 0 || snapshot.seq - last >= Self.snapshotEvery else { return }
        try write(try JSONEncoder().encode(snapshot), to: own.appendingPathComponent(Self.snapshotName))
        try store.setSyncSetting(String(snapshot.seq), for: "folderSnapshotSeq")
        // Keep one snapshot interval of logs; a peer that falls further behind restarts from the snapshot.
        for seq in stride(from: 1, through: last, by: 1) {
            let url = own.appendingPathComponent(Self.logName(seq))
            if FileManager.default.fileExists(atPath: url.path) { try? delete(url) }
        }
    }

    // MARK: Coordinated file access

    private func read(_ url: URL) throws -> Data {
        var coordinatorError: NSError?, result: Result<Data, any Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator(filePresenter: presenter).coordinate(readingItemAt: url, options: [], error: &coordinatorError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinatorError { throw coordinatorError }
        return try result.get()
    }

    private func write(_ data: Data, to url: URL) throws {
        var coordinatorError: NSError?, result: Result<Void, any Error> = .success(())
        NSFileCoordinator(filePresenter: presenter).coordinate(writingItemAt: url, options: .forReplacing,
                                                               error: &coordinatorError) { url in
            result = Result { try data.write(to: url, options: .atomic) }
        }
        if let coordinatorError { throw coordinatorError }
        try result.get()
    }

    private func delete(_ url: URL) throws {
        var coordinatorError: NSError?, result: Result<Void, any Error> = .success(())
        NSFileCoordinator(filePresenter: presenter).coordinate(writingItemAt: url, options: .forDeleting,
                                                               error: &coordinatorError) { url in
            result = Result { try FileManager.default.removeItem(at: url) }
        }
        if let coordinatorError { throw coordinatorError }
        try result.get()
    }
}

/// Tells the app when another device's files change in the sync folder.
final class FolderPresenter: NSObject, NSFilePresenter, @unchecked Sendable {
    let presentedItemURL: URL?
    let presentedItemOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let onChange: @Sendable () -> Void

    init(url: URL, onChange: @escaping @Sendable () -> Void) {
        presentedItemURL = url
        self.onChange = onChange
    }

    func presentedItemDidChange() { onChange() }
    func presentedSubitemDidChange(at url: URL) { onChange() }
    func presentedSubitemDidAppear(at url: URL) { onChange() }
}

// MARK: - FolioSync

/// Keeps this device's library in sync with the user's other devices through a shared folder (iCloud Drive/Folio).
/// Local writes are captured by database triggers, so every write path syncs. History and incognito never do.
@MainActor @Observable
public final class FolioSync {
    public enum Status: Equatable, Sendable {
        case idle
        case noFolder
        case syncing
        case error(String)
        case upToDate(Date)

        public var summary: String {
            switch self {
            case .idle: "Not synced yet"
            case .noFolder: "Choose a sync folder to keep your devices in sync"
            case .syncing: "Syncing…"
            case .error(let message): "Sync failed: \(message)"
            case .upToDate(let date): "Up to date (\(date.formatted(date: .omitted, time: .shortened)))"
            }
        }
    }

    public private(set) var status: Status = .idle
    /// The folder in use, if any.
    public private(set) var folderURL: URL?

    @ObservationIgnored private let store: FolioStore
    @ObservationIgnored private var started = false
    @ObservationIgnored private var pass: Task<Void, Never>?
    @ObservationIgnored private var passRequested = false
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var presenter: FolderPresenter?
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    private static let log = Logger(subsystem: "com.chenkahana.folio", category: "sync")
    static let bookmarkKey = "folderBookmark"

    public init(store: FolioStore) {
        self.store = store
    }

    /// Resolves the saved folder, watches it and the local change queue, and runs a first pass. Safe to call again.
    public func start() async {
        if !started {
            started = true
            _ = try? await store.purgeTombstones()
            resolveFolder()
            let store = store
            tasks.append(Task { [weak self] in
                do {
                    for try await queue in store.pendingSyncChangeUpdates() where !queue.isEmpty {
                        self?.schedule(after: .seconds(2))
                    }
                } catch {}
            })
            tasks.append(Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(60))
                    await self?.syncNow()
                }
            })
        }
        await syncNow()
    }

    /// Uses `url` (picked by the user) as the sync folder from now on and syncs right away.
    public func setFolder(_ url: URL) async throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        #endif
        try store.setSyncSetting(bookmark.base64EncodedString(), for: Self.bookmarkKey)
        try store.resetFolderSyncProgress()
        resolveFolder()
        await syncNow()
    }

    /// Runs a pass now (or right after the one in progress) and returns once passes are done.
    public func syncNow() async {
        guard let folderURL else { status = .noFolder; return }
        if let pass {
            passRequested = true
            return await pass.value
        }
        let task = Task { await runPasses(folderURL) }
        pass = task
        await task.value
        pass = nil
    }

    private func runPasses(_ folderURL: URL) async {
        status = .syncing
        let device: String
        do { device = try store.syncDeviceID() } catch { return fail(error) }
        var waiting = false
        repeat {
            passRequested = false
            let pass = FolderSyncPass(store: store, root: folderURL, device: device, presenter: presenter)
            let result = await Task.detached { Result { try pass.run() } }.value
            switch result {
            case .success(let outcome): waiting = outcome.waitingForDownloads
            case .failure(let error): return fail(error)
            }
        } while passRequested
        status = .upToDate(.now)
        if waiting { schedule(after: .seconds(5)) }
    }

    public func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        scheduled?.cancel()
        detachFolder()
        started = false
    }

    // MARK: Private

    private func fail(_ error: any Error) {
        Self.log.error("Folder sync failed: \(error, privacy: .public)")
        status = .error(error.localizedDescription)
    }

    private func schedule(after delay: Duration) {
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }

    private func resolveFolder() {
        detachFolder()
        var url: URL?
        if let encoded = store.syncSetting(Self.bookmarkKey), let data = Data(base64Encoded: encoded) {
            var stale = false
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = .withSecurityScope
            #else
            let options: URL.BookmarkResolutionOptions = []
            #endif
            do {
                let resolved = try URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
                if resolved.startAccessingSecurityScopedResource() { scopedURL = resolved }
                url = resolved
                if stale { Self.log.notice("Sync folder bookmark is stale; pick the folder again if sync fails") }
            } catch {
                Self.log.error("Sync folder bookmark unusable: \(error, privacy: .public)")
            }
        }
        folderURL = url
        guard let url else { status = .noFolder; return }
        let presenter = FolderPresenter(url: url.appendingPathComponent("devices", isDirectory: true)) { [weak self] in
            Task { @MainActor in self?.schedule(after: .seconds(1)) }
        }
        NSFileCoordinator.addFilePresenter(presenter)
        self.presenter = presenter
        Self.log.notice("Syncing through \(url.path, privacy: .public)")
    }

    private func detachFolder() {
        if let presenter { NSFileCoordinator.removeFilePresenter(presenter) }
        presenter = nil
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        folderURL = nil
    }
}

extension FolioStore {
    /// One synchronous pass without the app-level scheduling, for offline checks.
    @_spi(SyncTesting) public func runFolderSyncPass(root: URL, device: String) throws -> Bool {
        try FolderSyncPass(store: self, root: root, device: device, presenter: nil).run().waitingForDownloads
    }
}
