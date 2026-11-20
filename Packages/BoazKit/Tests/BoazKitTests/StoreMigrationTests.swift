import Foundation
import GRDB
import Testing
@testable import BoazKit

@Suite("Store migrations")
struct StoreMigrationTests {
    private func temporaryDatabaseURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BoazKitTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("boaz.sqlite")
    }

    @Test func freshStoreRunsEveryMigration() throws {
        let store = try BoazStore.inMemory()
        let tables = try store.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table'")
        }
        for expected in ["profile", "space", "sidebarItem", "archiveItem", "historyVisit",
                         "syncState", "syncPending", "syncRecordMeta", "syncFieldState", "syncPeer",
                         "device", "tabEngineChoice", "siteEngineRule", "siteEngineRuleRecord",
                         "protectedEngineSeed", "liveFolderState"] {
            #expect(tables.contains(expected), "missing table \(expected)")
        }
        // And a migrated store is immediately usable.
        #expect(try store.isEmpty())
    }

    @Test func storeFromBeforeSyncMigratesAndQueuesExistingRows() throws {
        let url = try temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // The v1 schema, as the first shipped migration created it.
        do {
            let queue = try DatabaseQueue(path: url.path)
            try queue.write { db in
                try db.execute(sql: """
                    CREATE TABLE profile (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL,
                        dataStoreID BLOB NOT NULL, isDefault INTEGER NOT NULL,
                        modifiedAt TEXT NOT NULL, deletedAt TEXT);
                    CREATE TABLE space (id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL,
                        icon TEXT, themeJSON BLOB, profileID TEXT NOT NULL, position REAL NOT NULL,
                        modifiedAt TEXT NOT NULL, deletedAt TEXT);
                    CREATE TABLE sidebarItem (id TEXT NOT NULL PRIMARY KEY, spaceID TEXT,
                        profileID TEXT NOT NULL, parentID TEXT, kind TEXT NOT NULL, containerKind TEXT,
                        title TEXT, url TEXT, isUnread INTEGER NOT NULL, isExpanded INTEGER NOT NULL,
                        position REAL NOT NULL, createdAt TEXT NOT NULL, lastActiveAt TEXT,
                        modifiedAt TEXT NOT NULL, deletedAt TEXT);
                    CREATE TABLE archiveItem (id TEXT NOT NULL PRIMARY KEY, profileID TEXT NOT NULL,
                        spaceID TEXT, title TEXT, url TEXT NOT NULL, archivedAt TEXT NOT NULL,
                        reason TEXT NOT NULL, modifiedAt TEXT NOT NULL, deletedAt TEXT);
                    CREATE INDEX idx_space_profileID ON space(profileID);
                    CREATE INDEX idx_sidebarItem_spaceID ON sidebarItem(spaceID);
                    CREATE INDEX idx_sidebarItem_parentID ON sidebarItem(parentID);
                    CREATE INDEX idx_archiveItem_archivedAt ON archiveItem(archivedAt);
                    """)
                try db.execute(sql: """
                    INSERT INTO space (id, title, icon, themeJSON, profileID, position, modifiedAt, deletedAt)
                    VALUES ('s1', 'Old Space', NULL, NULL, 'p1', 0, '2026-01-01 00:00:00.000', NULL);
                    INSERT INTO sidebarItem (id, spaceID, profileID, parentID, kind, containerKind,
                        title, url, isUnread, isExpanded, position, createdAt, lastActiveAt, modifiedAt, deletedAt)
                    VALUES ('tab1', 's1', 'p1', NULL, 'tab', NULL, 'Example', 'https://example.com',
                        0, 1, 0, '2026-01-01 00:00:00.000', NULL, '2026-01-01 00:00:00.000', NULL);
                    """)
                // The v1 migration ran to make this database; later migrations must run, not v1 again.
                try db.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
                try db.execute(sql: "INSERT INTO grdb_migrations (identifier) VALUES ('v1')")
            }
            try queue.close()
        }

        // Opening through BoazStore migrates v2…v9 over the old database.
        let store = try BoazStore(writer: DatabaseQueue(path: url.path))
        let sidebar = try store.sidebar()
        #expect(sidebar.spaces.map(\.id) == ["s1"])
        #expect(sidebar.items.map(\.id) == ["tab1"])
        #expect(sidebar.items.first?.title == "Example")

        // The sync migration backfills the pending queue with what was already there.
        let pending = Set(try store.pendingSyncChanges().map { "\($0.recordType):\($0.recordID)" })
        #expect(pending.contains("Space:s1"))
        #expect(pending.contains("SidebarItem:tab1"))

        // New writes land in the migrated schema (v5 and v9 added these columns).
        var tab = try #require(sidebar.items.first)
        tab.deviceID = "d1"
        try store.save([tab])
        #expect(try store.sidebar().items.first?.deviceID == "d1")
    }
}
