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
    /// Levels set in private windows: applied to the page, never written to disk.
    private static var unsaved: [String: Double] = [:]

    static func level(for url: URL?) -> Double {
        guard let host = url?.host() else { return 1 }
        if let level = unsaved[host] { return level }
        return (UserDefaults.standard.dictionary(forKey: defaultsKey)?[host] as? Double) ?? 1
    }

    static func change(_ change: Change, for page: WebPage, remember: Bool) {
        let current = level(for: page.url)
        let index = levels.firstIndex { $0 >= current } ?? levels.count - 1
        let next = switch change {
        case .in: levels[min(index + (levels[index] > current ? 0 : 1), levels.count - 1)]
        case .out: levels[max(index - 1, 0)]
        case .reset: 1.0
        }
        if let host = page.url?.host() {
            if remember {
                var saved = UserDefaults.standard.dictionary(forKey: defaultsKey) ?? [:]
                saved[host] = next == 1 ? nil : next
                UserDefaults.standard.set(saved, forKey: defaultsKey)
            } else {
                unsaved[host] = next
            }
        }
        apply(to: page)
    }

    static func apply(to page: WebPage) {
        let level = level(for: page.url)
        Task {
            _ = try? await page.callJavaScript("document.documentElement.style.zoom = z === 1 ? '' : String(z);",
                                                arguments: ["z": level])
        }
    }
}
