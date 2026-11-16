import Foundation

/// Turns what the user typed into a URL: a full URL, a bare domain, or a search.
public enum SearchInput {
    /// `schemes`: what a typed URL may use besides a search, e.g. `chrome` for Chromium's own pages.
    public static func url(for input: String,
                           searchTemplate: String = "https://duckduckgo.com/?q=%@",
                           schemes: Set<String> = ["http", "https"]) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let scheme = url.scheme, schemes.contains(scheme.lowercased()) {
            return url
        }
        // `about:blank` and `data:` URLs open as typed, as they do in Safari and Chrome, rather than as a search.
        if !text.contains(where: \.isWhitespace), let url = URL(string: text),
           let scheme = url.scheme, ["about", "data"].contains(scheme.lowercased()) {
            return url
        }
        if !text.contains(" "), text.contains("."), !text.hasSuffix("."), let url = URL(string: "https://" + text) {
            return url
        }
        let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        return URL(string: searchTemplate.replacingOccurrences(of: "%@", with: query))
    }
}
