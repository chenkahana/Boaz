import Foundation
import Testing
@testable import BoazKit

@Suite("Library")
struct LibraryTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_000_100)

    private func makeLibrary() throws -> (store: BoazStore, space: Space) {
        let store = try BoazStore.inMemory()
        try store.save([Profile(id: "p1", name: "Personal", isDefault: true, modifiedAt: t0)])
        let space = try store.createSpace(title: "Work", icon: nil, palette: .defaultPalette, profileID: "p1", at: t0)
        return (store, space)
    }

    private func tab(_ id: String, parentID: String?, spaceID: String?, position: Double = 0,
                     lastActiveAt: Date? = nil, deviceID: String? = nil,
                     url: String? = "https://example.com") -> SidebarItem {
        SidebarItem(id: id, spaceID: spaceID, profileID: "p1", parentID: parentID, kind: .tab,
                    title: id, url: url.flatMap(URL.init(string:)), position: position,
                    createdAt: lastActiveAt ?? t0, lastActiveAt: lastActiveAt, modifiedAt: t0,
                    deviceID: deviceID)
    }

    @Test func createSpaceAddsPinnedAndTodayContainers() throws {
        let (store, space) = try makeLibrary()
        let sidebar = try store.sidebar()
        #expect(sidebar.container(.pinned, in: space.id) != nil)
        #expect(sidebar.container(.unpinned, in: space.id) != nil)
    }

    @Test func archiveMovesTabToArchiveAtomically() throws {
        let (store, space) = try makeLibrary()
        let pinned = try #require(store.sidebar().container(.pinned, in: space.id))
        let tab = tab("tab1", parentID: pinned.id, spaceID: space.id)
        try store.save([tab])

        guard case .archived(let entry) = try store.archive(tab, reason: "closed") else {
            Issue.record("expected .archived")
            return
        }
        #expect(entry?.url.absoluteString == "https://example.com")
        #expect(entry?.reason == "closed")
        #expect(try store.sidebar().items.filter { $0.kind == .tab }.isEmpty)
        #expect(try store.archivedItems().count == 1)
    }

    @Test func archivingTwiceIsANoOp() throws {
        let (store, space) = try makeLibrary()
        let pinned = try #require(store.sidebar().container(.pinned, in: space.id))
        let tab = tab("tab1", parentID: pinned.id, spaceID: space.id)
        try store.save([tab])
        _ = try store.archive(tab, reason: "closed")
        let again = try store.archive(tab, reason: "closed")
        guard case .alreadyArchived = again else { Issue.record("second archive was \(again)"); return }
        #expect(try store.archivedItems().count == 1)
    }

    @Test func tabWithoutAddressArchivesWithoutEntry() throws {
        let (store, space) = try makeLibrary()
        let pinned = try #require(store.sidebar().container(.pinned, in: space.id))
        let tab = tab("tab1", parentID: pinned.id, spaceID: space.id, url: nil)
        try store.save([tab])
        guard case .archived(let entry) = try store.archive(tab, reason: "closed") else {
            Issue.record("expected .archived")
            return
        }
        #expect(entry == nil)
        #expect(try store.archivedItems().isEmpty)
    }

    @Test func staleSweepArchivesOldTodayTabsOnly() async throws {
        let (store, space) = try makeLibrary()
        let sidebar = try store.sidebar()
        let pinned = try #require(sidebar.container(.pinned, in: space.id))
        let today = try #require(sidebar.container(.unpinned, in: space.id))
        let old = t1.addingTimeInterval(-2 * 86_400)
        try store.save([
            tab("stale-today", parentID: today.id, spaceID: space.id, lastActiveAt: old),
            tab("fresh-today", parentID: today.id, spaceID: space.id, lastActiveAt: t1),
            tab("stale-pinned", parentID: pinned.id, spaceID: space.id, lastActiveAt: old),
            tab("other-device", parentID: today.id, spaceID: space.id, lastActiveAt: old, deviceID: "d2"),
            SidebarItem.mobileTab(url: URL(string: "https://m.example.com")!, title: "M",
                                  profileID: "p1", deviceID: "d1", at: old),
        ])

        let swept = try await store.archiveStaleTabs(olderThan: 86_400, onDevice: "d1", now: t1)
        #expect(swept == 2)
        let remaining = Set(try store.sidebar().items.filter { $0.kind == .tab }.map(\.id))
        #expect(remaining == Set(["fresh-today", "stale-pinned", "other-device"]))
        #expect(try store.archivedItems().count == 2)
    }

    @Test func recordVisitCoalescesWithinTenMinutes() async throws {
        let store = try BoazStore.inMemory()
        let url = URL(string: "https://example.com")!
        store.recordVisit(profileID: "p1", url: url, title: nil, at: t0)
        store.recordVisit(profileID: "p1", url: url, title: "Example", at: t0.addingTimeInterval(300))
        store.recordVisit(profileID: "p1", url: url, title: "Example", at: t0.addingTimeInterval(601))
        await store.waitForQueuedWrites()
        let history = try await store.history()
        #expect(history.count == 2)
        #expect(history.first?.title == "Example")
    }

    @Test func historySearchMatchesLiteralSpecialCharacters() async throws {
        let store = try BoazStore.inMemory()
        store.recordVisit(profileID: "p1", url: URL(string: "https://example.com/sale")!,
                          title: "100% cotton", at: t0)
        store.recordVisit(profileID: "p1", url: URL(string: "https://other.example")!,
                          title: "Something else", at: t0)
        await store.waitForQueuedWrites()
        // "%" must match itself, not act as a LIKE wildcard that would match every row.
        let matches = try await store.history(matching: "100%")
        #expect(matches.count == 1)
        #expect(matches.first?.title == "100% cotton")
    }

    @Test func clearHistoryRemovesVisits() async throws {
        let store = try BoazStore.inMemory()
        store.recordVisit(profileID: "p1", url: URL(string: "https://example.com")!, title: nil, at: t0)
        await store.waitForQueuedWrites()
        try store.clearHistory()
        #expect(try await store.history().isEmpty)
    }

    @Test func deleteSpaceArchivesItsTabs() throws {
        let (store, space) = try makeLibrary()
        let other = try store.createSpace(title: "Home", icon: nil, palette: .defaultPalette, profileID: "p1", at: t0)
        let pinned = try #require(store.sidebar().container(.pinned, in: space.id))
        try store.save([tab("tab1", parentID: pinned.id, spaceID: space.id)])

        let archived = try store.deleteSpace(space.id)
        #expect(archived == 1)
        #expect(try store.archivedItems().count == 1)
        #expect(try store.sidebar().spaces.map(\.id) == [other.id])
    }

    @Test func lastSpaceCannotBeDeleted() throws {
        let (store, space) = try makeLibrary()
        #expect(try store.deleteSpace(space.id) == 0)
        #expect(try store.sidebar().spaces.count == 1)
    }

    @Test func deletingLastSpaceOfProfileTakesProfileAlong() throws {
        let (store, space) = try makeLibrary()
        try store.save([Profile(id: "p2", name: "Work", isDefault: false, modifiedAt: t0)])
        _ = try store.createSpace(title: "Other", icon: nil, palette: .defaultPalette, profileID: "p2", at: t0)

        _ = try store.deleteSpace(space.id)
        let sidebar = try store.sidebar()
        #expect(sidebar.profiles.map(\.id) == ["p2"])
        #expect(sidebar.spaces.count == 1)
    }

    @Test func adoptMobileStackMovesFiledTabsOutOfSpaces() async throws {
        let (store, space) = try makeLibrary()
        let today = try #require(store.sidebar().container(.unpinned, in: space.id))
        try store.save([tab("tab1", parentID: today.id, spaceID: space.id, deviceID: "phone-1")])

        let moved = try await store.adoptMobileStack(deviceID: "phone-1")
        #expect(moved == 1)
        let item = try #require(store.sidebar().items.first { $0.id == "tab1" })
        #expect(item.spaceID == nil)
        #expect(item.parentID == nil)
        #expect(item.isMobileTab)
    }

    @Test func moveSpaceReorders() throws {
        let (store, space) = try makeLibrary()
        let b = try store.createSpace(title: "B", icon: nil, palette: .defaultPalette, profileID: "p1", at: t0)
        let c = try store.createSpace(title: "C", icon: nil, palette: .defaultPalette, profileID: "p1", at: t0)
        try store.moveSpace(c.id, to: 0)
        #expect(try store.sidebar().spaces.map(\.id) == [c.id, space.id, b.id])
    }
}
