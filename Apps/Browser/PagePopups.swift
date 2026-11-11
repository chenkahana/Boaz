import os
import SwiftUI
import WebKit

/// A window a page opened as a pop-up (`window.open(url, name, "width=500,height=600")`), in the `WKWebView` WebKit made
/// for it, so `window.opener` survives: OAuth sign-in pop-ups post their result back to the page that opened them.
@Observable
final class PagePopup: NSObject, Identifiable, WKUIDelegate {
    let webView: WKWebView
    /// The size the page asked for, if it did.
    let requestedSize: CGSize?
    /// The pop-up that opened this one, kept alive as its opener and shown again when this one closes.
    let parent: PagePopup?
    private(set) var url: URL?
    @ObservationIgnored fileprivate var isClosed = false
    @ObservationIgnored private let present: (PagePopup) -> Void
    @ObservationIgnored private let dismiss: (PagePopup) -> Void
    @ObservationIgnored private var observation: NSKeyValueObservation?

    fileprivate init(configuration: WKWebViewConfiguration, features: WKWindowFeatures, parent: PagePopup? = nil,
                     present: @escaping (PagePopup) -> Void, dismiss: @escaping (PagePopup) -> Void) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        requestedSize = features.width.flatMap { width in features.height.map { CGSize(width: width.doubleValue, height: $0.doubleValue) } }
        self.parent = parent
        self.present = present
        self.dismiss = dismiss
        super.init()
        webView.uiDelegate = self
        observation = webView.observe(\.url) { [weak self] view, _ in MainActor.assumeIsolated { self?.url = view.url } }
    }

    func close() { dismiss(self) }

    /// `window.close()`.
    func webViewDidClose(_ webView: WKWebView) { close() }

    /// A pop-up the pop-up opens (a sign-in page handing over to its provider) takes its place until it closes; any
    /// other window loads in the pop-up, as a peek's does.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard PagePopups.isPopup(windowFeatures) else {
            webView.load(action.request)
            return nil
        }
        let child = PagePopup(configuration: configuration, features: windowFeatures, parent: self, present: present,
                              dismiss: dismiss)
        present(child)
        return child.webView
    }
}

/// Hosts pop-ups for pages shown through `WebPage`, whose API has no new-window hook (checked through the macOS 27.2 and
/// iOS 27.2 SDKs). WebKit asks the opener's `WKWebView.uiDelegate` for a pop-up's view, so Boaz puts `PopupOpener` in
/// front of WebPage's own delegate: it answers that one question and passes every other one to WebPage's.
enum PagePopups {
    private static let log = Logger(subsystem: "com.chenkahana.boaz", category: "popups")
    private static var loggedFailure = false
    private static var openerKey = 0

