import AppKit
import BoazKit
import Carbon
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
    var commandMode: CommandMode? {
        didSet {
            if commandMode == nil { endTypeAhead() } else if oldValue == nil { beginTypeAhead() }
        }
    }
    /// Changes each time the command bar opens, so a bar reopened during its closing animation starts empty.
    private(set) var commandSession = UUID()
    var sidebarVisible = true { didSet { updateTrafficLights() } }
    var sidebarPeeking = false { didSet { updateTrafficLights() } }
    var findVisible = false
    var themeEditor: SpaceRef?
    /// The space editor sheet: a new space (nil id) or the space with this id.
    var spaceEditor: SpaceEditorRequest?
    var rename: RenameRequest?
    /// Summarize/Ask or a tidy preview (`MacAISheet`).
    var ai: AIRequest?
    var showImport = false
    var onboarding: OnboardingView.Step?
    private(set) var incognitoTabs: [SidebarItem] = []
    /// The load each tab's page shows as failed. Kept here so ⌘R retries a refused address as Try Again does.
    var loadFailures: [String: LoadFailure] = [:]
    /// Each tab's site color, which the window takes on. Never sampled in incognito.
    private(set) var siteColors: [String: SiteColor] = [:]

    // Touched while views render (page(for:)) or only by actions: not observed.
    @ObservationIgnored let model = MacModel.shared
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private var pages: [String: WebPage] = [:]
    @ObservationIgnored private var recency: [String] = []
    /// Tabs whose title is cooling down after a save, and whether it changed again meanwhile (`didChangeTitle`).
    @ObservationIgnored private var titleCooldowns: [String: Bool] = [:]
    /// Each tab's address as last saved, which a load in flight hasn't replaced yet.
    @ObservationIgnored private var savedURLs: [String: URL] = [:]
    @ObservationIgnored private var lastTabPerSpace: [String: String] = [:]
    @ObservationIgnored private let privateStore: WKWebsiteDataStore?
    @ObservationIgnored private var keyObserver: NSObjectProtocol?
    @ObservationIgnored private var closeObserver: NSObjectProtocol?
    @ObservationIgnored private var typeAheadMonitor: Any?
    /// What was typed after the command bar opened but before its field had the keyboard.
    @ObservationIgnored private var typeAhead = ""
    @ObservationIgnored private var typeAheadSubmits = false
    @ObservationIgnored private var typeAheadClears = false
    private let maxLivePages = 10

    init(incognito: Bool) {
        isIncognito = incognito
        privateStore = incognito ? .nonPersistent() : nil
    }

    isolated deinit {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        if let typeAheadMonitor { NSEvent.removeMonitor(typeAheadMonitor) }
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
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isIncognito else { return }
                self.model.lastActiveBrowser = self
            }
        }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.model.windowWillClose(self)
            }
        }
        model.register(self)
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
    /// The address that failed while the tab shows why; otherwise the page's address, or the tab's while the page has
    /// none of its own.
    var activeURL: URL? {
        if let failed = activeFailure?.url { return failed }
        return activePage?.url.flatMap { $0.absoluteString == "about:blank" ? nil : $0 } ?? activeTab?.url
    }

    var activeFailure: LoadFailure? { activeTabID.flatMap { loadFailures[$0] } }

    /// Only a page that loaded over HTTPS: a failed load has no certificate to vouch for, and the previous page's
    /// certificate isn't this address's.
    var activeIsSecure: Bool {
        activeFailure == nil && activeURL?.scheme == "https" && activePage?.serverTrust != nil
    }

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
        if loadFailures[tab.id] != nil { loadFailures[tab.id] = nil }
        let page = makePage(profileID: tab.profileID, context: .tab(tab.id), loading: tab.url)
        pages[tab.id] = page
        let pinnedIDs = [split?.leading, split?.trailing, activeTabID]
        while pages.count > maxLivePages, let victim = recency.first(where: { !pinnedIDs.contains($0) }) {
            recency.removeAll { $0 == victim }
            pages[victim] = nil
        }
        return page
    }

    func makePage(profileID: String?, context: NavigationRouter.Context, loading url: URL? = nil) -> WebPage {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore(profileID: profileID)
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        model.applyContentBlocking(to: &configuration)
        let page = WebPage(configuration: configuration, navigationDecider: NavigationRouter(browser: self, context: context),
                           dialogPresenter: MacDialogs())
        #if DEBUG
        page.isInspectable = true
        #endif
        if let url {
            // A tab's first load starts before its pane watches the page, so its failure is caught here.
            model.load(url, in: page, configuration: configuration) { [weak self, weak page] failure in
                if case .tab(let id) = context, let page, self?.pages[id] === page { self?.loadFailures[id] = failure }
            }
        }
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
        loadFailures[tabID] = nil
        savedURLs[tabID] = nil
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

    /// Link routing: ⌘-click peeks, ⌘⇧-click opens a tab; pages that open new windows get a peek
    /// when they're pinned (keeps the pinned app in place) and a new Today tab otherwise.
    func decide(_ action: WebPage.NavigationAction, context: NavigationRouter.Context) -> WKNavigationActionPolicy {
        let opensWindow = action.target == nil
        let downloadRequested = opensWindow && LinkDownloadMenu.takeRequest()
        guard let url = action.request.url, url.scheme?.hasPrefix("http") == true else {
            if downloadRequested { model.showToast("Boaz can't download this link") }
            return downloadRequested ? .cancel : .allow
        }
        if action.shouldPerformDownload || downloadRequested {
            download(url, context: context)
            return .cancel
        }
        let flags = NSEvent.modifierFlags
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
            if let url, url.absoluteString != "about:blank" { incognitoTabs[index].url = url }
            if !title.isEmpty { incognitoTabs[index].title = title }
            return
        }
        model.didNavigate(tabID, url: url, title: title)
    }

    /// A tab's page committed a new load, which its history visit is recorded for. Private tabs leave none.
    func didCommitLoad(_ tabID: String) {
        guard !incognitoTabs.contains(where: { $0.id == tabID }), let page = pages[tabID] else { return }
        model.didCommitLoad(tabID, url: page.url)
    }

    /// Pages that animate their title (unread counts, timers) would otherwise save, sync and refetch the whole
    /// sidebar on every tick. A title change is saved at once, then at most every two seconds with the latest title.
    /// A new page gets its title saved at once, not after the previous page's cooldown.
    /// While a load is in flight the page reports the address it's trying, which may never load: that address is
    /// saved once the load commits (`committed`), so a failed load leaves no visit under the previous page's title.
    func didChangeURL(_ tabID: String, committed: Bool = false) {
        guard let page = pages[tabID], committed || !page.isLoading else { return }
        titleCooldowns[tabID] = nil
        savedURLs[tabID] = page.url
        if !committed, !incognitoTabs.contains(where: { $0.id == tabID }) {
            model.didChangeAddress(tabID, url: page.url, title: page.title)
        }
        didNavigate(tabID, url: page.url, title: page.title)
    }

    func didChangeTitle(_ tabID: String) {
        guard titleCooldowns[tabID] == nil else { titleCooldowns[tabID] = true; return }
        // The old page's title ticking while another address loads isn't that address's title.
        guard let page = pages[tabID], !page.isLoading || page.url == savedURLs[tabID] else { return }
        didNavigate(tabID, url: page.url, title: page.title)
        titleCooldowns[tabID] = false
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            if self?.titleCooldowns.removeValue(forKey: tabID) == true { self?.didChangeTitle(tabID) }
        }
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
        siteColors[tab.id] = nil
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
        guard let url = activeURL else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        model.showToast("Copied URL")
    }

    func reload() {
        activePage?.reload(tabURL: activeTabID.flatMap { loadFailures[$0]?.url } ?? activeTab?.url)
    }

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
        PageZoom.change(change, for: page, isPrivate: isIncognito)
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
            operation.jobTitle = page.title.isEmpty ? (page.url?.host() ?? "Boaz") : page.title
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
            : model.sidebar.children(of: tab.parentID ?? "").filter {
                // Another device's Today tabs aren't in this Mac's sidebar.
                $0.kind == .tab && ($0.deviceID == nil || $0.deviceID == model.deviceID)
            }
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
            activeTabID = tabToShow(in: id)?.id
        }
    }

    /// The tab a switch to space `id` shows: a favorite already open that the space shares (same profile) stays;
    /// otherwise the tab last used there, else its most recently used one. Nil shows the empty New Tab page.
    private func tabToShow(in id: String) -> SidebarItem? {
        guard let space = model.space(id) else { return nil }
        let belongs = { (tab: SidebarItem) in
            tab.spaceID == id || (self.model.isFavorite(tab) && tab.profileID == space.profileID)
        }
        if let active = activeTab, model.isFavorite(active), belongs(active) { return active }
        if let remembered = lastTabPerSpace[id].flatMap(tab), belongs(remembered) { return remembered }
        return model.visibleTabs(in: space).filter { $0.spaceID == id }
            .max { ($0.lastActiveAt ?? .distantPast) < ($1.lastActiveAt ?? .distantPast) }
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

    // MARK: Command bar

    /// Keys typed right after ⌘T or ⌘L can arrive before the field has the keyboard, and would reach the page.
    /// Until the bar takes them (`endTypeAhead`), plain typing is held here.
    private func beginTypeAhead() {
        commandSession = UUID()
        endTypeAhead()
        typeAheadMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = event
            let held = MainActor.assumeIsolated { self?.holdTypeAhead(event) ?? false }
            return held ? nil : event
        }
    }

    private func holdTypeAhead(_ event: NSEvent) -> Bool {
        // An input method (Japanese, Chinese, Korean) composes the keys itself, so they aren't held.
        guard event.window === window, event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
              !Self.usesInputMethod else { return false }
        // Nothing typed after Return belongs to what it submits; held, so it doesn't reach the page either.
        if typeAheadSubmits { return true }
        switch event.keyCode {
        case 51: // Delete
            if typeAhead.isEmpty { typeAheadClears = true } else { typeAhead.removeLast() }
            return true
        case 36, 76: // Return, Enter
            typeAheadSubmits = true
            return true
        default:
            // Printable text only: Escape, Tab and the arrow and function keys keep their meaning.
            guard let text = event.characters, !text.isEmpty, text.unicodeScalars.allSatisfy({
                !CharacterSet.controlCharacters.contains($0) && !(0xF700...0xF8FF).contains($0.value)
            }) else { return false }
            typeAhead += text
            return true
        }
    }

    private static var usesInputMethod: Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let type = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else { return false }
        return Unmanaged<CFString>.fromOpaque(type).takeUnretainedValue() != kTISTypeKeyboardLayout
    }

    /// Stops holding keys and returns what was typed meanwhile, whether Delete was pressed with nothing typed, and
    /// whether Return followed.
    @discardableResult
    func endTypeAhead() -> (text: String, clear: Bool, submit: Bool) {
        if let typeAheadMonitor { NSEvent.removeMonitor(typeAheadMonitor) }
        typeAheadMonitor = nil
        defer { typeAhead = ""; typeAheadClears = false; typeAheadSubmits = false }
        return (typeAhead, typeAheadClears, typeAheadSubmits)
    }

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
        let page = makePage(profileID: profileID ?? currentSpace?.profileID, context: .peek, loading: url)
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
