import FolioKit
import Foundation

/// Parses and dispatches `folio://` deep links from `.onOpenURL`, App Intents and the widgets'
/// `Link` destinations.
///
/// Supported links:
/// - `folio://open?url=<encoded http(s) URL>` opens (or switches to) that address in a new tab.
/// - `folio://search?q=<encoded text>` runs a search and opens the results in a new tab.
/// - `folio://search` focuses the search overlay without a query.
enum DeepLink {
    enum Intent: Equatable {
        case open(URL)
        case search(String)
        case focusSearch
    }

    static func parse(_ url: URL) -> Intent? {
        guard url.scheme == "folio", let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
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
        components.scheme = "folio"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "url", value: target.absoluteString)]
        return components.url
    }

    static func url(forSearching query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "folio"
        components.host = "search"
        if !query.isEmpty { components.queryItems = [URLQueryItem(name: "q", value: query)] }
        return components.url
    }

    /// Applies `url` to `model`. `AppModel.start()` opens the store asynchronously and its loop
    /// never returns, so a link that arrives first is queued and replayed once `model.store` is set.
    @MainActor
    static func handle(_ url: URL, model: AppModel) {
        guard let intent = parse(url) else { return }
        guard model.store != nil else {
            pending = intent
            Task { await waitForStoreThenReplay(model: model) }
            return
        }
        perform(intent, model: model)
    }

    @MainActor private static var pending: Intent?

    @MainActor
    private static func waitForStoreThenReplay(model: AppModel) async {
        var attempts = 0
        while model.store == nil, attempts < 100 {
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
