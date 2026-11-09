import Foundation
import GRDB

/// Local source of truth. Both apps read and write here; `BoazSync` mirrors it to CloudKit.
public final class BoazStore: Sendable {
    public let writer: any DatabaseWriter

    /// `migrate: false` is for app extensions: only the app process migrates the shared database.
    public init(writer: any DatabaseWriter, migrate: Bool = true) throws {
        self.writer = writer
        if migrate { try Self.migrator.migrate(writer) }
    }

    /// On-disk store in Application Support/Boaz.
    /// iOS app, widgets and share extension share one database through this App Group.
    public static let appGroup = "group.com.chenkahana.boaz"

    /// Opens the database in the App Group container when the entitlement is present, else in Application Support.
    /// Configured per GRDB's "Sharing a Database": the app and its extensions wait for each other's writes instead
    /// of failing with `SQLITE_BUSY`, and the iOS app suspends the database in the background
    /// (`Database.suspendNotification`) so it is never killed for holding a lock. Extensions pass `migrate: false`.
    public static func onDisk(appGroup: String? = nil, migrate: Bool = true) throws -> BoazStore {
        let base = try appGroup.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
        let dir = base.appendingPathComponent("Boaz", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.observesSuspensionNotifications = true
        let pool = try DatabasePool(path: dir.appendingPathComponent("boaz.sqlite").path, configuration: configuration)
        return try BoazStore(writer: pool, migrate: migrate)
    }

    /// Stops on-disk stores from taking new locks (iOS app going to the background), and lets them again.
    public static func suspendDatabases() { NotificationCenter.default.post(name: Database.suspendNotification, object: nil) }
    public static func resumeDatabases() { NotificationCenter.default.post(name: Database.resumeNotification, object: nil) }

    public static func inMemory() throws -> BoazStore {
        try BoazStore(writer: DatabaseQueue())
    }

    // MARK: Reads

    /// Live snapshot of the whole sidebar; emits on every committed change.
    public func sidebarUpdates() -> AsyncValueObservation<Sidebar> {
        ValueObservation.tracking(Sidebar.fetch).values(in: writer)
    }

    public func sidebar() throws -> Sidebar {
        try writer.read(Sidebar.fetch)
    }

    /// `sidebar()` read on the database's own queue: a large library takes ~100 ms to fetch, too long to block the
    /// main thread for.
    public func loadSidebar() async throws -> Sidebar {
        try await writer.read { try Sidebar.fetch($0) }
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
        // CloudKit sync bookkeeping. Triggers queue every local change to a synced table; writes applied from
        // the server run while `syncSuppress` holds a row (inside the same transaction), so they are not echoed back.
        migrator.registerMigration("v3-sync") { db in
            try db.create(table: "syncState") { t in
                t.primaryKey("key", .text)
                t.column("value", .blob).notNull()
            }
            try db.create(table: "syncPending") { t in
                t.column("recordType", .text).notNull()
                t.column("recordID", .text).notNull()
                t.column("isDeletion", .boolean).notNull()
                t.primaryKey(["recordType", "recordID"])
            }
            try db.create(table: "syncRecordMeta") { t in
                t.column("recordType", .text).notNull()
                t.column("recordID", .text).notNull()
                t.column("systemFields", .blob).notNull()
                t.column("base", .blob)
                t.primaryKey(["recordType", "recordID"])
            }
            try db.create(table: "syncSuppress") { t in
                t.primaryKey("id", .integer)
            }
            // The tables that existed at v3; later synced tables add their triggers in their own migration.
            for type in [SyncRecordType.profile, .space, .sidebarItem, .archiveItem] {
                try createSyncTriggers(for: type, in: db)
            }
        }
        // Folder transport: per-field stamped state of every synced record, and how far each peer's log was read.
        migrator.registerMigration("v4-folder-sync") { db in
            try db.create(table: "syncFieldState") { t in
                t.column("recordType", .text).notNull()
                t.column("recordID", .text).notNull()
                t.column("state", .blob).notNull()
                t.primaryKey(["recordType", "recordID"])
            }
            try db.create(table: "syncPeer") { t in
                t.primaryKey("deviceID", .text)
                t.column("cursor", .integer).notNull()
            }
        }
        // Today tabs belong to the device they were opened on; devices sync so the others can name them.
        migrator.registerMigration("v5-devices") { db in
            try db.alter(table: "sidebarItem") { t in t.add(column: "deviceID", .text) }
            try db.create(table: "device") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("platform", .text).notNull()
                t.column("lastSeenAt", .datetime).notNull()
                t.column("modifiedAt", .datetime).notNull()
                t.column("deletedAt", .datetime)
            }
            try createSyncTriggers(for: .device, in: db)
        }
        return migrator
    }

