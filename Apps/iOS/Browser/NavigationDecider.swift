import WebKit

/// Per-page navigation policy: detects non-renderable responses (routed to `Downloads` instead of
/// failing to load), reports back/forward navigations so the browser can fire a haptic at the
/// edge-swipe commit point, and applies the page settings menu's per-host desktop site and pop-up choices.
struct BoazNavigationDecider: WebPage.NavigationDeciding {
    let isPrivate: Bool
    /// The page this decides for. It's created with the decider, so it's looked up rather than held.
    let page: @MainActor () -> WebPage?
    let onBackForward: @MainActor () -> Void
    let onDownload: @MainActor (URLResponse) -> Void

    @MainActor
    func decidePolicy(for action: WebPage.NavigationAction,
                       preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        if action.navigationType == .backForward { onBackForward() }
        // A pop-up is decided by the page that opened it: its destination is often a sign-in host the user has
        // never set anything for. A script-opened window (no target frame) has nowhere else to go — Boaz has no
        // separate window for it — so it navigates this tab in place unless the opener's site blocks pop-ups.
        if action.target == nil, action.navigationType == .other,
           PageSettings.settings(for: page()?.url, isPrivate: isPrivate).popups == .block {
            return .cancel
        }
        // Desktop or mobile site follows the destination, so it's right on a tab's first load and when a link
        // leaves the site.
        if action.target?.isMainFrame != false {
            let host = action.request.url?.host()
            preferences.preferredContentMode =
                PageSettings.settings(forHost: host, isPrivate: isPrivate).desktopSite ? .desktop : .recommended
            page()?.customUserAgent = PageSettings.userAgent(forHost: host, isPrivate: isPrivate)
        }
        return .allow
    }

    @MainActor
    func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
        guard !response.canShowMimeType else { return .allow }
        onDownload(response.response)
        return .cancel
    }
}
