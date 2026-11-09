import WebKit

/// Per-page navigation policy: detects non-renderable responses (routed to `Downloads` instead of
/// failing to load), reports back/forward navigations so the browser can fire a haptic at the
/// edge-swipe commit point, and applies the page settings menu's per-host desktop site and pop-up choices.
struct BoazNavigationDecider: WebPage.NavigationDeciding {
    let onBackForward: @MainActor () -> Void
    let onDownload: @MainActor (URLResponse) -> Void

    @MainActor
    func decidePolicy(for action: WebPage.NavigationAction,
                       preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        if action.navigationType == .backForward { onBackForward() }
        let host = action.request.url?.host()
        preferences.preferredContentMode = PageSettings.settings(forHost: host).desktopSite ? .desktop : .recommended
        // A script-opened window (no target frame) has nowhere else to go — Boaz has no separate window
        // for it — so it would otherwise just navigate this tab in place. "Block" stops that outright.
        if action.target == nil, action.navigationType == .other,
           PageSettings.settings(forHost: host).popups == .block {
            return .cancel
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
