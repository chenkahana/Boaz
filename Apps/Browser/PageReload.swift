import Foundation
import WebKit

extension WebPage {
    /// Reloads, unless a load WebKit refused left about:blank in place of the page: reloading that would only show
    /// the same blank page, so `tabURL` loads instead (callers pass the refused address when the page shows it).
    /// `fromOrigin` skips the cache and asks the server again.
    @discardableResult
    func reload(tabURL: URL?, fromOrigin: Bool = false) -> any AsyncSequence<NavigationEvent, any Error> {
        if url?.absoluteString == "about:blank", let tabURL, tabURL.scheme?.hasPrefix("http") == true {
            return load(URLRequest(url: tabURL, cachePolicy: fromOrigin ? .reloadIgnoringLocalAndRemoteCacheData
                                                                         : .useProtocolCachePolicy))
        }
        return reload(fromOrigin: fromOrigin)
    }
}
