import BoazKit
import Foundation
import Observation

extension SearchEngine {
    /// The engine's suggestion endpoint, with `%@` where the encoded query goes. Each answers OpenSearch-style
    /// JSON: `["query", ["suggestion", …], …]`.
    var suggestionTemplate: String {
        switch self {
        case .duckDuckGo: "https://duckduckgo.com/ac/?q=%@&type=list"
        case .google: "https://www.google.com/complete/search?client=firefox&q=%@"
        case .bing: "https://www.bing.com/osjson.aspx?query=%@"
        case .brave: "https://search.brave.com/api/suggest?q=%@"
        case .kagi: "https://kagi.com/api/autosuggest?q=%@"
        case .ecosia: "https://ac.ecosia.org/autocomplete?q=%@&type=list"
        }
    }
}

/// Query suggestions from the selected search engine, fast enough to update on every keystroke.
///
/// Call `update(_:engine:)` with each edit. Updates made in the same run-loop turn coalesce into one request, and
/// each update cancels the request still in flight. Answers are kept in a small LRU cache, and while a longer
/// query is loading `suggestions` keeps showing the best cached answer for its prefix, so the list never empties
/// between keystrokes. `warm(_:)` opens the connection ahead of the first keystroke.
///
/// Requests carry only the typed query: no cookies, no cache, no referrer. Callers decide whether to ask at all
/// (not in private browsing, not for addresses; see `looksLikeAddress`).
@Observable final class SearchSuggestions {
    /// What to show for the latest query; may be the answer to one of its prefixes until its own arrives.
    private(set) var suggestions: [String] = []

    @ObservationIgnored private var query = ""
    @ObservationIgnored private var engine = SearchEngine.duckDuckGo
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var lastWarm: (engine: SearchEngine, at: Date)?
    @ObservationIgnored private var cache = LRUCache(capacity: 120)
    /// Rows shown at most, so an engine that answers 20 doesn't push the local matches away.
    private let limit = 8

    /// One connection pool for every request, so HTTP/2 keeps the connection to the engine alive between keystrokes.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 1.5
        configuration.httpMaximumConnectionsPerHost = 2
        return URLSession(configuration: configuration)
    }()

    /// Whether the text is an address rather than a query: those are never sent to the engine.
    static func looksLikeAddress(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("://") || text.lowercased().hasPrefix("localhost") { return true }
        return !text.contains(" ") && text.contains(".") && !text.hasSuffix(".")
    }

    func update(_ text: String, engine: SearchEngine) {
        let query = String(text.drop(while: \.isWhitespace))
        guard !query.isEmpty else { return clear() }
        // The same text again (a field can report one edit twice): what's showing or loading already answers it.
        if query == self.query, engine == self.engine, request != nil || cache[key(engine, query)] != nil { return }
        self.query = query
        self.engine = engine
        request?.cancel()
        request = nil
        if let answer = cache[key(engine, query)] {
            show(answer)
            return
        }
        // The best answer on hand until this query's own arrives: its longest cached prefix's matches, else the
        // rows already up. Never empty in between.
        if let prefixAnswer = cachedPrefixAnswer(for: query) { show(prefixAnswer) }
        // A task rather than a direct call: edits in the same run-loop turn cancel it before it starts.
        request = Task { [weak self] in await self?.load(query, engine: engine) }
    }

    /// Opens the connection to the engine so the first keystroke's request doesn't pay for DNS and TLS. A connection
    /// opened in the last minute is still open, so opening the panel again sends nothing.
    func warm(_ engine: SearchEngine) {
        guard lastWarm.map({ $0.engine != engine || $0.at.timeIntervalSinceNow < -60 }) ?? true,
              let url = Self.url(engine, query: "") else { return }
        lastWarm = (engine, .now)
        Task { _ = try? await Self.session.data(for: Self.request(url)) }
    }

    func clear() {
        request?.cancel()
        request = nil
        query = ""
        if !suggestions.isEmpty { suggestions = [] }
    }

    private func load(_ query: String, engine: SearchEngine) async {
        // Not cancelled means no newer update replaced this request.
        defer { if !Task.isCancelled { request = nil } }
        // A fast typist's next keystroke usually comes sooner, and would cancel this request right after sending it.
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled, let url = Self.url(engine, query: query),
              let (data, response) = try? await Self.session.data(for: Self.request(url)),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let answer = Self.parse(data) else { return }
        cache[key(engine, query)] = answer
        guard !Task.isCancelled, query == self.query, engine == self.engine else { return }
        show(answer)
    }

    private func show(_ answer: [String]) {
        let rows = Array(answer.prefix(limit))
        if rows != suggestions { suggestions = rows }
    }

    private func cachedPrefixAnswer(for query: String) -> [String]? {
        let lowered = query.lowercased()
        var prefix = Substring(query)
        while prefix.count > 1 {
            prefix = prefix.dropLast()
            guard let answer = cache[key(engine, String(prefix))] else { continue }
            let matches = answer.filter { $0.lowercased().hasPrefix(lowered) }
            return matches.isEmpty ? nil : matches
        }
        return nil
    }

    private func key(_ engine: SearchEngine, _ query: String) -> String { engine.rawValue + "\u{1F}" + query.lowercased() }

    private static func url(_ engine: SearchEngine, query: String) -> URL? {
        // Stricter than `.urlQueryAllowed`, which leaves `&`, `+` and `=` as they are.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: engine.suggestionTemplate.replacingOccurrences(of: "%@", with: encoded))
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1.5)
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// `["query", ["s1", "s2", …], …]`. Some engines answer in Latin-1 for some locales.
    private static func parse(_ data: Data) -> [String]? {
        let json = (try? JSONSerialization.jsonObject(with: data))
            ?? String(data: data, encoding: .isoLatin1).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) }
        guard let array = json as? [Any], array.count > 1, let list = array[1] as? [Any] else { return nil }
        var seen = Set<String>()
        return list.compactMap { $0 as? String }.filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// Least-recently-used answers by engine and query.
private struct LRUCache {
    let capacity: Int
    private var values: [String: [String]] = [:]
    private var order: [String] = []

    init(capacity: Int) { self.capacity = capacity }

    subscript(key: String) -> [String]? {
        mutating get {
            guard let value = values[key] else { return nil }
            touch(key)
            return value
        }
        set {
            values[key] = newValue
            guard newValue != nil else { order.removeAll { $0 == key }; return }
            touch(key)
            if order.count > capacity { values[order.removeFirst()] = nil }
        }
    }

    private mutating func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