    /// Queues every local change to `type`'s table for upload (see `v3-sync`), and its existing rows.
    private static func createSyncTriggers(for type: SyncRecordType, in db: Database) throws {
        let table = type.tableName, name = type.rawValue
        let enqueue = "INSERT OR REPLACE INTO syncPending(recordType, recordID, isDeletion)"
        try db.execute(sql: """
            CREATE TRIGGER sync_\(table)_insert AFTER INSERT ON \(table)
            WHEN NOT EXISTS (SELECT 1 FROM syncSuppress)
            BEGIN \(enqueue) VALUES ('\(name)', NEW.id, 0); END;
            CREATE TRIGGER sync_\(table)_update AFTER UPDATE ON \(table)
            WHEN NOT EXISTS (SELECT 1 FROM syncSuppress)
            BEGIN
                \(enqueue) SELECT '\(name)', OLD.id, 1 WHERE OLD.id IS NOT NEW.id;
                \(enqueue) VALUES ('\(name)', NEW.id, 0);
            END;
            CREATE TRIGGER sync_\(table)_delete AFTER DELETE ON \(table)
            WHEN NOT EXISTS (SELECT 1 FROM syncSuppress)
            BEGIN \(enqueue) VALUES ('\(name)', OLD.id, 1); END;
            INSERT INTO syncPending(recordType, recordID, isDeletion) SELECT '\(name)', id, 0 FROM \(table);
            """)
    }
}

// MARK: - Ordering

extension BoazStore {
    /// Siblings closer than this get renumbered: repeated midpoint inserts eventually run out of `Double` precision.
    public static let minimumPositionGap = 1e-9

    /// Renumbers the live children of `parentID` to 0, 1, 2… in their current order (ties broken by id) when two
    /// neighbours sit closer than `minimumPositionGap`, or always when `force` is set. The rewrite is an ordinary
    /// local edit, so sync propagates it. Returns whether anything was renumbered.
    @discardableResult
    public func rebalancePositions(inParent parentID: String, force: Bool = false, at date: Date = .now) throws -> Bool {
        try writer.write { db in try Self.rebalanceChildren(of: parentID, force: force, at: date, in: db) }
    }

    /// Same as `rebalancePositions(inParent:)` for the spaces of one profile.
    @discardableResult
    public func rebalanceSpacePositions(profileID: String, force: Bool = false, at date: Date = .now) throws -> Bool {
        try writer.write { db in try Self.rebalanceSpaces(of: profileID, force: force, at: date, in: db) }
    }

    static func rebalanceChildren(of parentID: String, force: Bool, at date: Date, in db: Database) throws -> Bool {
        let children = try SidebarItem
            .filter(Column("parentID") == parentID && Column("deletedAt") == nil)
            .order(Column("position"), Column("id")).fetchAll(db)
        guard let positions = evenPositions(children.map(\.position), force: force) else { return false }
        for (var child, position) in zip(children, positions) where child.position != position {
            child.position = position
            child.modifiedAt = date
            try child.update(db)
        }
        return true
    }

    static func rebalanceSpaces(of profileID: String, force: Bool, at date: Date, in db: Database) throws -> Bool {
        let spaces = try Space
            .filter(Column("profileID") == profileID && Column("deletedAt") == nil)
            .order(Column("position"), Column("id")).fetchAll(db)
        guard let positions = evenPositions(spaces.map(\.position), force: force) else { return false }
        for (var space, position) in zip(spaces, positions) where space.position != position {
            space.position = position
            space.modifiedAt = date
            try space.update(db)
        }
        return true
    }

