import Foundation
import Testing
@testable import BoazKit

@Suite("RecordState")
struct RecordStateTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private let t1 = Date(timeIntervalSince1970: 1_700_000_100)
    private let t2 = Date(timeIntervalSince1970: 1_700_000_200)
    private let t3 = Date(timeIntervalSince1970: 1_700_000_300)

    private func item(title: String?, unread: Bool = false, modifiedAt: Date, deletedAt: Date? = nil) -> SidebarItem {
        SidebarItem(id: "tab-1", spaceID: "s1", profileID: "p1", parentID: "c1", kind: .tab,
                    title: title, url: URL(string: "https://example.com"), isUnread: unread,
                    position: 0, createdAt: t0, modifiedAt: modifiedAt, deletedAt: deletedAt)
    }

    private func stamped(_ item: SidebarItem, over previous: RecordState? = nil,
                         known: Set<String>? = nil) throws -> RecordState {
        try RecordState.stamped(RecordState.fields(of: item), over: previous,
                                groups: SidebarItem.mergeGroups, known: known)
    }

    @Test func firstWriteStampsEveryUnitWithModifiedAt() throws {
        let state = try stamped(item(title: "A", modifiedAt: t1))
        let expected = t1.timeIntervalSinceReferenceDate
        #expect(!state.stamps.isEmpty)
        #expect(state.stamps.values.allSatisfy { $0 == expected })
    }

    @Test func onlyChangedUnitsGetANewStamp() throws {
        let base = try stamped(item(title: "A", modifiedAt: t1))
        var edited = item(title: "B", modifiedAt: t1); edited.modifiedAt = t2
        let next = try stamped(edited, over: base)
        #expect(next.stamps["title"] == t2.timeIntervalSinceReferenceDate)
        #expect(next.stamps["parentID"] == t1.timeIntervalSinceReferenceDate)
        #expect(next.stamps["isUnread"] == t1.timeIntervalSinceReferenceDate)
    }

    @Test func stampBeatsClockSkew() throws {
        // A local edit made after seeing a newer-stamped change wins even if this device's clock is behind.
        let base = try stamped(item(title: "A", modifiedAt: t3))
        var edit = item(title: "B", modifiedAt: t3); edit.modifiedAt = t1
        let next = try stamped(edit, over: base)
        #expect(next.stamps["title"] == t3.timeIntervalSinceReferenceDate + 0.001)
    }

    @Test func mergeIsCommutativeAndIdempotent() throws {
        let base = try stamped(item(title: "A", modifiedAt: t1))
        let titleEdit = try stamped(item(title: "B", modifiedAt: t2), over: base)
        let unreadEdit = try stamped(item(title: "A", unread: true, modifiedAt: t3), over: base)
        let groups = SidebarItem.mergeGroups
        let ab = RecordState.merge(titleEdit, unreadEdit, groups: groups)
        let ba = RecordState.merge(unreadEdit, titleEdit, groups: groups)
        #expect(ab == ba)
        #expect(RecordState.merge(titleEdit, titleEdit, groups: groups) == titleEdit)
        #expect(try ab.value(SidebarItem.self).title == "B")
        #expect(try ab.value(SidebarItem.self).isUnread == true)
    }

    @Test func mergeIsAssociative() throws {
        let base = try stamped(item(title: "A", modifiedAt: t1))
        let a = try stamped(item(title: "B", modifiedAt: t2), over: base)
        var unread = item(title: "A", unread: true, modifiedAt: t1); unread.modifiedAt = t2
        let b = try stamped(unread, over: base)
        var moved = item(title: "A", modifiedAt: t1); moved.parentID = "c2"; moved.position = 9; moved.modifiedAt = t3
        let c = try stamped(moved, over: base)
        let groups = SidebarItem.mergeGroups
        #expect(RecordState.merge(RecordState.merge(a, b, groups: groups), c, groups: groups)
                == RecordState.merge(a, RecordState.merge(b, c, groups: groups), groups: groups))
    }

    @Test func mergeKeepsBothSidesChanges() throws {
        let base = try stamped(item(title: "A", modifiedAt: t1))
        let a = try stamped(item(title: "B", modifiedAt: t2), over: base)
        var unread = item(title: "A", unread: true, modifiedAt: t1); unread.modifiedAt = t3
        let b = try stamped(unread, over: base)
        let merged = RecordState.merge(a, b, groups: SidebarItem.mergeGroups)
        let value = try merged.value(SidebarItem.self)
        #expect(value.title == "B")
        #expect(value.isUnread == true)
        #expect(value.modifiedAt.timeIntervalSinceReferenceDate == t3.timeIntervalSinceReferenceDate)
    }

    @Test func editNewerThanDeleteResurrectsTheRecord() throws {
        let base = try stamped(item(title: "A", modifiedAt: t1))
        let deleted = try stamped(item(title: "A", modifiedAt: t2, deletedAt: t2), over: base)
        var revived = item(title: "B", modifiedAt: t3, deletedAt: t2)
        revived.modifiedAt = t3
        let edited = try stamped(revived, over: deleted)
        let normalized = edited.normalized()
        #expect(normalized.fields["deletedAt"] == nil)
        let value = try normalized.value(SidebarItem.self)
        #expect(value.deletedAt == nil)
        #expect(value.title == "B")
    }

    @Test func deleteBeatsOlderEdits() throws {
        let base = try stamped(item(title: "A", modifiedAt: t1))
        let edited = try stamped(item(title: "B", modifiedAt: t2), over: base)
        let deleted = try stamped(item(title: "A", modifiedAt: t3, deletedAt: t3), over: base)
        let merged = RecordState.merge(edited, deleted, groups: SidebarItem.mergeGroups)
        #expect(merged.fields["deletedAt"] != nil)
        #expect(try merged.value(SidebarItem.self).deletedAt == t3)
    }

    @Test func fieldsThisBuildCannotWriteSurviveAWrite() throws {
        let base = try stamped(item(title: "A", modifiedAt: t1))
        var withFuture = base
        withFuture.fields["futureField"] = .string("kept")
        let edit = item(title: "B", modifiedAt: t2)
        let next = try stamped(edit, over: withFuture, known: RecordState.keys(of: edit))
        #expect(next.fields["futureField"] == .string("kept"))
    }
}
