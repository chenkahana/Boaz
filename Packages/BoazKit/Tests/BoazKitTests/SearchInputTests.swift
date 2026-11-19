import Foundation
import Testing
@testable import BoazKit

@Suite("SearchInput")
struct SearchInputTests {
    @Test func fullURLPassesThrough() {
        let url = SearchInput.url(for: "https://example.com/path?q=1")
        #expect(url?.absoluteString == "https://example.com/path?q=1")
    }

    @Test func httpURLPassesThrough() {
        #expect(SearchInput.url(for: "http://example.com")?.absoluteString == "http://example.com")
    }

    @Test func bareDomainGetsHTTPS() {
        let url = SearchInput.url(for: "example.com")
        #expect(url?.absoluteString == "https://example.com")
    }

    @Test func bareDomainWithPathGetsHTTPS() {
        let url = SearchInput.url(for: "example.com/docs/page")
        #expect(url?.absoluteString == "https://example.com/docs/page")
    }

    @Test func trailingDotSearches() {
        let url = SearchInput.url(for: "example.")
        #expect(url?.absoluteString == "https://duckduckgo.com/?q=example.")
    }

    @Test func plainWordsSearch() {
        let url = SearchInput.url(for: "arc browser")
        #expect(url?.absoluteString == "https://duckduckgo.com/?q=arc%20browser")
    }

    @Test func queryIsPercentEncoded() {
        let url = SearchInput.url(for: "a&b=c")
        // `a&b=c` has no dot… it has none, so it searches, and the & and = may not split the query.
        #expect(url != nil)
        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)
        #expect(components?.queryItems?.first(where: { $0.name == "q" })?.value == "a&b=c")
    }

    @Test func emptyInputIsNil() {
        #expect(SearchInput.url(for: "") == nil)
        #expect(SearchInput.url(for: "   ") == nil)
    }

    @Test func aboutBlankOpensAsTyped() {
        #expect(SearchInput.url(for: "about:blank")?.absoluteString == "about:blank")
    }

    @Test func disallowedSchemeSearches() {
        // `tel:` is not in the default scheme set, so it becomes a search rather than a navigation.
        let url = SearchInput.url(for: "tel:+972525961515")
        #expect(url?.absoluteString.hasPrefix("https://duckduckgo.com/?q=") == true)
    }

    @Test func customSchemesAreAllowed() {
        let url = SearchInput.url(for: "chrome://extensions", schemes: ["http", "https", "chrome"])
        #expect(url?.absoluteString == "chrome://extensions")
    }

    @Test func searchTemplateIsUsed() {
        let url = SearchInput.url(for: "hello", searchTemplate: "https://kagi.com/search?q=%@")
        #expect(url?.absoluteString == "https://kagi.com/search?q=hello")
    }

    @Test func everyEngineTemplateResolves() {
        for engine in SearchEngine.allCases {
            let url = SearchInput.url(for: "boaz browser", searchTemplate: engine.template)
            #expect(url != nil)
            #expect(url?.absoluteString.contains("boaz%20browser") == true)
        }
    }
}
