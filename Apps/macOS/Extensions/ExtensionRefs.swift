import AppKit
import BoazKit
import WebKit

/// A Boaz tab as extensions see it (`chrome.tabs`).
final class ExtensionTab: NSObject, WKWebExtensionTab {
    let id: String
    weak var browser: BrowserState?

    init(id: String, browser: BrowserState) {
        self.id = id
        self.browser = browser
    }

    private var tab: SidebarItem? { browser?.tab(id) }
    private var page: WebPage? { browser?.existingPage(for: id) }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        browser.map { Extensions.shared.windowRef($0) }
    }

    func indexInWindow(for context: WKWebExtensionContext) -> Int {
        browser?.cycleTabs.firstIndex { $0.id == id } ?? 0
    }

    func webView(for context: WKWebExtensionContext) -> WKWebView? { page.flatMap(backingWebView(of:)) }
    func title(for context: WKWebExtensionContext) -> String? { page?.title ?? tab?.title }
    func url(for context: WKWebExtensionContext) -> URL? { page?.url ?? tab?.url }
    func isPinned(for context: WKWebExtensionContext) -> Bool { tab.map { MacModel.shared.isPinned($0) } ?? false }
    func isSelected(for context: WKWebExtensionContext) -> Bool { browser?.activeTabID == id }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !(page?.isLoading ?? false) }

    func activate(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if let tab { browser?.activate(tab) }
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if let tab { browser?.close(tab) }
        completionHandler(nil)
    }

    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if let tab, let browser { browser.page(for: tab).load(URLRequest(url: url)) }
        completionHandler(nil)
    }

    func reload(fromOrigin: Bool, for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        page?.reload(tabURL: tab?.url, fromOrigin: fromOrigin)
        completionHandler(nil)
    }

    func goBack(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if let page, let item = page.backForwardList.backList.last { page.load(item) }
        completionHandler(nil)
    }

    func goForward(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        if let page, let item = page.backForwardList.forwardList.first { page.load(item) }
        completionHandler(nil)
    }
}

/// A Boaz window as extensions see it (`chrome.windows`): the tabs of the space it shows.
final class ExtensionWindow: NSObject, WKWebExtensionWindow {
    weak var browser: BrowserState?

    init(browser: BrowserState) { self.browser = browser }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
        guard let browser else { return [] }
        return browser.cycleTabs.map { Extensions.shared.tabRef($0.id, in: browser) }
    }

    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let browser, let id = browser.activeTabID else { return nil }
        return Extensions.shared.tabRef(id, in: browser)
    }

    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window = browser?.window else { return .normal }
        return window.isMiniaturized ? .minimized : window.styleMask.contains(.fullScreen) ? .fullscreen : .normal
    }

    func isPrivate(for context: WKWebExtensionContext) -> Bool { browser?.isIncognito ?? false }
    func frame(for context: WKWebExtensionContext) -> CGRect { browser?.window?.frame ?? .null }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect { browser?.window?.screen?.frame ?? .null }

    func focus(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        browser?.window?.makeKeyAndOrderFront(nil)
        completionHandler(nil)
    }

    func close(for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        browser?.window?.performClose(nil)
        completionHandler(nil)
    }
}
