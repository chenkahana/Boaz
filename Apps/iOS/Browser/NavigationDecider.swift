import WebKit

/// Per-page navigation policy: detects non-renderable responses (routed to `Downloads` instead of
/// failing to load) and reports back/forward navigations so the browser can fire a haptic at the
/// edge-swipe commit point.
struct FolioNavigationDecider: WebPage.NavigationDeciding {
    let onBackForward: @MainActor () -> Void
    let onDownload: @MainActor (URLResponse) -> Void

    @MainActor
    func decidePolicy(for action: WebPage.NavigationAction,
                       preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        if action.navigationType == .backForward { onBackForward() }
        return .allow
    }

    @MainActor
    func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
        guard !response.canShowMimeType else { return .allow }
        onDownload(response.response)
        return .cancel
    }
}
