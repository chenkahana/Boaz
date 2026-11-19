import Foundation
import Testing
@testable import BoazKit

@Suite("Sync pending queue")
struct StoreSyncQueueTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func profile(id: String = "p1") -> Profile {
        Profile(id: id, name: "Personal", isDefault: true, modifiedAt: t0)
    }

    @Test func insertUpdateDeleteQueueChanges() throws {
        let store = try BoazStore.inMemory()
        var record = profile()
        try store.save([record])
        var pending = try store.pendingSyncChanges()
        #expect(pending == [SyncPendingChange(.profile, "p1")])

        record.name = "Renamed"
        try store.save([record])
        pending = try store.pendingSyncChanges()
        #expect(pending == [SyncPendingChange(.profile, "p1")])

        try store.writer.write { db in
            _ = try Profile.deleteOne(db, key: "p1")
        }
        pending = try store.pendingSyncChanges()
        #expect(pending == [SyncPendingChange(.profile, "p1", isDeletion: true)])
    }

    @Test func historyNeverQueues() async throws {
        let store = try BoazStore.inMemory()
        store.recordVisit(profileID: "p1", url: URL(string: "https://example.com")!, title: "Example", at: t0)
        await store.waitForQueuedWrites()
        #expect(try store.pendingSyncChanges().isEmpty)
        #expect(try await store.history().count == 1)
    }

    @Test func localEngineChoicesNeverQueue() throws {
        let store = try BoazStore.inMemory()
        try store.setTabEngine(.chromium, tabID: "tab1", profileID: "p1")
        #expect(try store.pendingSyncChanges().isEmpty)
    }

    @Test func queueAllForUploadRequeuesEverything() throws {
        let store = try BoazStore.inMemory()
        try store.save([profile()])
        try store.resetSyncState(reuploadAll: false)
        #expect(try store.pendingSyncChanges().isEmpty)
        try store.queueAllForUpload()
        #expect(try store.pendingSyncChanges() == [SyncPendingChange(.profile, "p1")])
    }

    @Test func resetSyncStateReuploadQueuesTombstonesToo() throws {
        let store = try BoazStore.inMemory()
        try store.save([profile()])
        try store.writer.write { db in
            var record = try #require(try Profile.fetchOne(db, key: "p1"))
            record.deletedAt = t0
            try record.update(db)
        }
        try store.resetSyncState(reuploadAll: true)
        // Re-upload queues the row as a save; the tombstone is a property of the record itself.
        #expect(try store.pendingSyncChanges() == [SyncPendingChange(.profile, "p1")])
    }

    @Test func deleteSyncedLibraryWipesRecordsAndSyncState() throws {
        let store = try BoazStore.inMemory()
        try store.save([profile()])
        try store.setTabEngine(.webkit, tabID: "tab1", profileID: "p1")
        try store.deleteSyncedLibrary()
        #expect(try store.sidebar().profiles.isEmpty)
        #expect(try store.pendingSyncChanges().isEmpty)
        // Tab engine choices are device-local: they survive an account wipe.
        #expect(try store.tabEngine(tabID: "tab1", profileID: "p1") == .webkit)
    }
}
