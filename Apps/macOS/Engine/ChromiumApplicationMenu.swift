#if BOAZ_CHROMIUM
import AppKit
import SwiftUI

@MainActor
final class ChromiumApplicationMenu: NSObject, NSMenuItemValidation {
    private struct Entry {
        let command: BrowserCommand?
        let enabled: (BrowserState?) -> Bool
        let perform: (BrowserState?) -> Void
        let title: ((BrowserState?) -> String)?
        let checked: ((BrowserState?) -> Bool)?
    }
    private let activeBrowser: () -> BrowserState?
    private let openScene: (String) -> Void
    private let quit: () -> Void
    private var entries: [Int: Entry] = [:]

    init(activeBrowser: @escaping () -> BrowserState?, openScene: @escaping (String) -> Void,
         quit: @escaping () -> Void) {
        self.activeBrowser = activeBrowser
        self.openScene = openScene
        self.quit = quit
        super.init()
    }

    func install() {
        entries.removeAll()
        let bar = NSMenu()
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let result = NSMenu(title: title)
            item.submenu = result
            bar.addItem(item)
            return result
        }
        let app = menu("Boaz")
        responder(app, "About Boaz", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        add(app, "Settings…", enabled: { _ in true }, perform: { [weak self] _ in self?.openScene("settings") }, key: ",")
        add(app, "Load Developer Extension…", enabled: {
            $0?.isIncognito == false && $0?.loadChromiumDeveloperExtension != nil
        }) { $0?.loadChromiumDeveloperExtension?() }
        add(app, "Install Chromium Extension…", enabled: {
            $0?.isIncognito == false && $0?.installChromiumExtension != nil
        }) { $0?.installChromiumExtension?() }
        add(app, "Manage Chromium Extensions…", enabled: {
            $0?.isIncognito == false && $0?.manageChromiumExtensions != nil
        }) { $0?.manageChromiumExtensions?() }
        add(app, "Review Previous Extensions…", enabled: {
            $0?.isIncognito == false && $0?.reviewPreviousChromiumExtensions != nil
        }) { $0?.reviewPreviousChromiumExtensions?() }
        app.addItem(.separator())
        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        app.addItem(servicesItem)
        NSApp.servicesMenu = services
        responder(app, "Hide Boaz", #selector(NSApplication.hide(_:)), key: "h")
        responder(app, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option])
        responder(app, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add(app, "Quit Boaz", enabled: { _ in true }, perform: { [weak self] _ in self?.quit() }, key: "q")

        let hasEnginePage: (BrowserState?) -> Bool = {
            $0?.activeEnginePage?.state.lifecycle == .active
        }
        let hasChromiumPage: (BrowserState?) -> Bool = {
            $0?.activeEnginePage?.adapter is ChromiumEnginePageAdapter
        }
        let hasWebKitPage: (BrowserState?) -> Bool = {
            $0?.activeEnginePage?.kind == .webKit && $0?.activeEnginePage?.state.lifecycle == .active
        }
        let file = menu("File")
        add(file, "New Tab", command: .newTab) { $0?.commandMode = .newTab }
        for (title, scene, command) in [("New Window", "main", BrowserCommand.newWindow),
                ("New Incognito Window", "incognito", .newIncognitoWindow),
                ("New Quick Window", "little", .newLittleWindow)] {
            add(file, title, command: command, enabled: { _ in true }) { [weak self] _ in self?.openScene(scene) }
        }
        file.addItem(.separator())
        add(file, "Open Location…", command: .openLocation) {
            $0?.commandMode = $0?.activeTab == nil ? .newTab : .currentTab
        }
        add(file, "Close Tab", command: .closeTab, enabled: { browser in
            browser != nil || (NSApp.keyWindow?.styleMask.contains(.closable) == true && NSApp.keyWindow?.sheetParent == nil)
        }, title: { $0?.activeTab == nil ? "Close Window" : "Close Tab" }) {
            if let browser = $0 { browser.closeActive() } else { NSApp.keyWindow?.performClose(nil) }
        }
        add(file, "Reopen Closed Tab", command: .reopenClosedTab,
            enabled: { $0 != nil && $0?.isIncognito == false }) { $0?.reopenClosedTab() }

        file.addItem(.separator())
        add(file, "Print…", enabled: hasEnginePage, perform: { browser in
            if let page = browser?.activeEnginePage?.adapter as? ChromiumEnginePageAdapter {
                do { try page.printPage() } catch { MacModel.shared.showToast(error.localizedDescription) }
            } else if hasWebKitPage(browser) { browser?.printActive() }
        }, key: "p")

        add(file, "Save Page as PDF…", enabled: hasEnginePage) { browser in
            if let page = browser?.activeEnginePage?.adapter as? ChromiumEnginePageAdapter {
                ChromiumPageCapture.exportPDF(from: page, window: browser?.window) { MacModel.shared.showToast($0) }
            } else if hasWebKitPage(browser) { browser?.exportPDF() }
        }

        let edit = menu("Edit")
        responder(edit, "Undo", Selector(("undo:")), key: "z")
        responder(edit, "Redo", Selector(("redo:")), key: "z", modifiers: [.command, .shift])
        edit.addItem(.separator())
        responder(edit, "Cut", #selector(NSText.cut(_:)), key: "x")
        responder(edit, "Copy", #selector(NSText.copy(_:)), key: "c")
        responder(edit, "Paste", #selector(NSText.paste(_:)), key: "v")
        responder(edit, "Select All", #selector(NSText.selectAll(_:)), key: "a")
        edit.addItem(.separator())
        add(edit, "Copy URL", command: .copyURL, enabled: { $0?.activeURL != nil }) { $0?.copyActiveURL() }

        add(edit, "Find…", command: .find, enabled: { $0?.activeTab != nil }) { $0?.findVisible = true }

        let passwords = menu("Passwords")
        add(passwords, "Fill Saved Password…", enabled: {
            ($0?.activeEnginePage?.adapter as? ChromiumEnginePageAdapter)?.state.lifecycle == .active
        }) { browser in
            guard let browser, let page = browser.activeEnginePage?.adapter as? ChromiumEnginePageAdapter,
                  let window = browser.window, window.attachedSheet == nil else { return }
            Task { await ChromiumPasswordFill.run(on: page, window: window) { browser.model.showToast($0) } }
        }

        let view = menu("View")
        add(view, "Hide Sidebar", command: .toggleSidebar,
            title: { $0?.sidebarVisible == false ? "Show Sidebar" : "Hide Sidebar" }) { $0?.toggleSidebar() }
        add(view, "Reload Page", command: .reload, enabled: { $0?.activeTab != nil }) { $0?.reload() }
        add(view, "Back", command: .goBack, enabled: { $0?.activeTab != nil }) { $0?.goBack() }
        add(view, "Forward", command: .goForward, enabled: { $0?.activeTab != nil }) { $0?.goForward() }
        add(view, "Zoom In", enabled: { $0?.activeTab != nil }, perform: { $0?.zoom(.in) }, key: "+")
        add(view, "Zoom Out", enabled: { $0?.activeTab != nil }, perform: { $0?.zoom(.out) }, key: "-")
        add(view, "Actual Size", enabled: { $0?.activeTab != nil }, perform: { $0?.zoom(.reset) }, key: "0")
        add(view, "Add Split View", command: .addSplitView, enabled: { $0?.activeTab != nil },
            title: { $0?.split == nil ? "Add Split View" : "Close Split View" }) { $0?.toggleSplit() }
        responder(view, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), key: "f", modifiers: [.command, .control])
        add(view, "Archive", command: .showArchive, enabled: { _ in true }) { [weak self] _ in self?.openScene("archive") }
        add(view, "Downloads…", enabled: { $0?.chromiumProfileIdentity != nil }) {
            guard let identity = $0?.chromiumProfileIdentity else { return }
            ChromiumRuntime.showDownloads(for: identity)
        }
        let history = menu("History")
        add(history, "Show All History", enabled: { _ in true }, perform: { [weak self] _ in self?.openScene("history") }, key: "y")

        let tabs = menu("Tabs")
        add(tabs, "Pin Tab", command: .pinTab, enabled: { $0?.activeTab != nil && $0?.isIncognito == false },
            title: { browser in browser?.activeTab.map { MacModel.shared.isPinned($0) } == true ? "Unpin Tab" : "Pin Tab" }) { $0?.togglePinActive() }
        add(tabs, "Next Tab", command: .nextTab) { $0?.cycleTab(by: 1) }
        add(tabs, "Previous Tab", command: .previousTab) { $0?.cycleTab(by: -1) }
        for number in 1...9 {
            add(tabs, "Favorite \(number)", enabled: { browser in
                guard let browser else { return false }
                return number <= MacModel.shared.favorites(profileID: browser.currentSpace?.profileID).count
            }, perform: { $0?.selectFavorite(number) }, key: String(number))
        }
        let spaces = menu("Spaces")
        add(spaces, "Next Space", command: .nextSpace) { $0?.shiftSpace(by: 1) }
        add(spaces, "Previous Space", command: .previousSpace) { $0?.shiftSpace(by: -1) }
        for number in 1...9 {
            add(spaces, "Space \(number)", enabled: { $0 != nil && MacModel.shared.sidebar.spaces.count >= number },
                title: { _ in
                    let values = MacModel.shared.sidebar.spaces
                    guard values.count >= number else { return "Space \(number)" }
                    let space = values[number - 1]
                    return (space.icon.map { $0 + " " } ?? "") + space.title
                }, perform: { $0?.selectSpace(number) }, key: String(number), modifiers: .control)
        }
        add(spaces, "New Space", command: .newSpace) { $0?.newSpace() }
        let pageMenu = menu("Page")
        add(pageMenu, "Open Page in WebKit", enabled: { browser in
            guard let browser, let tab = browser.activeTab else { return false }
            return browser.engineKind(for: tab) != .webKit
        }) { browser in Task { await browser?.switchActiveEngine(to: .webKit) } }
        add(pageMenu, "Open Page in Chromium", enabled: { browser in
            guard let browser, let tab = browser.activeTab else { return false }
            return browser.engineKind(for: tab) != .chromium
        }) { browser in Task { await browser?.switchActiveEngine(to: .chromium) } }

        let develop = menu("Develop")
        add(develop, "Responsive Viewport…", command: .responsiveDesignMode,
            enabled: hasEnginePage) { browser in
                if let page = browser?.activeEnginePage?.adapter as? ChromiumEnginePageAdapter {
                    page.responsiveVisible = true
                } else if hasWebKitPage(browser) { browser?.toggleResponsiveDesign() }
            }
        let hasPage: (BrowserState?) -> Bool = {
            $0?.activeEnginePage?.adapter is ChromiumEnginePageAdapter
        }
        add(develop, "Show Developer Tools", enabled: hasPage, perform: {
            Self.showDevTools(BOAZ_DEVTOOLS_SHOW, browser: $0)
        }, key: "i", modifiers: [.command, .option])
        add(develop, "Show JavaScript Console", command: .javaScriptConsole, enabled: hasEnginePage) { browser in
            if hasWebKitPage(browser) { browser?.devTools.toggleConsole() }
            else { Self.showDevTools(BOAZ_DEVTOOLS_CONSOLE, browser: browser) }
        }
        add(develop, "Inspect Element", enabled: hasPage, perform: {
            Self.showDevTools(BOAZ_DEVTOOLS_INSPECT, browser: $0)
        }, key: "c", modifiers: [.command, .option])
        add(develop, "WebKit Inspect Element: Right-click the page", enabled: { _ in false }) { _ in }
        develop.addItem(.separator())
        add(develop, "Capture Visible Area…", enabled: hasEnginePage) { browser in
            if let adapter = browser?.activeEnginePage?.adapter as? ChromiumEnginePageAdapter {
                ChromiumPageCapture.exportVisible(from: adapter, window: browser?.window) {
                    MacModel.shared.showToast($0)
                }
            } else if hasWebKitPage(browser) { browser?.captureScreenshot(fullPage: false) }
        }
        add(develop, "Capture Full Page…", enabled: hasEnginePage) { browser in
            if let adapter = browser?.activeEnginePage?.adapter as? ChromiumEnginePageAdapter {
                ChromiumPageCapture.exportFullPage(from: adapter, window: browser?.window) {
                    MacModel.shared.showToast($0)
                }
            } else if hasWebKitPage(browser) { browser?.captureScreenshot(fullPage: true) }
        }
        add(develop, "View Page Source", command: .viewSource, enabled: hasEnginePage) { browser in
            guard let browser else { return }
            if browser.activeEnginePage?.adapter is ChromiumEnginePageAdapter {
                ChromiumPageSource.show(in: browser)
            } else if hasWebKitPage(browser) { browser.viewPageSource() }
        }
        add(develop, "Show Storage…", enabled: hasEnginePage) { browser in
            if hasWebKitPage(browser) { browser?.showStorage() }
            else { Self.showDevTools(BOAZ_DEVTOOLS_STORAGE, browser: browser) }
        }
        add(develop, "Show Performance", enabled: hasChromiumPage) {
            Self.showDevTools(BOAZ_DEVTOOLS_PERFORMANCE, browser: $0)
        }
        add(develop, "Show Lighthouse", enabled: hasChromiumPage) {
            Self.showDevTools(BOAZ_DEVTOOLS_LIGHTHOUSE, browser: $0)
        }
        add(develop, "Empty Caches", command: .emptyCaches, enabled: { browser in
            hasEnginePage(browser) && !ChromiumCache.isPending(for: browser?.activeEnginePage?.profile)
        }) { browser in
            guard let browser else { return }
            if browser.activeEnginePage?.adapter is ChromiumEnginePageAdapter {
                ChromiumCache.clear(in: browser)
            } else if hasWebKitPage(browser) { browser.emptyCaches() }
        }
        develop.addItem(.separator())
        func webKitSubmenu(_ title: String) -> NSMenu {
            add(develop, title, enabled: hasWebKitPage) { _ in }
            let submenu = NSMenu(title: title)
            develop.items.last?.submenu = submenu
            return submenu
        }
        func state(_ browser: BrowserState?) -> DevTools.TabState {
            browser?.devTools[browser?.activeTabID] ?? DevTools.TabState()
        }
        let agents = webKitSubmenu("WebKit User Agent")
        add(agents, "Default", enabled: hasWebKitPage,
            checked: { (state($0).effectiveUserAgent ?? .default) == .default }) { $0?.setUserAgent(.default) }
        agents.addItem(.separator())
        for agent in UserAgent.presets {
            add(agents, agent.title, enabled: hasWebKitPage,
                checked: { state($0).effectiveUserAgent == agent }) { $0?.setUserAgent(agent) }
        }
        agents.addItem(.separator())
        add(agents, "Other…", enabled: hasWebKitPage, checked: {
            if case .custom = state($0).effectiveUserAgent { return true }
            return false
        }) { browser in
            if let id = browser?.activeTabID { browser?.devTools.sheet = .userAgent(tabID: id) }
        }
        let media = webKitSubmenu("WebKit Emulate Media")
        add(media, "Screen", enabled: hasWebKitPage, checked: { state($0).media != .print }) { $0?.setMediaType(nil) }
        add(media, "Print", enabled: hasWebKitPage, checked: { state($0).media == .print }) { $0?.setMediaType(.print) }
        media.addItem(.separator())
        add(media, "Light Appearance", enabled: hasWebKitPage, checked: { state($0).appearance == .light }) { $0?.setAppearance(.light) }
        add(media, "Dark Appearance", enabled: hasWebKitPage, checked: { state($0).appearance == .dark }) { $0?.setAppearance(.dark) }
        add(media, "System Appearance", enabled: hasWebKitPage, checked: { state($0).appearance == nil }) { $0?.setAppearance(nil) }
        let vision = webKitSubmenu("WebKit Vision Simulator")
        for mode in Vision.allCases {
            add(vision, mode.title, enabled: hasWebKitPage, checked: { state($0).vision == mode }) { $0?.setVision(mode) }
            if mode == .none { vision.addItem(.separator()) }
        }
        add(develop, "Disable JavaScript", enabled: { $0?.activeEnginePage?.state.lifecycle == .active },
            checked: { state($0).javaScriptDisabled }) { $0?.toggleJavaScript() }

        let window = menu("Window")
        responder(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), key: "m")
        responder(window, "Zoom", #selector(NSWindow.performZoom(_:)))
        responder(window, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        NSApp.windowsMenu = window
        NSApp.mainMenu = bar
    }

    private static func showDevTools(_ action: BoazHostDevToolsAction, browser: BrowserState?) {
        guard let adapter = browser?.activeEnginePage?.adapter as? ChromiumEnginePageAdapter else { return }
        do { try adapter.showDevTools(action) }
        catch { MacModel.shared.showToast(error.localizedDescription) }
    }

    private func add(_ menu: NSMenu, _ title: String, command: BrowserCommand? = nil,
                     enabled: @escaping (BrowserState?) -> Bool = { $0 != nil },
                     title dynamicTitle: ((BrowserState?) -> String)? = nil,
                     checked: ((BrowserState?) -> Bool)? = nil,
                     perform: @escaping (BrowserState?) -> Void,
                     key: String = "", modifiers: NSEvent.ModifierFlags = .command) {
        let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: key)
        item.target = self
        item.tag = entries.count + 1
        item.keyEquivalentModifierMask = modifiers
        entries[item.tag] = Entry(command: command, enabled: enabled, perform: perform, title: dynamicTitle, checked: checked)
        menu.addItem(item)
        _ = validateMenuItem(item)
    }
    private func responder(_ menu: NSMenu, _ title: String, _ selector: Selector,
                           key: String = "", modifiers: NSEvent.ModifierFlags = .command) {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let entry = entries[item.tag] else { return false }
        let browser = activeBrowser()
        if let title = entry.title { item.title = title(browser) }
        item.state = entry.checked?(browser) == true ? .on : .off
        if let command = entry.command {
            let shortcut = MacModel.shared.keyBindings.shortcut(command)
            item.keyEquivalent = shortcut.map { String($0.key.character) } ?? ""
            var flags: NSEvent.ModifierFlags = []
            if let modifiers = shortcut?.modifiers {
                if modifiers.contains(.command) { flags.insert(.command) }
                if modifiers.contains(.option) { flags.insert(.option) }
                if modifiers.contains(.control) { flags.insert(.control) }
                if modifiers.contains(.shift) { flags.insert(.shift) }
            }
            item.keyEquivalentModifierMask = flags
        }
        return entry.enabled(browser)
    }
    @objc private func invoke(_ item: NSMenuItem) {
        guard validateMenuItem(item), let entry = entries[item.tag] else { return }
        entry.perform(activeBrowser())
    }
}
#endif
