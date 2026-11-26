import CloudKit
import Foundation
import GRDB
import Testing
@testable import BoazKit

@Suite("SpaceRoute")
struct SpaceRouteTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func route(_ host: String, _ path: String? = nil, space: String = "work", position: Double = 0) throws -> SpaceRoute {
        try SpaceRoute(host: host, pathPrefix: path, spaceID: space, profileID: "p1", position: position, modifiedAt: t0)
    }

    private func storeWithSpaces() throws -> BoazStore {
        let store = try BoazStore.inMemory()
        try store.save([
            Profile(id: "p1", name: "Personal", isDefault: true, modifiedAt: t0),
            Profile(id: "p2", name: "Work", isDefault: false, modifiedAt: t0),
            Space(id: "home", title: "Personal", profileID: "p1", position: 0, modifiedAt: t0),
            Space(id: "work", title: "Work", profileID: "p2", position: 0, modifiedAt: t0),
        ])
        return store
    }

    @Test func hostsAndPathsAreNormalized() throws {
        let r = try route("GitHub.COM", "/acme/")
        #expect(r.host == "github.com" && r.pathPrefix == "/acme")
        #expect(try route("github.com", "/").pathPrefix == nil)
        #expect(throws: SiteEngineRule.ValidationError.self) { try route("not a host") }
        #expect(throws: SiteEngineRule.ValidationError.self) { try route("10.0.0.1") }
        #expect(throws: SiteEngineRule.ValidationError.self) { try route("github.com", "/../x") }
        // One site, one id, whatever the space.
        #expect(try route("github.com", space: "a").id == route("GITHUB.com", space: "b").id)
        #expect(try route("github.com").id != route("github.com", "/acme").id)
    }

    @Test func matchesHostSubdomainsAndPath() throws {
        let host = try route("github.com"), path = try route("github.com", "/acme")
        #expect(host.matches(URL(string: "https://github.com/x")!))
        #expect(host.matches(URL(string: "https://www.github.com/")!))
        #expect(!host.matches(URL(string: "https://notgithub.com/")!))
        #expect(!host.matches(URL(string: "https://github.com.evil.com/")!))
        #expect(!host.matches(URL(string: "mailto:a@github.com")!))
        #expect(path.matches(URL(string: "https://github.com/acme")!))
        #expect(path.matches(URL(string: "https://github.com/acme/repo")!))
        #expect(!path.matches(URL(string: "https://github.com/acmeco")!))
    }

    @Test func firstMatchInListOrderWins() throws {
        let broad = try route("github.com", space: "home", position: 0)
        let narrow = try route("github.com", "/acme", space: "work", position: 1)
        let url = URL(string: "https://github.com/acme/x")!
        let live: Set = ["home", "work"]
        #expect(SpaceRoute.route(for: url, in: [narrow, broad], liveSpaceIDs: live)?.spaceID == "home")
        var reordered = narrow; reordered.position = -1
        #expect(SpaceRoute.route(for: url, in: [reordered, broad], liveSpaceIDs: live)?.spaceID == "work")
    }

    @Test func missingSpaceAndDeletedRulesAreSkipped() throws {
        let first = try route("github.com", space: "gone", position: 0)
        var deleted = try route("github.com", "/acme", space: "home", position: 1); deleted.deletedAt = t0
        let fallback = try route("github.com", space: "work", position: 2)
        let url = URL(string: "https://github.com/acme")!
        let chosen = SpaceRoute.route(for: url, in: [first, deleted, fallback], liveSpaceIDs: ["home", "work"])
        #expect(chosen?.spaceID == "work")
        #expect(SpaceRoute.route(for: URL(string: "https://example.com")!, in: [first, fallback], liveSpaceIDs: ["work"]) == nil)
    }

    @Test func overlap() throws {
        #expect(try route("github.com", "/acme").isCovered(by: route("github.com")))
        #expect(try route("gist.github.com").isCovered(by: route("github.com")))
        #expect(try route("github.com", "/acme/x").isCovered(by: route("github.com", "/acme")))
        #expect(try !route("github.com").isCovered(by: route("github.com", "/acme")))
        #expect(try !route("github.com").isCovered(by: route("github.com")))
        #expect(try !route("github.com", "/acmeco").isCovered(by: route("github.com", "/acme")))
    }

    @Test func newRuleLandsAtEndOrAboveBroaderOverlap() throws {
        let store = try storeWithSpaces()
        try store.addSpaceRoute(host: "example.com", spaceID: "home", profileID: "p1", at: t0)
        try store.addSpaceRoute(host: "github.com", spaceID: "home", profileID: "p1", at: t0)
        try store.addSpaceRoute(host: "apple.com", spaceID: "home", profileID: "p1", at: t0)
        try store.addSpaceRoute(host: "github.com", pathPrefix: "/acme", spaceID: "work", profileID: "p2", at: t0)
        let order = try store.spaceRoutes().map { $0.host + ($0.pathPrefix ?? "") }
        #expect(order == ["example.com", "github.com/acme", "github.com", "apple.com"])
        #expect(try store.spaceRoutes().first { $0.pathPrefix == "/acme" }?.profileID == "p2")
    }

    @Test func addingAnExistingSiteRepointsItInPlace() throws {
        let store = try storeWithSpaces()
        try store.addSpaceRoute(host: "github.com", spaceID: "home", profileID: "p1", at: t0)
        try store.addSpaceRoute(host: "apple.com", spaceID: "home", profileID: "p1", at: t0)
        try store.addSpaceRoute(host: "GitHub.com", spaceID: "work", profileID: "p2", at: t0)
        let routes = try store.spaceRoutes()
        #expect(routes.map(\.host) == ["github.com", "apple.com"])
        #expect(routes[0].spaceID == "work" && routes[0].profileID == "p2")
    }

    @Test func moveAndRemove() throws {
        let store = try storeWithSpaces()
        let a = try store.addSpaceRoute(host: "a.com", spaceID: "home", profileID: "p1", at: t0)
        let b = try store.addSpaceRoute(host: "b.com", spaceID: "home", profileID: "p1", at: t0)
        let c = try store.addSpaceRoute(host: "c.com", spaceID: "home", profileID: "p1", at: t0)
        try store.moveSpaceRoute(id: c.id, before: a.id)
        #expect(try store.spaceRoutes().map(\.host) == ["c.com", "a.com", "b.com"])
        try store.moveSpaceRoute(id: c.id, before: nil)
        #expect(try store.spaceRoutes().map(\.host) == ["a.com", "b.com", "c.com"])
        for _ in 0..<80 { try store.moveSpaceRoute(id: c.id, before: b.id); try store.moveSpaceRoute(id: b.id, before: c.id) }
        #expect(try store.spaceRoutes().map(\.host) == ["a.com", "b.com", "c.com"])
        try store.removeSpaceRoute(id: b.id)
        #expect(try store.spaceRoutes().map(\.host) == ["a.com", "c.com"])
        // Removing is a synced tombstone; adding the site again brings the same record back.
        #expect(try store.pendingSyncChanges().contains(SyncPendingChange(.spaceRoute, b.id)))
        let again = try store.addSpaceRoute(host: "b.com", spaceID: "work", profileID: "p2", at: t0)
        #expect(again.id == b.id && again.deletedAt == nil)
    }

    @Test func importsUserDefaultsRulesLongestHostFirst() throws {
        let store = try storeWithSpaces()
        let old: [(host: String, spaceID: String)] = [
            ("github.com", "home"), ("docs.github.com", "work"), ("example.com", "missing"), ("apple.com", "work"),
        ]
        #expect(try store.importSpaceHostRules(old, at: t0) == 3)
        let routes = try store.spaceRoutes()
        #expect(routes.map(\.host) == ["docs.github.com", "github.com", "apple.com"])
        #expect(routes.map(\.profileID) == ["p2", "p1", "p2"])
        // Same winner as the old longest-host rule.
        let url = URL(string: "https://docs.github.com/x")!
        #expect(SpaceRoute.route(for: url, in: routes, liveSpaceIDs: ["home", "work"])?.spaceID == "work")
        // Running again (or another Mac's copy arriving first) adds nothing.
        #expect(try store.importSpaceHostRules(old, at: t0) == 0)
        try store.removeSpaceRoute(id: routes[2].id)
        #expect(try store.importSpaceHostRules(old, at: t0) == 0)
        // An invalid host throws, and nothing is written.
        #expect(throws: (any Error).self) { try store.importSpaceHostRules([("ok.com", "home"), ("bad host", "home")]) }
        #expect(try store.spaceRoutes().count == 2)
    }

    @Test func cloudRecordRoundTripAndRefusal() throws {
        let original = try route("github.com", "/acme", position: 3)
        let record = SyncMapping.record(for: original)
        #expect(record.recordType == "SpaceRoute")
        #expect(record["host"] == nil, "host must be encrypted")
        #expect(try SpaceRoute(cloudRecord: record) == original)

        // A record named for one site but carrying another is refused.
        let forged = SyncMapping.record(for: try route("github.com"))
        forged.encryptedValues["host"] = "evil.com"
        #expect(throws: (any Error).self) { try SpaceRoute(cloudRecord: forged) }
        let badHost = SyncMapping.record(for: try route("github.com"))
        badHost.encryptedValues["host"] = "javascript:alert(1)"
        #expect(throws: (any Error).self) { try SpaceRoute(cloudRecord: badHost) }
    }

    /// An iPhone (no spaces shown) stores synced rules silently, skips record types it doesn't know, and never
    /// queues a rule for upload or deletion.
    @Test func storeWithoutSpacesKeepsRulesAndSkipsUnknownTypes() async throws {
        let store = try BoazStore.inMemory()
        let rule = SyncMapping.record(for: try route("github.com", space: "work"))
        let unknown = CKRecord(recordType: "TabGroup",
                               recordID: CKRecord.ID(recordName: "TabGroup:1", zoneID: SyncMapping.zoneID))
        let requeue = try await store.applyServerChanges(modified: [rule, unknown])
        #expect(requeue.isEmpty)
        #expect(try store.spaceRoutes().map(\.host) == ["github.com"])
        #expect(try store.pendingSyncChanges().isEmpty)
        _ = try await store.purgeTombstones(now: t0.addingTimeInterval(365 * 24 * 3600))
        #expect(try store.spaceRoutes().count == 1)
    }

    @Test func tabOverridesStayLocalAndArePrunedWithTheirTab() throws {
        let store = try storeWithSpaces()
        let tab = SidebarItem(id: "t1", spaceID: "home", profileID: "p1", parentID: nil, kind: .tab,
                              position: 0, createdAt: t0, modifiedAt: t0)
        try store.save([tab])
        let queued = try store.pendingSyncChanges().count
        try store.setTabSpaceOverride(tabID: "t1", profileID: "p1")
        try store.setTabSpaceOverride(tabID: "gone", profileID: "p1")
        #expect(try store.pendingSyncChanges().count == queued)
        try store.pruneTabSpaceOverrides()
        #expect(try store.tabSpaceOverrides() == ["t1"])
    }
}
