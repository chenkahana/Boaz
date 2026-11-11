import WebKit

/// WebPage keeps its WKWebView to itself, and a few things need it: hosting pop-ups, WebKit's extension APIs (which
/// tab a script runs in) and Picture in Picture (a script call into one frame of the page). It's read through
/// reflection (a stored property, no private selector): if WebKit renames or drops the property, this returns nil,
/// pages still work, and new windows keep their old placement, extensions lose per-tab scripting and videos don't
/// float. docs/architecture.md lists what to check when the SDK changes.
func backingWebView(of page: WebPage) -> WKWebView? {
    Mirror(reflecting: page).children.lazy.compactMap { $0.value as? WKWebView }.first
}
