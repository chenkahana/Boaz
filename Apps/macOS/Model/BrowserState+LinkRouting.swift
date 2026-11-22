import AppKit
import BoazKit
import SwiftUI
import WebKit

// Link routing for a window: what a click, a script-opened window or a non-web scheme does. Split out of
// BrowserState without behavior changes; BrowserState keeps the state these decisions read and write.
extension BrowserState {
    /// Link routing: a middle-click or ⌘-click opens the link in a background tab right below this one, ⌘⇧-click in
    /// the foreground; pages that open new windows get a peek when they're pinned (keeps the pinned app in place)
    /// and otherwise a tab in front, right below theirs, so a page and what it opened stay together. A `window.open`
    /// asking for pop-up features opens in a sheet with its opener intact (`PagePopups`).
    func decide(_ action: WebPage.NavigationAction, context: NavigationRouter.Context) -> WKNavigationActionPolicy {
        let opensWindow = action.target == nil
        let downloadRequested = opensWindow && LinkDownloadMenu.takeRequest()
        // On the page's first navigation, before any script runs (`window.open` asks for its view without a
        // navigation decision; WebPage makes its WKWebView lazily). A link that opens a window, once allowed, goes to
        // the pop-up host too, which hands it back to `openWindowAsTab` unless it asked for pop-up features.
        var hostsPopups = false
        if case .tab(let id) = context, let page = pages[id] { hostsPopups = hostPopups(on: page, tabID: id) }
        guard let url = action.request.url, url.scheme?.hasPrefix("http") == true else {
            // A main-frame link for another app (`mailto:`, `tel:`, …): never navigate to it (WebKit would show
            // its raw error page); ask, then hand it to the app, as the Chromium build's dialog does.
            if downloadRequested { model.showToast("Boaz can't download this link"); return .cancel }
            if let url = action.request.url, action.target?.isMainFrame != false,
               ExternalLinkOpener.handles(url) {
                let host: String? = if case .tab(let id) = context { pages[id]?.url?.host() } else { nil }
                Task { await ExternalLinkOpener.confirmAndOpen(url, from: host) }
                return .cancel
            }
            return .allow
        }
        if action.shouldPerformDownload || downloadRequested {
            download(url, context: context)
            return .cancel
        }
        let flags = NSEvent.modifierFlags
        // A link, a form's button or anything else the user clicked to navigate, in any frame. WebKit reports the
        // button as a mask, as `NSEvent.pressedMouseButtons` does, so the middle one is 1 << 2. A form that posts
        // can't be reopened from its address alone, so it stays in this tab.
        let clicked = [.linkActivated, .formSubmitted].contains(action.navigationType)
            && action.request.httpMethod?.uppercased() ?? "GET" == "GET"
        let middleClick = action.buttonNumber == 1 << 2 && action.request.httpMethod?.uppercased() ?? "GET" == "GET"
        let newTabClick = middleClick || (clicked && flags.contains(.command))
        switch context {
        case .peek:
            if opensWindow || newTabClick { openTab(url); return .cancel }
            return .allow
        case .tab(let id):
            if newTabClick {
                openTab(url, below: tab(id), inBackground: !flags.contains(.shift))
                return .cancel
            }
            if opensWindow {
                if hostsPopups { return .allow }
                openWindowAsTab(url, from: id)
                return .cancel
            }
            return .allow
        }
    }

    private func openWindowAsTab(_ url: URL, from tabID: String) {
        if let tab = tab(tabID), model.isPinned(tab) {
            openPeek(url, profileID: tab.profileID)
        } else {
            openTab(url, below: tab(tabID))
        }
    }

    private func hostPopups(on page: WebPage, tabID: String) -> Bool {
        PagePopups.install(on: page, present: { [weak self] in self?.popup = $0 }, dismiss: { [weak self] closed in
            self?.popup = PagePopups.remaining(after: closed, shown: self?.popup)
        }, fallback: { [weak self] action in
            if let url = action.request.url { self?.openWindowAsTab(url, from: tabID) }
        })
    }
}

/// Bridges WebPage's navigation decisions back to the window that owns the page.
struct NavigationRouter: WebPage.NavigationDeciding {
    enum Context { case tab(String), peek }
    /// A reference, so a promoted peek's page routes as its tab from then on.
    final class Target { var context: Context; init(_ context: Context) { self.context = context } }

    weak var browser: BrowserState?
    let target: Target
    private var context: Context { target.context }

    init(browser: BrowserState, context: Context) {
        self.browser = browser
        target = Target(context)
    }

    func decidePolicy(for action: WebPage.NavigationAction,
                      preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        if browser?.javaScriptDisabled(context) == true { preferences.allowsContentJavaScript = false }
        return browser?.decide(action, context: context) ?? .allow
    }

    func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
        guard PageDownloads.shouldDownload(response), let url = response.response.url else { return .allow }
        browser?.download(url, context: context)
        return .cancel
    }
}
