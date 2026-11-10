import Foundation
import GRDB

/// A page visit. Local only: history is never synced.
public struct HistoryVisit: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public var id: String
    public var profileID: String
    public var url: URL
    public var title: String?
    public var visitedAt: Date

    public static let databaseTableName = "historyVisit"

    /// Whether the title or address contains `query`, as the history search matches it.
    public func matches(_ query: String) -> Bool {
        url.absoluteString.localizedCaseInsensitiveContains(query) || title?.localizedCaseInsensitiveContains(query) == true
    }
}

extension ArchiveItem {
    /// Whether the title or address contains `query`, as the archive search matches it.
    public func matches(_ query: String) -> Bool {
        url.absoluteString.localizedCaseInsensitiveContains(query) || title?.localizedCaseInsensitiveContains(query) == true
    }
}

/// What archiving a tab did.
public enum ArchiveOutcome: Sendable {
    /// The tab went to the archive. `item` is its entry, which a tab without an address doesn't get.
    case archived(ArchiveItem?)
    /// It was archived already (a close racing the stale-tab sweep, say), so nothing changed.
    case alreadyArchived

    /// The new archive entry, if any.
    public var item: ArchiveItem? {
        if case .archived(let item) = self { item } else { nil }
    }
}

extension BoazStore {
    // MARK: History

    /// Records a visit. Repeated loads of the same URL within ten minutes update the existing visit. Queued like
    /// `saveInBackground`, so navigating never waits on the database.
    public func recordVisit(profileID: String, url: URL, title: String?, at date: Date = .now) {
        writeInBackground { db in
            if var last = try HistoryVisit.order(Column("visitedAt").desc).fetchOne(db),
               last.url == url, date.timeIntervalSince(last.visitedAt) < 600 {
                if let title, !title.isEmpty { last.title = title }
                last.visitedAt = date
                try last.update(db)
            } else {
                try HistoryVisit(id: UUID().uuidString, profileID: profileID, url: url, title: title, visitedAt: date)
                    .insert(db)
            }
        }
    }

    /// Drops the visit just recorded for `hop`, an address the server redirected away from, so one load leaves one
    /// entry. The redirect's target may already be recorded after it, so the last two visits are checked, and only
    /// a visit from the last half minute goes. Queued in turn with `recordVisit`.
    public func forgetRedirectedVisit(to hop: URL, at date: Date = .now) {
        writeInBackground { db in
            let recent = try HistoryVisit.order(Column("visitedAt").desc).limit(2).fetchAll(db)
            guard let visit = recent.first(where: { $0.url == hop }), date.timeIntervalSince(visit.visitedAt) < 30
            else { return }
            try visit.delete(db)
        }
    }

    /// Most recent visits, newest first, optionally filtered by title or address. Searching scans the whole
    /// history, so it runs on the database's queue, never the caller's.
    public func history(matching query: String = "", limit: Int = 300) async throws -> [HistoryVisit] {
        let pattern = Self.containsPattern(query)
        return try await writer.read { db in
            var request = HistoryVisit.order(Column("visitedAt").desc).limit(limit)
            if !query.isEmpty {
                request = request.filter(Column("url").like(pattern, escape: "\\")
                                         || Column("title").like(pattern, escape: "\\"))
            }
            return try request.fetchAll(db)
        }
    }

    /// One entry per address, most recently visited first, for search suggestions. Runs on the database's queue.
    public func historySuggestions(matching query: String, limit: Int = 5) async throws -> [HistoryVisit] {
        guard !query.isEmpty else { return [] }
        let pattern = Self.containsPattern(query)
        return try await writer.read { db in
            try HistoryVisit.fetchAll(db, sql: """
                SELECT id, profileID, url, title, MAX(visitedAt) AS visitedAt FROM historyVisit
                WHERE url LIKE ? ESCAPE '\\' OR title LIKE ? ESCAPE '\\'
                GROUP BY url ORDER BY visitedAt DESC LIMIT ?
                """, arguments: [pattern, pattern, limit])
        }
    }

    /// A LIKE pattern for text containing `query`, with `%` and `_` in it matched as themselves.
    private static func containsPattern(_ query: String) -> String {
        let escaped = query.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return "%\(escaped)%"
    }

    public func clearHistory() throws {
        _ = try writer.write { db in try HistoryVisit.deleteAll(db) }
    }

    // MARK: Archive

