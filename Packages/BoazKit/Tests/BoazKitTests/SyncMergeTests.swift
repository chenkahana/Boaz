import Foundation
import Testing
@testable import BoazKit

@Suite("SyncMerge")
struct SyncMergeTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_000_100)
    private let t2 = Date(timeIntervalSince1970: 1_700_000_200)
    private let t3 = Date(timeIntervalSince1970: 1_700_000_300)

    private func item(title: String?, unread: Bool = false, parentID: String? = "c1",
                      position: Double = 0, modifiedAt: Date, deletedAt: Date? = nil) -> SidebarItem {
        SidebarItem(id: "tab-1", spaceID: "s1", profileID: "p1", parentID: parentID, kind: .tab,
                    title: title, url: URL(string: "https://example.com"), isUnread: unread,
                    position: position, createdAt: t0, modifiedAt: modifiedAt, deletedAt: deletedAt)
    }

    @Test func newerSideWinsWithoutBase() {
        let local = item(title: "Local", modifiedAt: t2)
        let server = item(title: "Server", modifiedAt: t1)
        #expect(SyncMerge.resolve(local: local, server: server).title == "Local")
        #expect(SyncMerge.resolve(local: server, server: local).title == "Local")
    }

    @Test func equalTimestampsFavorServer() {
        let local = item(title: "Local", modifiedAt: t1)
        let server = item(title: "Server", modifiedAt: t1)
        #expect(SyncMerge.resolve(local: local, server: server).title == "Server")
    }

    @Test func fieldMergeKeepsEachSidesOwnChanges() {
        let base = item(title: "Base", modifiedAt: t0)
        var local = base; local.title = "Local"; local.modifiedAt = t2
        var server = base; server.isUnread = true; server.modifiedAt = t1
        let merged = SyncMerge.resolve(local: local, server: server, base: base)
        #expect(merged.title == "Local")
        #expect(merged.isUnread == true)
        #expect(merged.modifiedAt == t2)
    }

    @Test func conflictingFieldGoesToNewerSide() {
        let base = item(title: "Base", modifiedAt: t0)
        var local = base; local.title = "Local"; local.modifiedAt = t1
        var server = base; server.title = "Server"; server.modifiedAt = t2
        #expect(SyncMerge.resolve(local: local, server: server, base: base).title == "Server")
    }

    @Test func aMoveNeverSplits() {
        // parentID and position merge as one unit: a server-side move keeps its own position,
        // even though the local side is newer elsewhere.
        let base = item(title: "Same", parentID: "c1", position: 0, modifiedAt: t0)
        var local = base; local.title = "Edited"; local.modifiedAt = t2
        var server = base; server.parentID = "c2"; server.position = 7; server.modifiedAt = t1
        let merged = SyncMerge.resolve(local: local, server: server, base: base)
        #expect(merged.title == "Edited")
        #expect(merged.parentID == "c2")
        #expect(merged.position == 7)
    }

    @Test func newerLocalMoveWins() {
        let base = item(title: "Same", parentID: "c1", position: 0, modifiedAt: t0)
        var local = base; local.parentID = "c3"; local.position = 2; local.modifiedAt = t2
        var server = base; server.parentID = "c2"; server.position = 7; server.modifiedAt = t1
        let merged = SyncMerge.resolve(local: local, server: server, base: base)
        #expect(merged.parentID == "c3")
        #expect(merged.position == 2)
    }

    @Test func deleteBeatsOlderEdit() {
        let local = item(title: "Gone", modifiedAt: t2, deletedAt: t2)
        let server = item(title: "Edited", unread: true, modifiedAt: t1)
        let merged = SyncMerge.resolve(local: local, server: server)
        #expect(merged.deletedAt == t2)
    }

    @Test func editNewerThanDeleteResurrects() {
        let local = item(title: "Edited", modifiedAt: t3)
        let server = item(title: "Gone", modifiedAt: t2, deletedAt: t2)
        let merged = SyncMerge.resolve(local: local, server: server)
        #expect(merged.deletedAt == nil)
        #expect(merged.title == "Edited")
    }

    @Test func deleteBeatsOlderDeleteKeepingNewestTombstone() {
        let local = item(title: "Gone", modifiedAt: t1, deletedAt: t1)
        let server = item(title: "Gone", modifiedAt: t2, deletedAt: t2)
        #expect(SyncMerge.resolve(local: local, server: server).deletedAt == t2)
    }
}
