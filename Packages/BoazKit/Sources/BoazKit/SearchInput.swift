import Foundation

/// Turns what the user typed into a URL: a full URL, a bare domain, or a search.
public enum SearchInput {
    public static func url(for input: String,
                           searchTemplate: String = "https://duckduckgo.com/?q=%@") -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) {
            return url
        }
        if !text.contains(" "), text.contains("."), !text.hasSuffix("."), let url = URL(string: "https://" + text) {
            return url
        }
        let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        return URL(string: searchTemplate.replacingOccurrences(of: "%@", with: query))
    }
}
