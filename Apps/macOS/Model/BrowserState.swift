import AppKit
import FolioKit
import SwiftUI
import WebKit

/// One browser window: which space and tab it shows, its live web pages, split view, peek and command bar.
@Observable
final class BrowserState {
    enum CommandMode: Equatable { case newTab, currentTab, split }

    struct Split: Equatable {
        var leading: String
        var trailing: String
        var fraction: CGFloat = 0.5
        func contains(_ id: String?) -> Bool { id == leading || id == trailing }
    }

    struct Peek: Identifiable {
        let id = UUID()
        let page: WebPage
    }

    struct SpaceRef: Identifiable { let id: String }
    struct SpaceEditorRequest: Identifiable {
        let id = UUID()
        var spaceID: String?
    }
    struct RenameRequest: Identifiable {
        enum Target { case item(SidebarItem), space(Space) }
        let id = UUID()
        let target: Target
        var text: String
    }

    let isIncognito: Bool
    var currentSpaceID: String?
    /// Direction the space column slides in from on the next switch.
    var spaceEdge: Edge = .trailing
    var activeTabID: String?
    var split: Split?
    var peek: Peek?
    var commandMode: CommandMode?
    var sidebarVisible = true { didSet { updateTrafficLights() } }
    var sidebarPeeking = false { didSet { updateTrafficLights() } }
    var findVisible = false
    var themeEditor: SpaceRef?
    /// The space editor sheet: a new space (nil id) or the space with this id.
    var spaceEditor: SpaceEditorRequest?
    var rename: RenameRequest?
    var showImport = false
    var onboarding: OnboardingView.Step?
    private(set) var incognitoTabs: [SidebarItem] = []
    /// Each tab's site color, which the window takes on. Never sampled in incognito.
    private(set) var siteColors: [String: SiteColor] = [:]

    // Touched while views render (page(for:)) or only by actions: not observed.
    @ObservationIgnored let model = MacModel.shared
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private var pages: [String: WebPage] = [:]
    @ObservationIgnored private var recency: [String] = []
    @ObservationIgnored private var lastTabPerSpace: [String: String] = [:]
    @ObservationIgnored private let privateStore: WKWebsiteDataStore?
    @ObservationIgnored private var keyObserver: NSObjectProtocol?
    private let maxLivePages = 10

    init(incognito: Bool) {
        isIncognito = incognito
        privateStore = incognito ? .nonPersistent() : nil
    }

