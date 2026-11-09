import Foundation
import WebKit

/// Page zoom (Mac: ⌘+ ⌘− ⌘0; iPhone: the page settings menu's Text Size), remembered per host. WebPage has
/// no zoom property, so it's CSS `zoom` on the root element, reapplied after each navigation. Lives in
/// `Apps/Browser` so both apps compile it.
enum PageZoom {
    enum Change { case `in`, out, reset }

    /// Safari's steps.
    private static let levels: [Double] = [0.5, 0.75, 0.85, 1, 1.15, 1.25, 1.5, 1.75, 2, 2.5, 3]
    private static let defaultsKey = "pageZoomByHost"
    /// Levels set in private windows and tabs: applied to private pages only, never written to disk.
    private static var unsaved: [String: Double] = [:]

    static func level(for url: URL?, isPrivate: Bool) -> Double {
        guard let host = url?.host() else { return 1 }
        if isPrivate, let level = unsaved[host] { return level }
        return (UserDefaults.standard.dictionary(forKey: defaultsKey)?[host] as? Double) ?? 1
    }

    static func change(_ change: Change, for page: WebPage, isPrivate: Bool) {
        let current = level(for: page.url, isPrivate: isPrivate)
        let index = levels.firstIndex { $0 >= current } ?? levels.count - 1
        let next = switch change {
        case .in: levels[min(index + (levels[index] > current ? 0 : 1), levels.count - 1)]
        case .out: levels[max(index - 1, 0)]
        case .reset: 1.0
        }
        if let host = page.url?.host() {
            if isPrivate {
                unsaved[host] = next
            } else {
                var saved = UserDefaults.standard.dictionary(forKey: defaultsKey) ?? [:]
                saved[host] = next == 1 ? nil : next
                UserDefaults.standard.set(saved, forKey: defaultsKey)
            }
        }
        apply(to: page, isPrivate: isPrivate)
    }

    static func apply(to page: WebPage, isPrivate: Bool) {
        let level = level(for: page.url, isPrivate: isPrivate)
        Task {
            _ = try? await page.callJavaScript("document.documentElement.style.zoom = z === 1 ? '' : String(z);",
                                                arguments: ["z": level])
        }
    }

    /// Called when private browsing ends (iPhone: leaving Incognito).
    static func forgetPrivateLevels() { unsaved = [:] }
}