    /// Archived tabs whose title or address contains `query`, newest first. Covers the whole archive, not only the
    /// newest entries `archivedItems` lists, so it runs on the database's queue.
    public func archivedItems(matching query: String, limit: Int = 500) async throws -> [ArchiveItem] {
        let pattern = Self.containsPattern(query)
        return try await writer.read { db in
            try ArchiveItem.filter(Column("deletedAt") == nil)
                .filter(Column("url").like(pattern, escape: "\\") || Column("title").like(pattern, escape: "\\"))
                .order(Column("archivedAt").desc).limit(limit).fetchAll(db)
        }
    }

    public func archivedItems(limit: Int = 500) throws -> [ArchiveItem] {
        try writer.read { db in
            try ArchiveItem.filter(Column("deletedAt") == nil)
                .order(Column("archivedAt").desc).limit(limit).fetchAll(db)
        }
    }

    /// Moves a tab into the archive: tombstones the tab and records an archive item, atomically.
    @discardableResult
    public func archive(_ tab: SidebarItem, reason: String, at date: Date = .now) throws -> ArchiveOutcome {
        try writer.write { db in try Self.archive(tab, reason: reason, at: date, in: db) }
    }

    /// Archives several tabs, and saves `others` (such as the folders they leave empty), in one transaction, so
    /// the sidebar observation sees one change however many tabs go.
    @discardableResult
    public func archive(_ tabs: [SidebarItem], reason: String, saving others: [SidebarItem] = [],
                        at date: Date = .now) throws -> [ArchiveOutcome] {
        try writer.write { db in
            for record in others { try record.save(db) }
            return try tabs.map { try Self.archive($0, reason: reason, at: date, in: db) }
        }
    }

    /// Archives Today tabs that haven't been active for `interval`. Pinned and favorite tabs are never archived.
    /// Only `deviceID`'s tabs (and those that recorded no device) go: another device sweeps its own.
    @discardableResult
    /// Runs on the database's queue: a backlog of thousands of tabs takes ~150 ms.
    public func archiveStaleTabs(olderThan interval: TimeInterval, onDevice deviceID: String,
                                 now: Date = .now) async throws -> Int {
        let cutoff = now.addingTimeInterval(-interval)
        return try await writer.write { db in
            let todayContainers = try SidebarItem
                .filter(Column("kind") == SidebarItem.Kind.container.rawValue)
                .filter(Column("containerKind") == SidebarItem.ContainerKind.unpinned.rawValue)
                .filter(Column("deletedAt") == nil)
                .fetchAll(db).map(\.id)
            // Tabs in Today's folders (Tidy Tabs) are Today tabs too.
            let todayFolders = try SidebarItem
                .filter(todayContainers.contains(Column("parentID")))
                .filter(Column("kind") == SidebarItem.Kind.folder.rawValue)
                .filter(Column("deletedAt") == nil)
                .fetchAll(db).map(\.id)
            let stale = try SidebarItem
                .filter((todayContainers + todayFolders).contains(Column("parentID")))
                .filter(Column("kind") == SidebarItem.Kind.tab.rawValue)
                .filter(Column("deletedAt") == nil)
                .filter(Column("deviceID") == nil || Column("deviceID") == deviceID)
                .filter(SQL(sql: "COALESCE(lastActiveAt, createdAt) < ?", arguments: [cutoff]))
                .fetchAll(db)
            for tab in stale { try Self.archive(tab, reason: "autoArchived", at: now, in: db) }
            return stale.count
        }
    }

    public func removeFromArchive(_ id: String, at date: Date = .now) throws {
        try writer.write { db in
            guard var item = try ArchiveItem.fetchOne(db, key: id) else { return }
            item.deletedAt = date
            item.modifiedAt = date
            try item.update(db)
        }
    }

    public func clearArchive(at date: Date = .now) throws {
        try writer.write { db in
            try ArchiveItem.filter(Column("deletedAt") == nil)
                .updateAll(db, Column("deletedAt").set(to: date), Column("modifiedAt").set(to: date))
        }
    }

    static func archive(_ tab: SidebarItem, reason: String, at date: Date, in db: Database) throws -> ArchiveOutcome {
        // One archive entry is enough.
        guard try SidebarItem.fetchOne(db, key: tab.id)?.deletedAt == nil else { return .alreadyArchived }
        var tab = tab
        tab.deletedAt = date
        tab.modifiedAt = date
        try tab.save(db)
        guard let url = tab.url else { return .archived(nil) }
        let item = ArchiveItem(id: UUID().uuidString, profileID: tab.profileID, spaceID: tab.spaceID,
                               title: tab.title, url: url, archivedAt: date, reason: reason, modifiedAt: date)
        try item.insert(db)
        return .archived(item)
    }
}
