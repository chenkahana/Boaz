import BoazKit
import Foundation

/// Seeds a fresh store from the JSON fixture named by `BOAZ_UITEST_FIXTURES` (`UITestMode.fixturesURL`), so
/// BoazUITests always sees the same library. Inert unless UI test mode is active; see `Tests/BoazUITests/Fixtures`.
enum UITestFixtures {
    private struct Tab: Decodable {
        var id: String
        var title: String?
        var url: String
        var children: [Tab]?
    }

    private struct SpaceFixture: Decodable {
        var id: String
        var name: String
        var icon: String?
        var pinned: [Tab]?
        var folders: [Tab]?
        var today: [Tab]?
    }

    private struct ArchivedFixture: Decodable {
        var id: String
        var title: String?
        var url: String
        var reason: String?
        var daysAgo: Double?
    }

    private struct HistoryFixture: Decodable {
        var id: String
        var title: String?
        var url: String
        var daysAgo: Double?
    }

    private struct Root: Decodable {
        var spaces: [SpaceFixture]?
        var favorites: [Tab]?
        var archived: [ArchivedFixture]?
        var history: [HistoryFixture]?
    }

    private static let profileID = "fixture-default"

    /// Replaces the fresh store's content with the fixture at `UITestMode.fixturesURL`. No-op outside UI test
    /// mode, or when no fixture was given (an empty library).
    static func seedIfNeeded(_ store: BoazStore, deviceID: String) async throws {
        guard UITestMode.isActive, let url = UITestMode.fixturesURL else { return }
        let root = try JSONDecoder().decode(Root.self, from: Data(contentsOf: url))
        let now = Date.now

        try store.save([Profile(id: profileID, name: "Fixture", isDefault: true, modifiedAt: now)])

        var spaces: [Space] = []
        var items: [SidebarItem] = []
        for (index, space) in (root.spaces ?? []).enumerated() {
            spaces.append(Space(id: space.id, title: space.name, icon: space.icon, profileID: profileID,
                                position: Double(index), modifiedAt: now))
            let pinnedID = "\(space.id)-pinned"
            let todayID = "\(space.id)-today"
            items.append(SidebarItem(id: pinnedID, spaceID: space.id, profileID: profileID, parentID: nil,
                                     kind: .container, containerKind: .pinned, position: 0,
                                     createdAt: now, modifiedAt: now))
            items.append(SidebarItem(id: todayID, spaceID: space.id, profileID: profileID, parentID: nil,
                                     kind: .container, containerKind: .unpinned, position: 1,
                                     createdAt: now, modifiedAt: now))
            appendTabs(space.pinned ?? [], spaceID: space.id, parentID: pinnedID, deviceID: nil, now: now, into: &items)
            appendFolders(space.folders ?? [], spaceID: space.id, parentID: pinnedID, now: now, into: &items)
            appendTabs(space.today ?? [], spaceID: space.id, parentID: todayID, deviceID: deviceID, now: now, into: &items)
        }
        if let favorites = root.favorites, !favorites.isEmpty {
            items.append(SidebarItem(id: "fixture-favorites", spaceID: nil, profileID: profileID, parentID: nil,
                                     kind: .container, containerKind: .favorites, position: 0,
                                     createdAt: now, modifiedAt: now))
            appendTabs(favorites, spaceID: nil, parentID: "fixture-favorites", deviceID: nil, now: now, into: &items)
        }
        try store.save(spaces)
        try store.save(items)

        let archivedFixtures: [ArchivedFixture] = root.archived ?? []
        let archived = archivedFixtures.compactMap { entry -> ArchiveItem? in
            guard let archiveURL = URL(string: entry.url) else { return nil }
            let archivedAt = now.addingTimeInterval(-(entry.daysAgo ?? 1) * 86400)
            return ArchiveItem(id: entry.id, profileID: profileID, spaceID: nil, title: entry.title,
                               url: archiveURL, archivedAt: archivedAt, reason: entry.reason ?? "closed", modifiedAt: now)
        }
        try store.save(archived)

        // `HistoryVisit` has no public memberwise initializer (history is written only through `recordVisit`),
        // so fixtures go through the same API a real page visit does; `waitForQueuedWrites` makes sure they land
        // before the window reads the store.
        let historyFixtures: [HistoryFixture] = root.history ?? []
        for entry in historyFixtures {
            guard let historyURL = URL(string: entry.url) else { continue }
            let visitedAt = now.addingTimeInterval(-(entry.daysAgo ?? 0) * 86400)
            store.recordVisit(profileID: profileID, url: historyURL, title: entry.title, at: visitedAt)
        }
        if !historyFixtures.isEmpty { await store.waitForQueuedWrites() }
    }

    private static func appendTabs(_ tabs: [Tab], spaceID: String?, parentID: String?, deviceID: String?,
                                   now: Date, into items: inout [SidebarItem]) {
        for (index, tab) in tabs.enumerated() {
            items.append(SidebarItem(id: tab.id, spaceID: spaceID, profileID: profileID, parentID: parentID, kind: .tab,
                                     title: tab.title, url: URL(string: tab.url), position: Double(index),
                                     createdAt: now, modifiedAt: now, deviceID: deviceID))
        }
    }

    private static func appendFolders(_ folders: [Tab], spaceID: String, parentID: String?, now: Date,
                                      into items: inout [SidebarItem]) {
        for (index, folder) in folders.enumerated() {
            items.append(SidebarItem(id: folder.id, spaceID: spaceID, profileID: profileID, parentID: parentID,
                                     kind: .folder, title: folder.title, position: Double(index),
                                     createdAt: now, modifiedAt: now))
            appendTabs(folder.children ?? [], spaceID: spaceID, parentID: folder.id, deviceID: nil, now: now, into: &items)
        }
    }
}