    /// Puts the pop-up host on `page`, once. `present` shows a pop-up and `dismiss` takes it away (on `window.close()`,
    /// its close button, or when the opener's page goes); `fallback` places any other http(s) window (a `target=_blank`
    /// link, `window.open` without pop-up features). `allowsScriptWindows` is the site's pop-up setting: when it's
    /// false, windows a script opens get nothing, and links the user follows still open. False when WebPage's
    /// internals aren't what Boaz expects: the caller keeps its old behavior.
    static func install(on page: WebPage, allowsScriptWindows: @escaping () -> Bool = { true },
                        present: @escaping (PagePopup) -> Void, dismiss: @escaping (PagePopup) -> Void,
                        fallback: @escaping (WKNavigationAction) -> Void) -> Bool {
        guard let webView = backingWebView(of: page) else { return failed("no WKWebView behind WebPage") }
        if webView.uiDelegate is PopupOpener { return true }
        guard let original = webView.uiDelegate as? NSObject,
              NSStringFromClass(type(of: original)).hasPrefix("WebKit.") else {
            return failed("unexpected UI delegate \(String(describing: webView.uiDelegate))")
        }
        let opener = PopupOpener(original: original, allowsScriptWindows: allowsScriptWindows, present: present,
                                 dismiss: dismiss, fallback: fallback)
        // `uiDelegate` is weak: the opener lives as long as the view does.
        objc_setAssociatedObject(webView, &openerKey, opener, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        webView.uiDelegate = opener
        return true
    }

    /// The pop-up to show once `closed` closes, given the one on screen: unchanged unless `closed` is that one or
    /// opened it, then the nearest pop-up up the chain that's still open, or none.
    static func remaining(after closed: PagePopup, shown: PagePopup?) -> PagePopup? {
        closed.isClosed = true
        var remaining = shown
        var popup = shown
        while let current = popup {
            if current.isClosed { remaining = current.parent }
            popup = current.parent
        }
        return remaining
    }

    private static func failed(_ reason: String) -> Bool {
        if !loggedFailure {
            loggedFailure = true
            log.error("No pop-up host, new windows keep their old placement: \(reason, privacy: .public)")
        }
        return false
    }

    /// Safari's rule: `window.open` asking for a size, a position or no browser chrome gets a window; anything else is
    /// a tab.
    static func isPopup(_ features: WKWindowFeatures) -> Bool {
        [features.width, features.height, features.x, features.y].contains { $0 != nil }
            || [features.toolbarsVisibility, features.menuBarVisibility].contains { $0?.boolValue == false }
    }
}

/// WebPage keeps its WKWebView to itself; Boaz needs it to host pop-ups and to tell WebKit's extension APIs which tab
/// a script runs in. It's read through reflection (a stored property, no private selector): if WebKit renames or
/// drops the property, this returns nil, new windows keep their old placement and extensions lose per-tab scripting.
/// docs/architecture.md lists what to check when the SDK changes.
func backingWebView(of page: WebPage) -> WKWebView? {
    Mirror(reflecting: page).children.lazy.compactMap { $0.value as? WKWebView }.first
}

/// The opener's UI delegate: makes pop-up views and forwards everything else to WebPage's delegate, which it keeps.
private final class PopupOpener: NSObject, WKUIDelegate {
    nonisolated(unsafe) private let original: NSObject
    private let allowsScriptWindows: () -> Bool
    private let present: (PagePopup) -> Void
    private let dismiss: (PagePopup) -> Void
    private let fallback: (WKNavigationAction) -> Void
    private weak var popup: PagePopup?

    init(original: NSObject, allowsScriptWindows: @escaping () -> Bool, present: @escaping (PagePopup) -> Void,
         dismiss: @escaping (PagePopup) -> Void, fallback: @escaping (WKNavigationAction) -> Void) {
        self.original = original
        self.allowsScriptWindows = allowsScriptWindows
        self.present = present
        self.dismiss = dismiss
        self.fallback = fallback
    }

    /// The opener's view is gone (its tab closed or unloaded), so is its pop-up.
    isolated deinit { popup?.close() }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.navigationType != .linkActivated, !allowsScriptWindows() { return nil }
        if PagePopups.isPopup(windowFeatures) {
            popup?.close()
            // The configuration WebKit passes is the opener's: same data store (incognito stays in memory),
            // content blockers, scripts and extensions.
            let popup = PagePopup(configuration: configuration, features: windowFeatures, present: present,
                                  dismiss: dismiss)
            self.popup = popup
            present(popup)
            return popup.webView
        }
        if action.request.url?.scheme?.hasPrefix("http") == true {
            fallback(action)
            return nil
        }
        // An about:blank window without pop-up features: whatever WebPage does with it (today, nothing).
        return (original as? WKUIDelegate)?.webView?(webView, createWebViewWith: configuration, for: action,
                                                     windowFeatures: windowFeatures)
    }

    override nonisolated func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original.responds(to: selector)
    }

    override nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
        original.responds(to: selector) ? original : super.forwardingTarget(for: selector)
    }
}

/// A pop-up's page with its address and a close button.
struct PopupSheet: View {
    let popup: PagePopup

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: popup.url?.scheme == "https" ? "lock.fill" : "globe")
                    .font(.caption).foregroundStyle(.secondary)
                Text(popup.url?.host() ?? "Loading…")
                    .font(.callout.weight(.medium)).lineLimit(1)
                Spacer()
                Button("Close", systemImage: "xmark", action: popup.close)
                    .labelStyle(.iconOnly)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 12).frame(height: 40)
            PopupWebView(webView: popup.webView)
        }
        #if os(macOS)
        .frame(width: min(max(popup.requestedSize?.width ?? 500, 360), 900),
               height: min(max(popup.requestedSize?.height ?? 640, 400), 800))
        #endif
    }
}

#if os(macOS)
private struct PopupWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
#else
private struct PopupWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
#endif