    // MARK: Window

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isOpaque = false
        window.backgroundColor = .clear
        window.tabbingMode = .disallowed
        updateTrafficLights()
        if !isIncognito { model.lastActiveBrowser = self }
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isIncognito else { return }
                self.model.lastActiveBrowser = self
            }
        }
    }

    /// Arc hides the traffic lights with the sidebar; they come back while the sidebar peeks.
    private func updateTrafficLights() {
        let hidden = !(sidebarVisible || sidebarPeeking)
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window?.standardWindowButton(kind)?.isHidden = hidden
        }
    }

    func toggleSidebar() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            sidebarVisible.toggle()
            sidebarPeeking = false
        }
    }

    // MARK: Reads

    var spaceID: String? { model.space(currentSpaceID)?.id ?? model.sidebar.spaces.first?.id }
    var currentSpace: Space? { model.space(spaceID) }

    func tab(_ id: String?) -> SidebarItem? {
        guard let id else { return nil }
        return incognitoTabs.first { $0.id == id } ?? model.item(id)
    }

    var activeTab: SidebarItem? { tab(activeTabID) }
    var activePage: WebPage? { activeTab.map(page(for:)) }

    func isPrivate(_ tab: SidebarItem) -> Bool { isIncognito && incognitoTabs.contains { $0.id == tab.id } }

    /// Tabs the window cycles through with ⌃Tab.
    var cycleTabs: [SidebarItem] {
        if isIncognito { return incognitoTabs }
        return currentSpace.map(model.visibleTabs(in:)) ?? []
    }

    // MARK: Pages

    func page(for tab: SidebarItem) -> WebPage {
        recency.removeAll { $0 == tab.id }
        recency.append(tab.id)
        if let page = pages[tab.id] { return page }
        let page = makePage(profileID: tab.profileID, context: .tab(tab.id))
        if let url = tab.url { page.load(URLRequest(url: url)) }
        pages[tab.id] = page
        let pinnedIDs = [split?.leading, split?.trailing, activeTabID]
        while pages.count > maxLivePages, let victim = recency.first(where: { !pinnedIDs.contains($0) }) {
            recency.removeAll { $0 == victim }
            pages[victim] = nil
        }
        return page
    }

    func makePage(profileID: String?, context: NavigationRouter.Context) -> WebPage {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore(profileID: profileID)
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        model.applyContentBlocking(to: &configuration)
        let page = WebPage(configuration: configuration, navigationDecider: NavigationRouter(browser: self, context: context),
                           dialogPresenter: MacDialogs())
        page.isInspectable = true
        return page
    }

    func dataStore(profileID: String?) -> WKWebsiteDataStore {
        privateStore ?? profileID.map(model.dataStore(for:)) ?? .default()
    }

    /// Saves `url` to ~/Downloads using the cookies of the page it came from.
    func download(_ url: URL, context: NavigationRouter.Context) {
        let profileID: String? = switch context {
        case .tab(let id): tab(id)?.profileID
        case .peek: currentSpace?.profileID
        }
        PageDownloads.start(url, store: dataStore(profileID: profileID))
    }

    func unload(_ tabID: String) {
        pages[tabID] = nil
        recency.removeAll { $0 == tabID }
    }

    /// Whether a pinned tab's page has browsed away from where it was pinned.
    func hasWandered(_ tab: SidebarItem) -> Bool {
        guard model.isPinned(tab), let page = pages[tab.id] else { return false }
        return PinnedAnchor.hasWandered(page, from: tab.url)
    }

    func returnToPinnedPage(_ tab: SidebarItem) {
        guard let url = tab.url else { return }
        activate(tab)
        page(for: tab).load(URLRequest(url: url))
    }

    /// Pins or unpins; unpinning keeps the tab where its page is now, not where it was pinned.
    func togglePin(_ tab: SidebarItem) {
        let unpinning = model.isPinned(tab) && !model.isFavorite(tab)
        model.togglePin(tab)
        if unpinning, let page = pages[tab.id] { model.didNavigate(tab.id, url: page.url, title: page.title) }
    }

    /// Link routing, Arc-style: ⌘-click peeks, ⌘⇧-click opens a tab; pages that open new windows get a peek
    /// when they're pinned (keeps the pinned app in place) and a new Today tab otherwise.
    func decide(_ action: WebPage.NavigationAction, context: NavigationRouter.Context) -> WKNavigationActionPolicy {
        guard let url = action.request.url, url.scheme?.hasPrefix("http") == true else { return .allow }
        if action.shouldPerformDownload { download(url, context: context); return .cancel }
        let flags = NSEvent.modifierFlags
        let opensWindow = action.target == nil
        let mainFrameLink = action.navigationType == .linkActivated && (action.target?.isMainFrame ?? true)
        switch context {
        case .peek:
            if opensWindow || (mainFrameLink && flags.contains(.command)) { openTab(url); return .cancel }
            return .allow
        case .tab(let id):
            if mainFrameLink && flags.contains(.command) {
                if flags.contains(.shift) { openTab(url) } else { openPeek(url, profileID: tab(id)?.profileID) }
                return .cancel
            }
            if opensWindow {
                if let tab = tab(id), model.isPinned(tab) { openPeek(url, profileID: tab.profileID) } else { openTab(url) }
                return .cancel
            }
            return .allow
        }
    }

    // MARK: Tabs

    func activate(_ tab: SidebarItem) {
        guard tab.kind == .tab else { return }
        commandMode = nil
        if let split, !split.contains(tab.id) { self.split = nil }
        if let space = tab.spaceID, space != spaceID { switchSpace(to: space, restoringTab: false) }
        if !isPrivate(tab) { model.markActive(tab) }
        activeTabID = tab.id
        if let spaceID { lastTabPerSpace[spaceID] = tab.id }
    }

    func openTab(_ url: URL, title: String? = nil) {
        if isIncognito {
            let tab = SidebarItem(id: UUID().uuidString, spaceID: nil, profileID: "incognito", parentID: nil,
                                  kind: .tab, title: title ?? url.host(), url: url,
                                  position: (incognitoTabs.map(\.position).min() ?? 1) - 1, lastActiveAt: .now)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { incognitoTabs.insert(tab, at: 0) }
            activate(tab)
            return
        }
        guard let tab = withAnimation(.spring(response: 0.35, dampingFraction: 0.8), {
            model.newTab(url, title: title, in: spaceID)
        }) else { return }
        activate(tab)
    }

    func load(_ url: URL) {
        guard let tab = activeTab else { openTab(url); return }
        page(for: tab).load(URLRequest(url: url))
    }

    func didNavigate(_ tabID: String, url: URL?, title: String) {
        if let index = incognitoTabs.firstIndex(where: { $0.id == tabID }) {
            if let url { incognitoTabs[index].url = url }
            if !title.isEmpty { incognitoTabs[index].title = title }
            return
        }
        model.didNavigate(tabID, url: url, title: title)
    }

    /// Samples the tab's site color once its page has loaded; while it loads, uses the color last seen for the host.
    func updateSiteColor(_ tabID: String, page: WebPage) {
        guard !isIncognito else { return }
        if page.isLoading {
            if let cached = SiteColor.cached(for: page.url), siteColors[tabID] != cached { siteColors[tabID] = cached }
            return
        }
        Task { [weak self] in
            let color = await SiteColor.sample(page)
            if let self, self.siteColors[tabID] != color { self.siteColors[tabID] = color }
        }
    }

    /// The active tab's site color, when tinting is on.
    func activeSiteColor(enabled: Bool) -> SiteColor? {
        guard enabled, !isIncognito, let id = activeTab?.id else { return nil }
        return siteColors[id]
    }

    /// Learns the page's favicon once it finishes loading (skipped for incognito, matching `updateSiteColor`).
    func pageDidFinishLoading(page: WebPage) {
        guard !page.isLoading, !isIncognito, let pageURL = page.url else { return }
        Task {
            guard let href = try? await page.callJavaScript(Favicons.discoveryScript, contentWorld: .defaultClient) as? String,
                  let iconURL = URL(string: href, relativeTo: pageURL)?.absoluteURL else { return }
            Favicons.shared.learn(iconURL: iconURL, forPageAt: pageURL, isPrivate: false)
        }
    }

    /// ⌘W: archives a Today tab; a pinned or favorite tab just unloads (it stays in the sidebar).
    func closeActive() {
        guard let tab = activeTab else { window?.performClose(nil); return }
        close(tab)
    }

    func close(_ tab: SidebarItem) {
        let next = neighbor(of: tab)
        if let split, split.contains(tab.id) {
            self.split = nil
            activeTabID = split.leading == tab.id ? split.trailing : split.leading
        } else if activeTabID == tab.id {
            activeTabID = next?.id
        }
        unload(tab.id)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if isPrivate(tab) {
                incognitoTabs.removeAll { $0.id == tab.id }
            } else if !model.isPinned(tab) {
                model.archive(tab)
            }
        }
    }

    func reopenClosedTab() {
        guard !isIncognito, let tab = withAnimation(.spring(response: 0.35, dampingFraction: 0.8), {
            model.reopenClosedTab()
        }) else { return }
        activate(tab)
    }

    func togglePinActive() {
        guard let tab = activeTab, !isPrivate(tab) else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { togglePin(tab) }
    }

    func copyActiveURL() {
        guard let url = activePage?.url ?? activeTab?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        model.showToast("Copied URL")
    }

    func reload() { _ = activePage?.reload() }

    func goBack() {
        guard let page = activePage, let item = page.backForwardList.backList.last else { return }
        page.load(item)
    }

    func goForward() {
        guard let page = activePage, let item = page.backForwardList.forwardList.first else { return }
        page.load(item)
    }

    func zoom(_ change: PageZoom.Change) {
        guard let page = activePage else { return }
        PageZoom.change(change, for: page, remember: !isIncognito)
    }

    /// Prints the active page through a PDF of it, split across sheets at the paper's width.
    func printActive() {
        guard let page = activePage else { return }
        Task {
            guard let data = try? await page.exported(as: .pdf()), let image = NSImage(data: data) else {
                model.showToast("Couldn't print this page")
                return
            }
            let view = NSImageView(frame: NSRect(origin: .zero, size: image.size))
            view.image = image
            view.imageScaling = .scaleProportionallyUpOrDown
            let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
            info.horizontalPagination = .fit
            info.verticalPagination = .automatic
            let operation = NSPrintOperation(view: view, printInfo: info)
            operation.jobTitle = page.title.isEmpty ? (page.url?.host() ?? "Folio") : page.title
            if let window { operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil) } else { operation.run() }
        }
    }

    func cycleTab(by offset: Int) {
        let tabs = cycleTabs
        guard !tabs.isEmpty else { return }
        let index = tabs.firstIndex { $0.id == activeTabID } ?? (offset > 0 ? -1 : 0)
        activate(tabs[(index + offset + tabs.count) % tabs.count])
    }

    func selectFavorite(_ number: Int) {
        let favorites = model.favorites(profileID: currentSpace?.profileID)
        guard favorites.indices.contains(number - 1) else { return }
        activate(favorites[number - 1])
    }

    private func neighbor(of tab: SidebarItem) -> SidebarItem? {
        let siblings = isPrivate(tab) ? incognitoTabs
            : model.sidebar.children(of: tab.parentID ?? "").filter { $0.kind == .tab }
        guard let index = siblings.firstIndex(where: { $0.id == tab.id }) else { return nil }
        return siblings.indices.contains(index + 1) ? siblings[index + 1]
            : siblings.indices.contains(index - 1) ? siblings[index - 1] : nil
    }

    // MARK: Spaces

    func switchSpace(to id: String, restoringTab: Bool = true) {
        guard id != spaceID, !isIncognito else { return }
        let spaces = model.sidebar.spaces
        let from = spaces.firstIndex { $0.id == spaceID } ?? 0
        let to = spaces.firstIndex { $0.id == id } ?? 0
        if let spaceID, let activeTabID { lastTabPerSpace[spaceID] = activeTabID }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
            spaceEdge = to >= from ? .trailing : .leading
            currentSpaceID = id
            guard restoringTab else { return }
            split = nil
            let remembered = lastTabPerSpace[id].flatMap(tab)
            if let active = activeTab, model.isFavorite(active) { return }
            activeTabID = remembered?.id
        }
    }

    func shiftSpace(by offset: Int) {
        let spaces = model.sidebar.spaces
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }),
              spaces.indices.contains(index + offset) else { return }
        switchSpace(to: spaces[index + offset].id)
    }

    func selectSpace(_ number: Int) {
        let spaces = model.sidebar.spaces
        guard spaces.indices.contains(number - 1) else { return }
        switchSpace(to: spaces[number - 1].id)
    }

    /// Opens the space editor to name, icon and color the new space before it's created.
    func newSpace() { spaceEditor = SpaceEditorRequest(spaceID: nil) }

    // MARK: Split view & peek

    func toggleSplit() {
        if split != nil {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { split = nil }
        } else if activeTab != nil {
            commandMode = .split
        }
    }

    func openInSplit(_ tab: SidebarItem) {
        commandMode = nil
        guard let active = activeTab, active.id != tab.id else { activate(tab); return }
        if !isPrivate(tab) { model.markActive(tab) }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            split = Split(leading: active.id, trailing: tab.id)
            activeTabID = tab.id
        }
    }

    func openInSplit(_ url: URL) {
        guard let active = activeTab else { openTab(url); return }
        openTab(url)
        guard let new = activeTab, new.id != active.id else { return }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.85)) {
            split = Split(leading: active.id, trailing: new.id)
        }
    }

    func focusPane(_ id: String) {
        guard activeTabID != id else { return }
        activeTabID = id
    }

    func openPeek(_ url: URL, profileID: String?) {
        let page = makePage(profileID: profileID ?? currentSpace?.profileID, context: .peek)
        page.load(URLRequest(url: url))
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { peek = Peek(page: page) }
    }

    func closePeek() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { peek = nil }
    }

    /// Keeps the peeked page alive and turns it into a Today tab. The peek's WebView has to be gone before a
    /// tab's WebView can host the same page, so the overlay closes without animation first.
    func promotePeek() {
        guard let peek, let url = peek.page.url else { closePeek(); return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { self.peek = nil }
        Task {
            try? await Task.sleep(for: .milliseconds(60))
            if isIncognito {
                openTab(url, title: peek.page.title)
            } else if let tab = withAnimation(.spring(response: 0.4, dampingFraction: 0.85), {
                model.newTab(url, title: peek.page.title, in: spaceID)
            }) {
                pages[tab.id] = peek.page
                recency.append(tab.id)
                activate(tab)
            }
        }
    }

    // MARK: External

    func consumePendingURL() {
        guard !isIncognito else { return }
        if let id = model.pendingMainTabID {
            model.pendingMainTabID = nil
            if let tab = tab(id) { activate(tab) }
        }
        guard let url = model.pendingMainURL else { return }
        model.pendingMainURL = nil
        openTab(url)
    }
}

/// Bridges WebPage's navigation decisions back to the window that owns the page.
struct NavigationRouter: WebPage.NavigationDeciding {
    enum Context { case tab(String), peek }

    weak var browser: BrowserState?
    let context: Context

    func decidePolicy(for action: WebPage.NavigationAction,
                      preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        browser?.decide(action, context: context) ?? .allow
    }

    func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
        guard PageDownloads.shouldDownload(response), let url = response.response.url else { return .allow }
        browser?.download(url, context: context)
        return .cancel
    }
}