    /// Folders moved into each other on two devices (A into B on one, B into A on the other) end up parented in a
    /// loop, hidden on every device with everything inside them. Walking up from each of `parents`, a loop is cut
    /// at its smallest id, the same row on every device, which moves to the end of its space's pinned section (or
    /// its profile's favorites). The move is a local edit, so sync propagates it.
    static func breakParentLoops(from parents: some Sequence<String>, at date: Date, in db: Database) throws {
        for start in parents {
            var seen = Set<String>(), next: String? = start
            while let id = next, !seen.contains(id), let item = try SidebarItem.fetchOne(db, key: id),
                  item.deletedAt == nil, item.kind != .container {
                seen.insert(id)
                next = item.parentID
            }
            guard let repeated = next, seen.contains(repeated) else { continue }
            var loop: [String] = [repeated], id = repeated
            while let parent = try SidebarItem.fetchOne(db, key: id)?.parentID, parent != repeated { loop.append(parent); id = parent }
            guard var cut = try SidebarItem.fetchOne(db, key: loop.min()!) else { continue }
            let live = Column("kind") == SidebarItem.Kind.container.rawValue && Column("deletedAt") == nil
            let section = cut.spaceID.map {
                Column("spaceID") == $0 && Column("containerKind") == SidebarItem.ContainerKind.pinned.rawValue
            } ?? (Column("profileID") == cut.profileID && Column("containerKind") == SidebarItem.ContainerKind.favorites.rawValue)
            guard let destination = try SidebarItem.filter(live && section).order(Column("id")).fetchOne(db) else { continue }
            cut.parentID = destination.id
            cut.position = (try Double.fetchOne(db, sql: "SELECT MAX(position) FROM sidebarItem WHERE parentID = ? AND deletedAt IS NULL",
                                                arguments: [destination.id]) ?? -1) + 1
            cut.modifiedAt = date
            try cut.update(db)
        }
    }

    /// 0, 1, 2… when renumbering is due, else nil. `positions` must be sorted.
    static func evenPositions(_ positions: [Double], force: Bool) -> [Double]? {
        let crowded = zip(positions, positions.dropFirst()).contains { !($1 - $0 >= minimumPositionGap) }
        guard force || crowded else { return nil }
        return positions.indices.map(Double.init)
    }
}

/// Everything the sidebar renders, excluding tombstones, in display order.
public struct Sidebar: Equatable, Sendable {
    public var profiles: [Profile]
    public var spaces: [Space]
    public var items: [SidebarItem]
    public var devices: [Device]

    public init(profiles: [Profile] = [], spaces: [Space] = [], items: [SidebarItem] = [], devices: [Device] = []) {
        self.profiles = profiles; self.spaces = spaces; self.items = items; self.devices = devices
    }

    static func fetch(_ db: Database) throws -> Sidebar {
        Sidebar(
            profiles: try Profile.filter(Column("deletedAt") == nil).fetchAll(db),
            spaces: try Space.filter(Column("deletedAt") == nil).order(Column("position"), Column("id")).fetchAll(db),
            items: try SidebarItem.filter(Column("deletedAt") == nil).order(Column("position"), Column("id")).fetchAll(db),
            devices: try Device.filter(Column("deletedAt") == nil).order(Column("name"), Column("id")).fetchAll(db)
        )
    }

    /// A space's Today tabs as `deviceID` lists them: its own, plus those that recorded no device.
    public func todayTabs(in spaceID: String, onDevice deviceID: String) -> [SidebarItem] {
        guard let box = container(.unpinned, in: spaceID) else { return [] }
        return children(of: box.id).filter { $0.kind == .tab && ($0.deviceID == nil || $0.deviceID == deviceID) }
    }

    /// Every Today tab opened on `deviceID`, across spaces.
    public func todayTabs(openedOn deviceID: String) -> [SidebarItem] {
        let boxes = Set(items.lazy.filter { $0.containerKind == .unpinned }.map(\.id))
        return items.filter { $0.kind == .tab && $0.deviceID == deviceID && $0.parentID.map(boxes.contains) == true }
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
