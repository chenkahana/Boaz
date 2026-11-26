import Foundation
import Testing
@testable import BoazKit

@Suite("Page residency")
struct PageResidencyTests {
    private typealias Page = PageResidencyPolicy.Page

    @Test func phoneLimitScalesWithMemoryWithinBounds() {
        #expect(PageResidencyPolicy.phoneLimit(physicalMemory: 2_000_000_000) == 6)
        #expect(PageResidencyPolicy.phoneLimit(physicalMemory: 3_900_000_000) == 8)
        #expect(PageResidencyPolicy.phoneLimit(physicalMemory: 5_900_000_000) == 12)
        #expect(PageResidencyPolicy.phoneLimit(physicalMemory: 7_990_000_000) == 16)
        #expect(PageResidencyPolicy.phoneLimit(physicalMemory: 12_000_000_000) == 16)
    }

    @Test func underTheLimitNothingCloses() {
        let pages = ["a", "b", "c"].map { Page(id: $0) }
        #expect(PageResidencyPolicy.pagesToClose(pages, target: 3, keeping: [], closesInput: false).isEmpty)
    }

    @Test func reselectingALivePageNeverClosesIt() {
        // The page just shown again is the most recent and in view: over the limit, an older one goes.
        let pages = ["a", "b", "c", "d"].map { Page(id: $0) }
        let close = PageResidencyPolicy.pagesToClose(pages, target: 3, keeping: ["d"], closesInput: false)
        #expect(close == ["a"])
    }

    @Test func pagesInViewAndBusyPagesStay() {
        let pages = [Page(id: "a"), Page(id: "b", isBusy: true), Page(id: "c"), Page(id: "d")]
        let close = PageResidencyPolicy.pagesToClose(pages, target: 1, keeping: ["a"], closesInput: true)
        #expect(close == ["c", "d"])
    }

    @Test func thePlainLimitKeepsTypedIntoPages() {
        let pages = [Page(id: "form", hasInput: true), Page(id: "b"), Page(id: "c")]
        let close = PageResidencyPolicy.pagesToClose(pages, target: 1, keeping: ["c"], closesInput: false)
        #expect(close == ["b"])
    }

    @Test func normalPagesCloseBeforePrivateOnesAndTypedIntoLast() {
        let pages = [Page(id: "private", isPrivate: true), Page(id: "form", hasInput: true), Page(id: "plain"),
                     Page(id: "privateForm", isPrivate: true, hasInput: true), Page(id: "shown")]
        let close = PageResidencyPolicy.pagesToClose(pages, target: 1, keeping: ["shown"], closesInput: true)
        #expect(close == ["plain", "form", "private", "privateForm"])
    }

    @Test func aMemoryWarningTrimsToTheTargetOnly() {
        let pages = (0..<8).map { Page(id: "\($0)") }
        let close = PageResidencyPolicy.pagesToClose(pages, target: 4, keeping: ["7"], closesInput: true)
        #expect(close == ["0", "1", "2", "3"])
    }

    @Test func aCrashRestoresOnceThenStops() {
        var budget = CrashRestoreBudget()
        let start = Date(timeIntervalSince1970: 1_000)
        let firstEnding = budget.contentEnded("tab", at: start)
        let restored = budget.takeRestore("tab")
        let restoredTwice = budget.takeRestore("tab")
        #expect(firstEnding && restored && !restoredTwice)
        // Ended again within a minute: no automatic restore, however often the page finished loading meanwhile.
        let soonAfter = budget.contentEnded("tab", at: start + 30)
        let restoredSoonAfter = budget.takeRestore("tab")
        #expect(!soonAfter && !restoredSoonAfter)
        // Still too soon: the minute runs from the last ending.
        let stillTooSoon = budget.contentEnded("tab", at: start + 80)
        #expect(!stillTooSoon)
        // A minute after the last ending, the next one restores again.
        let minuteLater = budget.contentEnded("tab", at: start + 141)
        #expect(minuteLater && budget.owesRestore("tab"))
    }

    @Test func crashRestoresAreKeptPerTab() {
        var budget = CrashRestoreBudget()
        let now = Date(timeIntervalSince1970: 1_000)
        budget.contentEnded("a", at: now)
        budget.contentEnded("b", at: now + 1)
        let restoredB = budget.takeRestore("b")
        let restoredA = budget.takeRestore("a")
        #expect(restoredA && restoredB)
        // A closed tab's record goes with it.
        budget.forget("a")
        let afterForgetting = budget.contentEnded("a", at: now + 2)
        #expect(afterForgetting)
    }
}
