import Foundation
import GRDB
import Testing
@testable import BoazKit

@Suite("Ordering")
struct OrderingTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func evenPositionsOnlyRenumbersWhenCrowded() {
        #expect(BoazStore.evenPositions([0, 1, 2], force: false) == nil)
        #expect(BoazStore.evenPositions([0, 1, 2], force: true) == [0, 1, 2])
        #expect(BoazStore.evenPositions([0, 0.5, 0.5 + 5e-10], force: false) == [0, 1, 2])
        #expect(BoazStore.evenPositions([], force: true) == [])
    }

    @Test func rebalancePositionsRenumbersCrowdedSiblings() throws {
        let store = try BoazStore.inMemory()
        func child(_ id: String, _ position: Double) -> SidebarItem {
            SidebarItem(id: id, spaceID: "s1", profileID: "p1", parentID: "parent", kind: .tab,
                        url: URL(string: "https://example.com/\(id)"), position: position, modifiedAt: t0)
        }
        try store.save([child("a", 0), child("b", 0.5), child("c", 0.5 + 5e-10)])

        #expect(try store.rebalancePositions(inParent: "parent") == true)
        let positions = try store.sidebar().children(of: "parent").sorted { $0.position < $1.position }
        #expect(positions.map(\.id) == ["a", "b", "c"])
        #expect(positions.map(\.position) == [0, 1, 2])

        // Balanced now: nothing left to do.
        #expect(try store.rebalancePositions(inParent: "parent") == false)
    }

    @Test func parentLoopsAreCutAtTheSamePlaceOnEveryDevice() throws {
        let store = try BoazStore.inMemory()
        try store.save([Profile(id: "p1", name: "Personal", isDefault: true, modifiedAt: t0)])
        let space = try store.createSpace(title: "Work", icon: nil, palette: .defaultPalette, profileID: "p1", at: t0)
        let pinned = try #require(store.sidebar().container(.pinned, in: space.id))
        // Two folders parented into each other, as a two-device race can produce.
        let a = SidebarItem(id: "aaa", spaceID: space.id, profileID: "p1", parentID: "bbb",
                            kind: .folder, title: "A", position: 0, modifiedAt: t0)
        let b = SidebarItem(id: "bbb", spaceID: space.id, profileID: "p1", parentID: "aaa",
                            kind: .folder, title: "B", position: 1, modifiedAt: t0)
        try store.save([a, b])

        try store.writer.write { db in
            try BoazStore.breakParentLoops(from: ["aaa", "bbb"], at: t0, in: db)
        }

        let items = try store.sidebar().items
        let after = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.parentID) })
        // The loop is cut at the smaller id, which moves to the space's pinned container.
        #expect(after["aaa"] == pinned.id)
        #expect(after["bbb"] == "aaa")
    }
}

@Suite("Sidebar model")
struct SidebarModelTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_000_100)

    private func makeSidebar() throws -> (store: BoazStore, space: Space) {
        let store = try BoazStore.inMemory()
        try store.save([Profile(id: "p1", name: "Personal", isDefault: true, modifiedAt: t0)])
        let space = try store.createSpace(title: "Work", icon: nil, palette: .defaultPalette, profileID: "p1", at: t0)
        return (store, space)
    }

    @Test func todayTabsAreTheDevicesOwn() throws {
        let (store, space) = try makeSidebar()
        let today = try #require(store.sidebar().container(.unpinned, in: space.id))
        func todayTab(_ id: String, device: String?) -> SidebarItem {
            SidebarItem(id: id, spaceID: space.id, profileID: "p1", parentID: today.id, kind: .tab,
                        url: URL(string: "https://example.com/\(id)"), position: 0, modifiedAt: t0, deviceID: device)
        }
        try store.save([todayTab("mine", device: "d1"), todayTab("theirs", device: "d2"),
                        todayTab("before-devices", device: nil)])

        let sidebar = try store.sidebar()
        #expect(Set(sidebar.todayTabs(in: space.id, onDevice: "d1").map(\.id)) == ["mine", "before-devices"])
        #expect(Set(sidebar.todayTabs(in: space.id, onDevice: "d2").map(\.id)) == ["theirs", "before-devices"])
    }

    @Test func mobileTabsSortMostRecentlyUsedFirst() throws {
        let store = try BoazStore.inMemory()
        let old = SidebarItem.mobileTab(url: URL(string: "https://a.example.com")!, title: "A",
                                        profileID: "p1", deviceID: "d1", at: t0)
        let new = SidebarItem.mobileTab(url: URL(string: "https://b.example.com")!, title: "B",
                                        profileID: "p1", deviceID: "d1", at: t1)
        let otherDevice = SidebarItem.mobileTab(url: URL(string: "https://c.example.com")!, title: "C",
                                                profileID: "p1", deviceID: "d2", at: t1)
        try store.save([old, new, otherDevice])
        #expect(try store.sidebar().mobileTabs(onDevice: "d1").map(\.title) == ["B", "A"])
    }

    @Test func upsertReplacesAndKeepsOrder() throws {
        let (store, space) = try makeSidebar()
        let today = try #require(store.sidebar().container(.unpinned, in: space.id))
        func tab(_ id: String, _ position: Double) -> SidebarItem {
            SidebarItem(id: id, spaceID: space.id, profileID: "p1", parentID: today.id, kind: .tab,
                        url: URL(string: "https://example.com/\(id)"), position: position, modifiedAt: t0)
        }
        try store.save([tab("a", 0), tab("b", 1)])

        var sidebar = try store.sidebar()
        var renamed = try #require(sidebar.items.first { $0.id == "a" })
        renamed.title = "Renamed"
        sidebar.upsert(renamed)
        #expect(sidebar.children(of: today.id).map(\.id) == ["a", "b"])
        #expect(sidebar.children(of: today.id).first?.title == "Renamed")

        // A tombstoned item leaves the model.
        var gone = try #require(sidebar.items.first { $0.id == "b" })
        gone.deletedAt = t1
        sidebar.upsert(gone)
        #expect(sidebar.children(of: today.id).map(\.id) == ["a"])
    }

    @Test func nextPositionAppendsAfterExistingChildren() throws {
        let (store, space) = try makeSidebar()
        let today = try #require(store.sidebar().container(.unpinned, in: space.id))
        let sidebar = try store.sidebar()
        #expect(sidebar.nextPosition(in: today.id) == 0)
        try store.save([SidebarItem(id: "a", spaceID: space.id, profileID: "p1", parentID: today.id,
                                    kind: .tab, url: URL(string: "https://example.com"),
                                    position: 4, modifiedAt: t0)])
        #expect(try store.sidebar().nextPosition(in: today.id) == 5)
    }
}
