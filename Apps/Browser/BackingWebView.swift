import WebKit

/// WebPage keeps its WKWebView to itself, and a few things need it: WebKit's extension APIs (which tab a script runs
/// in) and Picture in Picture (a script call into one frame of the page). It's read through reflection, which calls
/// no private API: if WebKit renames the property, pages still work, without those two.
func backingWebView(of page: WebPage) -> WKWebView? {
    Mirror(reflecting: page).children.lazy.compactMap { $0.value as? WKWebView }.first
}
