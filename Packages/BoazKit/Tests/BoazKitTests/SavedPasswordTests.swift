import Foundation
import Testing
@testable import BoazKit

@Suite("SavedPassword")
struct SavedPasswordTests {
    private let saved = [
        SavedPassword(host: "www.example.com", username: "zoe"),
        SavedPassword(host: "example.com", username: "chen"),
        SavedPassword(host: "accounts.example.com", username: "Chen@Example.com"),
        SavedPassword(host: "other.org", username: ""),
        SavedPassword(host: "intranet.local", port: 8080, isSecure: false, username: "admin"),
    ]

    @Test func matchingEmptyListsAllBySiteThenUsername() {
        #expect(saved.matching("  ").map(\.id) == [
            "https://accounts.example.com|Chen@Example.com",
            "https://example.com|chen",
            "http://intranet.local:8080|admin",
            "https://other.org|",
            "https://www.example.com|zoe",
        ])
    }

    @Test func matchingSearchesSiteAndUsernameIgnoringCase() {
        #expect(saved.matching("CHEN").map(\.host) == ["accounts.example.com", "example.com"])
        #expect(saved.matching("other").map(\.host) == ["other.org"])
        #expect(saved.matching("8080").map(\.host) == ["intranet.local"])
        #expect(saved.matching("nothing").isEmpty)
    }

    @Test func serviceURLHasSchemeHostAndPort() {
        #expect(SavedPassword(host: "Example.com", username: "a").serviceURL == "https://example.com")
        #expect(SavedPassword(host: "intranet.local", port: 8080, isSecure: false, username: "a").serviceURL
            == "http://intranet.local:8080")
    }

    @Test func pageURLFromServiceIdentifiers() {
        #expect(SavedPassword.pageURL(serviceIdentifier: "example.com", isDomain: true)?.absoluteString
            == "https://example.com")
        #expect(SavedPassword.pageURL(serviceIdentifier: "https://accounts.example.com/login?x=1", isDomain: false)?
            .host() == "accounts.example.com")
        #expect(SavedPassword.pageURL(serviceIdentifier: "example.com", isDomain: false)?.absoluteString
            == "https://example.com")
        #expect(SavedPassword.pageURL(serviceIdentifier: "http://intranet.local:8080/", isDomain: false)?.port == 8080)
        #expect(SavedPassword.pageURL(serviceIdentifier: "", isDomain: true) == nil)
    }

    @Test func offeredAtSeveralURLsKeepsOrderWithoutRepeats() throws {
        let urls = [
            try #require(SavedPassword.pageURL(serviceIdentifier: "https://example.com/login", isDomain: false)),
            try #require(SavedPassword.pageURL(serviceIdentifier: "accounts.example.com", isDomain: true)),
        ]
        let offered = saved.offered(at: urls)
        #expect(offered.count == 3)
        #expect(Set(offered.prefix(2).map(\.host)) == ["example.com", "www.example.com"])
        #expect(offered.last?.host == "accounts.example.com")
        #expect(saved.offered(at: []).isEmpty)
    }

    @Test func idFindsTheEntryAsAutoFillRecordIdentifier() {
        let entry = SavedPassword(host: "intranet.local", port: 8080, isSecure: false, username: "admin")
        #expect(saved.first { $0.id == entry.id } == entry)
    }
}
