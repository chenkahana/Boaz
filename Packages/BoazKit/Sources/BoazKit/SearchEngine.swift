import Foundation

public enum SearchEngine: String, CaseIterable, Codable, Sendable, Identifiable {
    case duckDuckGo, google, bing, brave, kagi, ecosia

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .duckDuckGo: "DuckDuckGo"
        case .google: "Google"
        case .bing: "Bing"
        case .brave: "Brave Search"
        case .kagi: "Kagi"
        case .ecosia: "Ecosia"
        }
    }

    /// Query URL with `%@` where the encoded search terms go.
    public var template: String {
        switch self {
        case .duckDuckGo: "https://duckduckgo.com/?q=%@"
        case .google: "https://www.google.com/search?q=%@"
        case .bing: "https://www.bing.com/search?q=%@"
        case .brave: "https://search.brave.com/search?q=%@"
        case .kagi: "https://kagi.com/search?q=%@"
        case .ecosia: "https://www.ecosia.org/search?q=%@"
        }
    }
}
