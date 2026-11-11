import BoazKit
import Foundation

/// Parses and dispatches `boaz://` deep links from `.onOpenURL`, App Intents and the widgets'
/// `Link` destinations, and the web links iOS hands Boaz as the default browser.
///
/// Supported links:
/// - `http(s)://…` opens (or switches to) that address in a new tab.
/// - `boaz://open?url=<encoded http(s) URL>` does the same.
/// - `boaz://search?q=<encoded text>` runs a search and opens the results in a new tab.
/// - `boaz://search` focuses the search overlay without a query.
enum DeepLink {
    enum Intent: Equatable {
        case open(URL)
        case search(String)
        case focusSearch
    }

    static func parse(_ url: URL) -> Intent? {
        if ["http", "https"].contains(url.scheme?.lowercased()), url.host() != nil { return .open(url) }
        guard url.scheme == "boaz", let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        func value(_ name: String) -> String? { components.queryItems?.first { $0.name == name }?.value }
        switch components.host {
        case "open":
            // Any app or page can send this link, so only web addresses: never javascript:, file: or app schemes.
            guard let raw = value("url"), let target = URL(string: raw),
                  ["http", "https"].contains(target.scheme?.lowercased()), target.host() != nil else { return nil }
            return .open(target)
        case "search":
            if let query = value("q"), !query.isEmpty { return .search(query) }
            return .focusSearch
        default:
            return nil
        }
    }

    static func url(forOpening target: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "boaz"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "url", value: target.absoluteString)]
        return components.url
    }

    static func url(forSearching query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "boaz"
        components.host = "search"
        if !query.isEmpty { components.queryItems = [URLQueryItem(name: "q", value: query)] }
        return components.url
    }

    /// Applies `url` to `model`. A new tab needs its profile, which only exists once the library's first snapshot
    /// has landed: that can take several seconds after a cold launch, longer on a device still joining its iCloud
    /// library. A link that arrives first is queued and replayed then.
    @MainActor
    static func handle(_ url: URL, model: AppModel) {
        guard let intent = parse(url) else { return }
        // Search waits too: submitting it opens a new tab.
        guard model.hasLibrary else {
            pending = intent
            Task { await waitForLibraryThenReplay(model: model) }
            return
        }
        perform(intent, model: model)
    }

    @MainActor private static var pending: Intent?

    @MainActor
    private static func waitForLibraryThenReplay(model: AppModel) async {
        var attempts = 0
        while !model.hasLibrary, attempts < 600 {
            try? await Task.sleep(for: .milliseconds(50))
            attempts += 1
        }
        guard let intent = pending else { return }
        pending = nil
        perform(intent, model: model)
    }

    @MainActor
    private static func perform(_ intent: Intent, model: AppModel) {
        switch intent {
        case .open(let target):
            model.openNewTab(target)
        case .search(let query):
            model.beginSearch(.newTab)
            model.searchText = query
            model.submitSearch()
        case .focusSearch:
            model.beginSearch(.newTab)
        }
    }
}
