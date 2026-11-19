import Foundation
import Testing
@testable import BoazKit

@Suite("SiteEngineRule")
struct SiteEngineRuleTests {
    private func rule(host: String, path: String? = nil, engine: StoredBrowserEngine = .webkit,
                      reason: SiteEngineRule.Reason = .user, profileID: String = "p1") throws -> SiteEngineRule {
        try SiteEngineRule(profileID: profileID, host: host, pathPrefix: path, engine: engine, reason: reason)
    }

    @Test func hostsAreNormalizedToLowercase() throws {
        #expect(try rule(host: "Example.COM").host == "example.com")
    }

    @Test func invalidHostsAreRejected() {
        #expect(throws: SiteEngineRule.ValidationError.self) { try rule(host: "") }
        #expect(throws: SiteEngineRule.ValidationError.self) { try rule(host: "127.0.0.1") }
        #expect(throws: SiteEngineRule.ValidationError.self) { try rule(host: "8.8.8.8") }
        #expect(throws: SiteEngineRule.ValidationError.self) { try rule(host: "-bad.com") }
        #expect(throws: SiteEngineRule.ValidationError.self) { try rule(host: "bad-.com") }
        #expect(throws: SiteEngineRule.ValidationError.self) { try rule(host: "a..com") }
        #expect(throws: SiteEngineRule.ValidationError.self) { try rule(host: "exa mple.com") }
        #expect(throws: SiteEngineRule.ValidationError.self) { try rule(host: String(repeating: "a", count: 254) + ".com") }
        // All-numeric hosts are IP-literal-like and rejected; mixed labels are fine.
        #expect(throws: SiteEngineRule.ValidationError.self) { try rule(host: "123.456") }
    }

    @Test func validHostsAreAccepted() throws {
        #expect(try rule(host: "example.com").host == "example.com")
        #expect(try rule(host: "sub.domain.co.il").host == "sub.domain.co.il")
        #expect(try rule(host: "a-b-c.example.com").host == "a-b-c.example.com")
        #expect(try rule(host: "123abc.com").host == "123abc.com")
    }

    @Test func pathsAreValidatedAndNormalized() throws {
        #expect(try rule(host: "example.com", path: "/gp/video/").pathPrefix == "/gp/video")
        #expect(try rule(host: "example.com", path: "/").pathPrefix == nil)
        #expect(throws: SiteEngineRule.ValidationError.self) { try rule(host: "example.com", path: "gp/video") }
        #expect(throws: SiteEngineRule.ValidationError.self) { try rule(host: "example.com", path: "/gp/../etc") }
        #expect(throws: SiteEngineRule.ValidationError.self) { try rule(host: "example.com", path: "/gp/video?x=1") }
        #expect(throws: SiteEngineRule.ValidationError.self) { try rule(host: "example.com", path: "/gp%2Fvideo") }
    }

    @Test func matchingCoversHostSuffixAndPathPrefix() throws {
        let hostRule = try rule(host: "example.com")
        #expect(hostRule.matches(URL(string: "https://example.com/")!))
        #expect(hostRule.matches(URL(string: "https://sub.example.com/page")!))
        #expect(!hostRule.matches(URL(string: "https://notexample.com/")!))
        #expect(!hostRule.matches(URL(string: "https://example.com.evil.com/")!))
        #expect(!hostRule.matches(URL(string: "ftp://example.com/")!))

        let pathRule = try rule(host: "amazon.com", path: "/gp/video")
        #expect(pathRule.matches(URL(string: "https://www.amazon.com/gp/video")!))
        #expect(pathRule.matches(URL(string: "https://www.amazon.com/gp/video/detail")!))
        #expect(!pathRule.matches(URL(string: "https://www.amazon.com/gp/video2")!))
        #expect(!pathRule.matches(URL(string: "https://www.amazon.com/")!))
    }

    @Test func userRulesBeatSeededRulesAndLongerMatchesBeatShorter() throws {
        let seeded = try rule(host: "amazon.com", engine: .webkit, reason: .protectedMedia)
        let user = try rule(host: "amazon.com", engine: .chromium, reason: .user)
        let deeper = try rule(host: "amazon.com", path: "/gp/video", engine: .webkit, reason: .user)
        let url = URL(string: "https://www.amazon.com/gp/video")!

        // A user rule wins over a seeded one at the same specificity…
        #expect(SiteEngineRule.matchingRule(for: url, profileID: "p1", rules: [seeded, user])?.engine == .chromium)
        // …and a more specific path wins over a bare host.
        #expect(SiteEngineRule.matchingRule(for: url, profileID: "p1", rules: [user, deeper])?.pathPrefix == "/gp/video")
        // Rules of another profile never apply.
        #expect(SiteEngineRule.matchingRule(for: url, profileID: "p2", rules: [user]) == nil)
    }

    @Test func protectedMediaSeedsAreIdempotentAndRespectRemovals() throws {
        let store = try BoazStore.inMemory()
        try store.seedProtectedMediaRules(profileID: "p1")
        let seeded = try store.siteEngineRules(profileID: "p1")
        #expect(seeded.count == 10)
        #expect(seeded.allSatisfy { $0.reason == .protectedMedia && $0.engine == .webkit })

        try store.seedProtectedMediaRules(profileID: "p1")
        #expect(try store.siteEngineRules(profileID: "p1").count == 10)

        // The user removes Netflix; re-seeding must not bring it back.
        let netflix = try #require(seeded.first { $0.host == "netflix.com" })
        try store.removeSiteEngineRule(netflix)
        try store.seedProtectedMediaRules(profileID: "p1")
        #expect(try store.siteEngineRules(profileID: "p1").count == 9)
    }

    @Test func tabEngineChoicesRoundTripPerProfile() throws {
        let store = try BoazStore.inMemory()
        #expect(try store.tabEngine(tabID: "tab1", profileID: "p1") == nil)
        try store.setTabEngine(.chromium, tabID: "tab1", profileID: "p1")
        #expect(try store.tabEngine(tabID: "tab1", profileID: "p1") == .chromium)
        #expect(try store.tabEngine(tabID: "tab1", profileID: "p2") == nil)
        try store.setTabEngine(nil, tabID: "tab1", profileID: "p1")
        #expect(try store.tabEngine(tabID: "tab1", profileID: "p1") == nil)
    }
}
