import Foundation
import GRDB

/// Local source of truth. Both apps read and write here; CloudKit sync (Phase 2) mirrors it.
public final class FolioStore: Sendable {
    public let writer: any DatabaseWriter

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// On-disk store in Application Support/Folio.
    public static func onDisk() throws -> FolioStore {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: true)
            .appendingPathComponent("Folio", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try FolioStore(writer: DatabasePool(path: dir.appendingPathComponent("folio.sqlite").path))
    }

    public static func inMemory() throws -> FolioStore {
        try FolioStore(writer: DatabaseQueue())
    }

    // MARK: Reads

    /// Live snapshot of the whole sidebar; emits on every committed change.
    public func sidebarUpdates() -> AsyncValueObservation<Sidebar> {
        ValueObservation.tracking(Sidebar.fetch).values(in: writer)
    }

    public func sidebar() throws -> Sidebar {
        try writer.read(Sidebar.fetch)
    }

    // MARK: Writes

    public func save(_ records: [any PersistableRecord]) throws {
        try writer.write { db in
            for record in records { try record.save(db) }
        }
    }

    public func isEmpty() throws -> Bool {
        try writer.read { db in try Space.fetchCount(db) == 0 }
    }

    // MARK: Schema

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "profile") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("dataStoreID", .blob).notNull()
                t.column("isDefault", .boolean).notNull()
                t.column("modifiedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(table: "space") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("icon", .text)
                t.column("themeJSON", .blob)
                t.column("profileID", .text).notNull().indexed()
                t.column("position", .double).notNull()
                t.column("modifiedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(table: "sidebarItem") { t in
                t.primaryKey("id", .text)
                t.column("spaceID", .text).indexed()
                t.column("profileID", .text).notNull()
                t.column("parentID", .text).indexed()
                t.column("kind", .text).notNull()
                t.column("containerKind", .text)
                t.column("title", .text)
                t.column("url", .text)
                t.column("isUnread", .boolean).notNull()
                t.column("isExpanded", .boolean).notNull()
                t.column("position", .double).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("lastActiveAt", .datetime)
                t.column("modifiedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try db.create(table: "archiveItem") { t in
                t.primaryKey("id", .text)
                t.column("profileID", .text).notNull()
                t.column("spaceID", .text)
                t.column("title", .text)
                t.column("url", .text).notNull()
                t.column("archivedAt", .datetime).notNull().indexed()
                t.column("reason", .text).notNull()
                t.column("modifiedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
        }
        // History stays on this device: it is never synced.
        migrator.registerMigration("v2-history") { db in
            try db.create(table: "historyVisit") { t in
                t.primaryKey("id", .text)
                t.column("profileID", .text).notNull()
                t.column("url", .text).notNull().indexed()
                t.column("title", .text)
                t.column("visitedAt", .datetime).notNull().indexed()
            }
        }
        return migrator
    }
}

/// Everything the sidebar renders, excluding tombstones, in display order.
public struct Sidebar: Equatable, Sendable {
    public var profiles: [Profile]
    public var spaces: [Space]
    public var items: [SidebarItem]

    public init(profiles: [Profile] = [], spaces: [Space] = [], items: [SidebarItem] = []) {
        self.profiles = profiles; self.spaces = spaces; self.items = items
    }

    static func fetch(_ db: Database) throws -> Sidebar {
        Sidebar(
            profiles: try Profile.filter(Column("deletedAt") == nil).fetchAll(db),
            spaces: try Space.filter(Column("deletedAt") == nil).order(Column("position")).fetchAll(db),
            items: try SidebarItem.filter(Column("deletedAt") == nil).order(Column("position")).fetchAll(db)
        )
    }

    public func children(of parentID: String) -> [SidebarItem] {
        items.filter { $0.parentID == parentID }
    }

    public func container(_ kind: SidebarItem.ContainerKind, in spaceID: String) -> SidebarItem? {
        items.first { $0.kind == .container && $0.containerKind == kind && $0.spaceID == spaceID }
    }

    /// Position that places a new child after the existing ones.
    public func nextPosition(in parentID: String) -> Double {
        (children(of: parentID).map(\.position).max() ?? -1) + 1
    }

    /// Inserts or replaces an item locally, so the UI reflects a write before the observation fires.
    public mutating func upsert(_ item: SidebarItem) {
        items.removeAll { $0.id == item.id }
        if item.deletedAt == nil {
            let index = items.firstIndex { $0.parentID == item.parentID && $0.position > item.position } ?? items.endIndex
            items.insert(item, at: index)
        }
    }

    public func favoritesContainer(profileID: String) -> SidebarItem? {
        items.first { $0.containerKind == .favorites && $0.profileID == profileID }
    }

    public func favorites(profileID: String) -> [SidebarItem] {
        guard let container = items.first(where: { $0.containerKind == .favorites && $0.profileID == profileID })
        else { return [] }
        return children(of: container.id)
    }
}
