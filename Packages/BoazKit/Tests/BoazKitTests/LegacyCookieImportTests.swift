import Foundation
import Testing
@testable import BoazKit

@Suite("LegacyCookieImport")
struct LegacyCookieImportTests {
    typealias Plan = LegacyCookieImport
    let session = Plan.Key(host: "example.com", name: "session", path: "/")
    let theme = Plan.Key(host: ".example.com", name: "theme", path: "/")
    let other = Plan.Key(host: "other.test", name: "id", path: "/")

    @Test func firstLaunchImportsOnlyWhatTheProfileDoesNotHave() {
        let (action, state) = Plan.plan(.init(), source: [session, theme, other], destination: [theme])
        #expect(action == .importCookies([0, 2]))
        #expect(state.phase == .pending && state.attempts == 1 && state.imported == [session, other])
    }

    @Test func aSourceThatWinsKeepsItsCookies() {
        let (action, _) = Plan.plan(.init(), source: [session, theme], excluded: [session], destination: [])
        #expect(action == .importCookies([1]))
    }

    @Test func nothingToImportIsDone() {
        #expect(Plan.plan(.init(), source: [], destination: nil).state.phase == .done)
        #expect(Plan.plan(.init(), source: [session], excluded: [session], destination: []).state.phase == .done)
        #expect(Plan.plan(.init(), source: [session], destination: [session]).state.phase == .done)
    }

    @Test func importOnDiskNextLaunchIsDone() {
        let pending = Plan.State(phase: .pending, attempts: 1, imported: [session])
        let (action, state) = Plan.plan(pending, source: [session, theme], destination: [session])
        #expect(action == .none)
        #expect(state.phase == .done)
    }

    /// A denied Keychain prompt writes nothing, so the next launch imports again.
    @Test func importMissingFromDiskImportsAgain() {
        let pending = Plan.State(phase: .pending, attempts: 1, imported: [session])
        let (action, state) = Plan.plan(pending, source: [session, theme], destination: [])
        #expect(action == .importCookies([0, 1]))
        #expect(state.phase == .pending && state.attempts == 2)
    }

    /// A cookie the user already had doesn't prove the import reached the disk: only an imported one does.
    @Test func onlyImportedCookiesProveTheImport() {
        let pending = Plan.State(phase: .pending, attempts: 1, imported: [session])
        let (action, state) = Plan.plan(pending, source: [session, theme], destination: [theme])
        #expect(action == .importCookies([0]))
        #expect(state.phase == .pending)
    }

    @Test func unreadableCookieFileWaits() {
        let pending = Plan.State(phase: .pending, attempts: 3, imported: [session])
        let (action, state) = Plan.plan(pending, source: [session], destination: nil)
        #expect(action == .none)
        #expect(state.phase == .pending && state.attempts == 4 && state.imported == [session])
    }

    @Test func givesUpAfterTheLimit() {
        let (action, state) = Plan.plan(.init(phase: .pending, attempts: Plan.attemptLimit, imported: [session]),
                                        source: [session], destination: [])
        #expect(action == .none)
        #expect(state.phase == .stopped)
        #expect(Plan.plan(.init(phase: .pending, attempts: Plan.attemptLimit - 1), source: [session],
                          destination: nil).state.phase == .stopped)
        #expect(Plan.plan(state, source: [session], destination: []).action == .none)
    }

    @Test func oldMarkerGetsOneCheck() {
        let closed = Plan.State(stored: nil, closedByOldMarker: true)
        #expect(closed.phase == .pending)
        #expect(Plan.plan(closed, source: [session], destination: [session]).state.phase == .done)
        #expect(Plan.plan(closed, source: [session], destination: []).action == .importCookies([0]))
        #expect(Plan.State(stored: nil, closedByOldMarker: false).phase == .new)
    }

    @Test func stateRoundTrips() {
        let state = Plan.State(phase: .pending, attempts: 2, imported: [session, theme])
        #expect(Plan.State(stored: state.stored, closedByOldMarker: false) == state)
        #expect(Plan.State(stored: Data("junk".utf8), closedByOldMarker: false) == Plan.State())
    }
}
