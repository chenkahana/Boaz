import Foundation
import Testing
@testable import BoazKit

@Suite("SiteStyleBook")
struct SiteStyleBookTests {
    @Test func hostsAreKeyedExactlyWithWwwFolded() {
        #expect(SiteStyleBook.key(forHost: "WWW.NYTimes.com") == "nytimes.com")
        #expect(SiteStyleBook.key(forHost: "nytimes.com.") == "nytimes.com")
        #expect(SiteStyleBook.key(forHost: "news.nytimes.com") == "news.nytimes.com")
        // `www.` alone before a single label isn't a subdomain to fold.
        #expect(SiteStyleBook.key(forHost: "www.com") == "www.com")
        #expect(SiteStyleBook.key(forHost: "127.0.0.1") == "127.0.0.1")
        #expect(SiteStyleBook.key(forHost: "") == nil)
        #expect(SiteStyleBook.key(forHost: "a b.com") == nil)
    }

    @Test func savedStyleIsFoundForEitherSpellingButNotSubdomains() throws {
        var book = SiteStyleBook()
        try book.save("body{}", profileID: "p1", host: "www.example.com")
        #expect(book.css(profileID: "p1", host: "example.com") == "body{}")
        #expect(book.css(profileID: "p1", host: "WWW.example.com") == "body{}")
        #expect(book.css(profileID: "p1", host: "app.example.com") == nil)
        #expect(book.styles.map(\.host) == ["example.com"])
    }

    @Test func stylesArePerProfile() throws {
        var book = SiteStyleBook()
        try book.save("a{}", profileID: "p1", host: "example.com")
        try book.save("b{}", profileID: "p2", host: "example.com")
        #expect(book.css(profileID: "p1", host: "example.com") == "a{}")
        #expect(book.css(profileID: "p2", host: "example.com") == "b{}")
        #expect(book.cssByHost(profileID: "p2") == ["example.com": "b{}"])
        book.delete(profileID: "p1", host: "example.com")
        #expect(book.css(profileID: "p1", host: "example.com") == nil)
        #expect(book.css(profileID: "p2", host: "example.com") == "b{}")
    }

    @Test func savingReplacesAndUpdatesTheDate() throws {
        var book = SiteStyleBook()
        try book.save("a{}", profileID: "p1", host: "example.com", now: Date(timeIntervalSince1970: 1))
        try book.save("b{}", profileID: "p1", host: "example.com", now: Date(timeIntervalSince1970: 2))
        #expect(book.styles.count == 1)
        #expect(book.styles.first?.css == "b{}")
        #expect(book.styles.first?.updatedAt == Date(timeIntervalSince1970: 2))
    }

    @Test func savingEmptyTextDeletes() throws {
        var book = SiteStyleBook()
        try book.save("a{}", profileID: "p1", host: "example.com")
        try book.save("  \n\t", profileID: "p1", host: "example.com")
        #expect(book.styles.isEmpty)
        // Saving empty text for a host with no style is a no-op, not a blank row.
        try book.save("", profileID: "p1", host: "other.com")
        #expect(book.styles.isEmpty)
    }

    @Test func cssIsCappedAt32KB() throws {
        var book = SiteStyleBook()
        let limit = String(repeating: "a", count: SiteStyleBook.maxBytes)
        try book.save(limit, profileID: "p1", host: "example.com")
        #expect(throws: SiteStyleBook.SaveError.tooLong) {
            try book.save(limit + "a", profileID: "p1", host: "example.com")
        }
        // Counted in UTF-8 bytes, not characters.
        let wide = String(repeating: "é", count: SiteStyleBook.maxBytes / 2 + 1)
        #expect(!SiteStyleBook.fits(wide))
        #expect(book.css(profileID: "p1", host: "example.com") == limit)
    }

    @Test func atMost500SitesButReplacingStillWorks() throws {
        var book = SiteStyleBook()
        for index in 0..<SiteStyleBook.maxSites { try book.save("a{}", profileID: "p1", host: "site\(index).com") }
        #expect(book.isFull(adding: "new.com", profileID: "p1"))
        #expect(!book.isFull(adding: "site3.com", profileID: "p1"))
        #expect(throws: SiteStyleBook.SaveError.tooMany) { try book.save("a{}", profileID: "p1", host: "new.com") }
        try book.save("b{}", profileID: "p1", host: "site3.com")
        #expect(book.css(profileID: "p1", host: "site3.com") == "b{}")
    }

    @Test func invalidHostIsRejected() {
        var book = SiteStyleBook()
        #expect(throws: SiteStyleBook.SaveError.invalidHost) { try book.save("a{}", profileID: "p1", host: " ") }
    }

    @Test func deletedProfilesLoseTheirStyles() throws {
        var book = SiteStyleBook()
        try book.save("a{}", profileID: "p1", host: "example.com")
        try book.save("b{}", profileID: "gone", host: "example.com")
        book.keepProfiles(["p1"])
        #expect(book.styles.map(\.profileID) == ["p1"])
    }

    @Test func roundTripsThroughJSON() throws {
        var book = SiteStyleBook()
        try book.save("body::before{content:\"x\"}", profileID: "p1", host: "example.com",
                      now: Date(timeIntervalSince1970: 100))
        let decoded = try JSONDecoder().decode(SiteStyleBook.self, from: JSONEncoder().encode(book))
        #expect(decoded == book)
    }
}

@Suite("SiteStylePreset")
struct SiteStylePresetTests {
    private func tap(_ preset: SiteStylePreset, on text: String) -> String { text + preset.addition(to: text) }

    @Test func presetsAppendAndNeverReplace() {
        let typed = "h1 { color: red; }"
        let dark = tap(.dark, on: typed)
        #expect(dark.hasPrefix(typed + "\n\n/* Dark */\n"))
        let both = tap(.biggerText, on: dark)
        #expect(both.hasPrefix(dark))
        #expect(SiteStylePreset.dark.isApplied(in: both))
        #expect(SiteStylePreset.biggerText.isApplied(in: both))
        #expect(!SiteStylePreset.hideCookieBanners.isApplied(in: both))
    }

    @Test func presetOnEmptyTextIsJustTheBlock() {
        #expect(tap(.biggerText, on: "") == "/* Bigger Text */\nhtml { font-size: 112.5% !important; }\n")
    }

    @Test func presetAfterTrailingNewlinesKeepsOneBlankLine() {
        #expect(tap(.dark, on: "a{}\n").hasPrefix("a{}\n\n/* Dark */"))
        #expect(tap(.dark, on: "a{}\n\n").hasPrefix("a{}\n\n/* Dark */"))
    }

    @Test func editedPresetCountsAsNotApplied() {
        let text = tap(.biggerText, on: "").replacingOccurrences(of: "112.5%", with: "125%")
        #expect(!SiteStylePreset.biggerText.isApplied(in: text))
    }

    @Test func everyPresetFitsTheCap() {
        let all = SiteStylePreset.allCases.reduce("") { tap($1, on: $0) }
        #expect(SiteStyleBook.fits(all))
    }
}
