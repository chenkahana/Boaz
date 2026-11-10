import Foundation
import WebKit

extension WebPage {
    /// Reloads, unless a load WebKit refused left about:blank in place of the page: reloading that would only show
    /// the same blank page, so the tab's own address loads instead.
    @discardableResult
    func reload(tabURL: URL?) -> any AsyncSequence<NavigationEvent, any Error> {
        if url?.absoluteString == "about:blank", let tabURL, tabURL.scheme?.hasPrefix("http") == true {
            return load(URLRequest(url: tabURL))
        }
        return reload()
    }
}
