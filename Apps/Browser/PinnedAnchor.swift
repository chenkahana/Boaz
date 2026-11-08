import Foundation
import WebKit

/// Pinned and favorite tabs keep the address they were pinned at, as in Arc: browsing inside one moves only its
/// live page, never the saved item, so it comes back to the same place after it unloads, syncs or relaunches.
enum PinnedAnchor {
    /// Whether the page has browsed away from the tab's saved address. Where the first load landed counts as
    /// home too, since sites often redirect their front door (x.com → /home).
    static func hasWandered(_ page: WebPage, from saved: URL?) -> Bool {
        guard let saved, let current = page.url, let landing = page.backForwardList.backList.first?.url
        else { return false }
        return !sameLocation(current, saved) && !sameLocation(current, landing)
    }

    /// Same host (ignoring "www.") and path (ignoring a trailing slash), so the redirects sites do on load
    /// don't count as leaving.
    static func sameLocation(_ a: URL, _ b: URL) -> Bool {
        func host(_ url: URL) -> String {
            let host = url.host()?.lowercased() ?? ""
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        func path(_ url: URL) -> String {
            var path = url.path()
            while path.hasSuffix("/") { path.removeLast() }
            return path
        }
        return host(a) == host(b) && path(a) == path(b)
    }
}
