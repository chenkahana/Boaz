import Foundation

/// Builds `boaz://` deep links for widget `Link` destinations. Deliberately duplicated (not
/// shared) from `Apps/iOS/Intents/DeepLink.swift`, which also depends on `AppModel` and so can't
/// be added to this extension target's sources without pulling the whole app target in.
enum BoazLink {
    static func search() -> URL {
        var components = URLComponents()
        components.scheme = "boaz"
        components.host = "search"
        return components.url!
    }

    static func open(_ target: URL) -> URL {
        var components = URLComponents()
        components.scheme = "boaz"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "url", value: target.absoluteString)]
        return components.url!
    }
}
