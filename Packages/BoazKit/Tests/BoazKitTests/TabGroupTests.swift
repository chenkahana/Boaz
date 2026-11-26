import CloudKit
import Foundation
import Testing
@testable import BoazKit

@Suite("Tab groups")
struct TabGroupTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_000_000 + 2 * 86_400)

    private struct Library {
        let store: BoazStore
        let space: Space
        let today: SidebarItem
        let pinned: SidebarItem
    }

    private func makeLibrary() throws -> Library {
        let store = try BoazStore.inMemory()
        try store.save([Profile(id: "p1", name: "Personal", isDefault: true, modifiedAt: t0)])
        let space = try store.createSpace(title: "Work", icon: nil, palette: .defaultPalette, profileID: "p1", at: t0)
        let sidebar = try store.sidebar()
        return Library(store: store, space: space, today: try #require(sidebar.container(.unpinned, in: space.id)),
                       pinned: try #require(sidebar.container(.pinned, in: space.id)))
    }

    private func tab(_ id: String, in parent: String, _ library: Library, position: Double = 0, device: String?,
                     lastActive: Date? = nil) -> SidebarItem {
        SidebarItem(id: id, spaceID: library.space.id, profileID: "p1", parentID: parent, kind: .tab,
                    url: URL(string: "https://example.com/\(id)"), position: position, lastActiveAt: lastActive,
                    modifiedAt: t0, deviceID: device)
    }

    private func group(_ id: String, _ library: Library, position: Double = 0, device: String?) -> SidebarItem {
        SidebarItem(id: id, spaceID: library.space.id, profileID: "p1", parentID: library.today.id, kind: .folder,
                    title: id, position: position, modifiedAt: t0, deviceID: device)
    }

    /// Mac B's Today and its Clear never reach Mac A's groups, which B doesn't show; folders from before devices
    /// were recorded show on both.
    @Test func todayGroupsAndClearAreTheDevicesOwn() throws {
        let library = try makeLibrary()
        try library.store.save([
            group("a-group", library, position: 0, device: "mac-a"),
            tab("a-grouped", in: "a-group", library, device: "mac-a"),
            group("b-group", library, position: 1, device: "mac-b"),
            tab("b-grouped", in: "b-group", library, device: "mac-b"),
            group("old-tidy", library, position: 2, device: nil),
            tab("tidied", in: "old-tidy", library, device: "mac-b"),
            tab("b-today", in: library.today.id, library, position: 3, device: "mac-b"),
            tab("a-today", in: library.today.id, library, position: 4, device: "mac-a"),
        ])
        let sidebar = try library.store.sidebar()

        #expect(sidebar.today(in: library.space.id, onDevice: "mac-b").map(\.id) == ["b-group", "old-tidy", "b-today"])
        #expect(sidebar.groups(in: library.space.id, onDevice: "mac-a").map(\.id) == ["a-group", "old-tidy"])

        let clear = sidebar.clearable(in: library.space.id, onDevice: "mac-b")
        #expect(Set(clear.groups.map(\.id)) == ["b-group", "old-tidy"])
        #expect(Set(clear.tabs.map(\.id)) == ["b-today", "b-grouped", "tidied"])

        // Archived as MacModel.clearToday does: Mac A's group and tabs are untouched.
        let tombstones = clear.groups.map { var group = $0; group.deletedAt = t1; group.modifiedAt = t1; return group }
        try library.store.archive(clear.tabs, reason: "cleared", saving: tombstones, at: t1)
        let after = try library.store.sidebar()
        #expect(Set(after.items.filter { $0.kind != .container }.map(\.id)) == ["a-group", "a-grouped", "a-today"])
    }

    @Test func newGroupTakesTheTabsSlotAndThisDevice() throws {
        let library = try makeLibrary()
        let target = tab("b", in: library.today.id, library, position: 1, device: "mac-a")
        try library.store.save([tab("a", in: library.today.id, library, position: 0, device: "mac-a"), target,
                                tab("c", in: library.today.id, library, position: 2, device: "mac-a")])
        var sidebar = try library.store.sidebar()
        let records = try #require(sidebar.newGroup(around: target, id: "g", deviceID: "mac-a", at: t1))
        records.forEach { sidebar.upsert($0) }

        #expect(sidebar.children(of: library.today.id).map(\.id) == ["a", "g", "c"])
        #expect(sidebar.children(of: "g").map(\.id) == ["b"])
        let made = try #require(sidebar.items.first { $0.id == "g" })
        #expect(made.title == Sidebar.newGroupTitle && made.isExpanded && made.deviceID == "mac-a")

        let empty = try #require(sidebar.newEmptyGroup(in: library.space.id, id: "e", deviceID: "mac-a", at: t1))
        sidebar.upsert(empty)
        #expect(sidebar.children(of: library.today.id).first?.id == "e")
    }

    /// Ungroup keeps the tabs' order and puts them where the group was, between its neighbours.
    @Test func ungroupKeepsOrderInTheGroupsPlace() throws {
        let library = try makeLibrary()
        let g = group("g", library, position: 1, device: "mac-a")
        try library.store.save([
            tab("before", in: library.today.id, library, position: 0, device: "mac-a"), g,
            tab("after", in: library.today.id, library, position: 2, device: "mac-a"),
            tab("one", in: "g", library, position: 0, device: "mac-a"),
            tab("two", in: "g", library, position: 1, device: "mac-a"),
            tab("three", in: "g", library, position: 2, device: "mac-a"),
        ])
        let records = try library.store.sidebar().ungrouped(g, at: t1)
        #expect(records.last?.id == "g" && records.last?.deletedAt == t1)
        try library.store.save(records)

        let after = try library.store.sidebar()
        #expect(after.children(of: library.today.id).map(\.id) == ["before", "one", "two", "three", "after"])
        #expect(!after.items.contains { $0.id == "g" })
        #expect(after.items.filter { $0.kind == .tab }.count == 5)
    }

    /// Archive Group sends every tab to the Archive and the group with them; restoring brings the group back with
    /// its tabs inside and takes them out of the Archive.
    @Test func archivedGroupRestoresWhole() throws {
        let library = try makeLibrary()
        let g = group("g", library, position: 0, device: "mac-a")
        let tabs = [tab("one", in: "g", library, position: 0, device: "mac-a"),
                    tab("two", in: "g", library, position: 1, device: "mac-a")]
        try library.store.save([g] + tabs)

        var tombstone = g
        tombstone.deletedAt = t1
        let outcomes = try library.store.archive(tabs, reason: "closed", saving: [tombstone], at: t1)
        #expect(try library.store.sidebar().items.allSatisfy { $0.kind == .container })
        #expect(try library.store.archivedItems().count == 2)

        // MacModel.reopenClosedTab: the batch comes back undeleted, and its archive entries go.
        let restored = ([g] + tabs).map { var item = $0; item.deletedAt = nil; item.modifiedAt = t1.addingTimeInterval(1); return item }
        try library.store.save(restored)
        for case .archived(let entry?) in outcomes { try library.store.removeFromArchive(entry.id) }

        let after = try library.store.sidebar()
        #expect(after.children(of: library.today.id).map(\.id) == ["g"])
        #expect(after.children(of: "g").map(\.id) == ["one", "two"])
        #expect(try library.store.archivedItems().isEmpty)
    }

    /// The sweep removes a group it empties; a group still holding a fresh tab, one already empty, and another
    /// device's stay.
    @Test func sweepRemovesOnlyTheGroupsItEmpties() async throws {
        let library = try makeLibrary()
        try library.store.save([
            group("emptied", library, position: 0, device: "mac-a"),
            tab("stale", in: "emptied", library, device: "mac-a", lastActive: t0),
            group("kept", library, position: 1, device: "mac-a"),
            tab("stale-2", in: "kept", library, device: "mac-a", lastActive: t0),
            tab("fresh", in: "kept", library, position: 1, device: "mac-a", lastActive: t1),
            group("by-hand", library, position: 2, device: "mac-a"),
            group("other-mac", library, position: 3, device: "mac-b"),
            tab("other-stale", in: "other-mac", library, device: "mac-b", lastActive: t0),
        ])

        let swept = try await library.store.archiveStaleTabs(olderThan: 86_400, onDevice: "mac-a", now: t1)
        #expect(swept == 2)
        let folders = Set(try library.store.sidebar().items.filter { $0.kind == .folder }.map(\.id))
        #expect(folders == ["kept", "by-hand", "other-mac"])
    }

    /// No new field crosses CloudKit: a group's record has only keys a Today tab or a pinned folder already has.
    @Test func groupRecordAddsNoField() throws {
        let library = try makeLibrary()
        func keys(_ item: SidebarItem) -> Set<String> {
            let record = SyncMapping.record(for: item)
            return Set(record.allKeys()).union(record.encryptedValues.allKeys())
        }
        let todayTab = tab("t", in: library.today.id, library, device: "mac-a", lastActive: t0)
        let folder = SidebarItem(id: "f", spaceID: library.space.id, profileID: "p1", parentID: library.pinned.id,
                                 kind: .folder, title: "Folder", position: 0, modifiedAt: t0, icon: "📁")
        let made = try #require(try library.store.sidebar().newGroup(around: todayTab, id: "g", deviceID: "mac-a"))[0]
        #expect(keys(made).isSubset(of: keys(todayTab).union(keys(folder))))
    }
}
