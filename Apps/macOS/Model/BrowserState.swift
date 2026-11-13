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
        let profileID: String?
    }

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
    var activeTabID: String? {
        didSet { if oldValue != activeTabID { pagesInViewChanged(from: Self.pagesInView(oldValue, split)) } }
    }
    var split: Split? {
        didSet { if oldValue != split { pagesInViewChanged(from: Self.pagesInView(activeTabID, oldValue)) } }
    }
    var peek: Peek?
    /// A window a page opened as a pop-up, such as a sign-in (`PagePopups`).
    var popup: PagePopup?
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
    /// The space editor sheet: a new space (nil id) or the space with this id.
    var spaceEditor: SpaceEditorRequest?
    var rename: RenameRequest?
    /// The space whose deletion is waiting for confirmation.
    var spaceToDelete: Space?
    /// The unloaded pinned tab a middle-click asked to remove, waiting for confirmation.
    var pinnedTabToRemove: SidebarItem?
    var extensionSheet: ExtensionSheet?
    /// Summarize/Ask or a tidy preview (`MacAISheet`).
    var ai: AIRequest?
    var showImport = false
    var onboarding: OnboardingView.Step?
    private(set) var incognitoTabs: [SidebarItem] = []
    /// The load each tab's page shows as failed. Kept here so ⌘R retries a refused address as Try Again does.
    var loadFailures: [String: LoadFailure] = [:]
    /// The Develop menu's per-tab settings.
    let devTools = DevTools()

    // Touched while views render (page(for:)) or only by actions: not observed.
    @ObservationIgnored let model = MacModel.shared
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private var pages: [String: WebPage] = [:]
    @ObservationIgnored private var enginePages: [String: EnginePage] = [:]
    private let privateEngineProfileID = UUID().uuidString
    #if BOAZ_CHROMIUM
    @ObservationIgnored var createChromiumPage: ((SidebarItem) throws -> EnginePage)?
    @ObservationIgnored var chromiumAddressField: NSTextField?
    #endif
    @ObservationIgnored private var recency: [String] = []
    @ObservationIgnored private var isClosingIdlePages = false
    /// Tabs whose title is cooling down after a save, and whether it changed again meanwhile (`didChangeTitle`).
    @ObservationIgnored private var titleCooldowns: [String: Bool] = [:]
    /// Each tab's address as last saved, which a load in flight hasn't replaced yet.
    @ObservationIgnored private var savedURLs: [String: URL] = [:]
    @ObservationIgnored private var lastTabPerSpace: [String: String] = [:]
    /// The peek's router, which becomes its tab's when the peek is promoted.
    @ObservationIgnored private var peekRouter: (page: ObjectIdentifier, target: NavigationRouter.Target)?
    @ObservationIgnored private let privateStore: WKWebsiteDataStore?
    @ObservationIgnored private var keyObserver: NSObjectProtocol?
    @ObservationIgnored private var closeObserver: NSObjectProtocol?
    @ObservationIgnored private var occlusionObserver: NSObjectProtocol?
    @ObservationIgnored private var windowIsVisible = true
    @ObservationIgnored private var typeAheadMonitor: Any?
    @ObservationIgnored private var sidebarKeyMonitor: Any?
    /// What was typed after the command bar opened but before its field had the keyboard.
    @ObservationIgnored private var typeAhead = ""
    @ObservationIgnored private var typeAheadSubmits = false
    @ObservationIgnored private var typeAheadClears = false
    /// Where each tab's page was last read (`PageState`): the Mac's, or this Incognito window's own, in memory.
    @ObservationIgnored private let pageStates: PageState.Store
    /// States waiting for their tab's page to finish loading (`pageDidFinishLoading`).
    @ObservationIgnored private var pendingRestores: [String: PageState] = [:]
    private let maxLivePages = 10

    init(incognito: Bool) {
        isIncognito = incognito
        privateStore = incognito ? .nonPersistent() : nil
        pageStates = incognito ? PageState.Store() : MacModel.shared.pageStates
    }

    isolated deinit {
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        if let typeAheadMonitor { NSEvent.removeMonitor(typeAheadMonitor) }
        if let sidebarKeyMonitor { NSEvent.removeMonitor(sidebarKeyMonitor) }
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
        Extensions.shared.didOpenWindow(self)
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isIncognito else { return }
                self.model.lastActiveBrowser = self
                Extensions.shared.didFocusWindow(self)
            }
        }
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.windowWillCloseForPictureInPicture()
                self.model.windowWillClose(self)
                Extensions.shared.didCloseWindow(self)
            }
        }
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowVisibilityChanged() }
        }
        model.register(self)
        watchSidebarShortcut()
    }

    /// The sidebar's shortcut, taken before the key reaches the focused view or the menu bar, so it folds the
    /// sidebar wherever the keyboard focus is, a web page included.
    private func watchSidebarShortcut() {
        guard sidebarKeyMonitor == nil else { return }
        sidebarKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated {
                guard let self, let window = self.window, event.window === window, window.attachedSheet == nil,
                      self.model.keyBindings.shortcut(.toggleSidebar)?.matches(event) == true else { return false }
                // Held down, it folds once; the repeats are swallowed so the menu doesn't fold it again.
                if !event.isARepeat { self.toggleSidebar() }
                return true
            }
            return handled ? nil : event
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
    var activePage: WebPage? {
        #if BOAZ_CHROMIUM
        if createChromiumPage != nil { return nil }
        #endif
        return activeTab.map(page(for:))
    }
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
        enginePages[tab.id] = wrapPage(page, profileID: tab.profileID)
        // Unloaded past `maxLivePages`, or after a relaunch: back to where it was.
        if let state = pageStates[tab.id], tab.url?.isSamePage(as: state.url) == true { pendingRestores[tab.id] = state }
        closeIdlePages()
        return page
    }

    /// Over the limit, the least recently used pages close, except those in view and those playing, recording or in
    /// full screen: music in a background tab keeps playing however many tabs open after it.
    private func closeIdlePages() {
        guard pages.count > maxLivePages, !isClosingIdlePages else { return }
        isClosingIdlePages = true
        Task {
            let close = await PageResidency.pagesToClose(recency: recency, pages: pages, limit: maxLivePages,
                                                         keeping: pagesInView)
            for id in close where !pagesInView.contains(id) {
                recency.removeAll { $0 == id }
                pages[id] = nil
                enginePages[id] = nil
                devTools.drop(id)
            }
            isClosingIdlePages = false
        }
    }

    private var pagesInView: Set<String> { Self.pagesInView(activeTabID, split) }
    private static func pagesInView(_ active: String?, _ split: Split?) -> Set<String> {
        Set([split?.leading, split?.trailing, active].compactMap(\.self))
    }

    // MARK: Picture in Picture

    /// A video still playing in a tab the window stops showing floats in Picture in Picture; one Boaz floated returns
    /// to its tab when the tab shows again. Moving between the tabs of a split keeps both in view, so nothing floats.
    private func pagesInViewChanged(from previous: Set<String>) {
        guard windowIsVisible else { return }
        let now = pagesInView
        for id in previous.subtracting(now) { pictureInPicture(id)?.floatOnLeaving() }
        for id in now.subtracting(previous) { pictureInPicture(id)?.returnFromLeaving() }
    }

    /// The window was hidden, minimized or left behind on another desktop, or came back: its videos float or return.
    private func windowVisibilityChanged() {
        guard let window else { return }
        let visible = window.occlusionState.contains(.visible) && !window.isMiniaturized
        guard visible != windowIsVisible else { return }
        windowIsVisible = visible
        for id in pagesInView {
            if visible { pictureInPicture(id)?.returnFromLeaving() } else { pictureInPicture(id)?.floatOnLeaving() }
        }
    }

    /// A closing window's videos go with it: none floats as it orders out.
    private func windowWillCloseForPictureInPicture() {
        windowIsVisible = false
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        for id in pages.keys { pictureInPicture(id)?.detach() }
    }

    private func pictureInPicture(_ tabID: String) -> PictureInPicture? {
        pages[tabID].flatMap(PictureInPicture.controller(of:))
    }

    /// Floats the active tab's video, or brings it back.
    func togglePictureInPicture() {
        activePage.flatMap(PictureInPicture.controller(of:))?.toggle()
    }

    /// The user brought a floating video back from its window: its window and tab come forward.
    private func showTabReturningFromPictureInPicture(_ id: String) {
        guard let tab = tab(id), let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        if !pagesInView.contains(id) { activate(tab) }
    }

    func existingPage(for tabID: String) -> WebPage? { pages[tabID] }

    func enginePage(for tab: SidebarItem) throws -> EnginePage {
        if let engine = enginePages[tab.id] { return engine }
        #if BOAZ_CHROMIUM
        if let createChromiumPage {
            let engine = try createChromiumPage(tab)
            enginePages[tab.id] = engine
            return engine
        }
        #endif
        let page = page(for: tab)
        let engine = wrapPage(page, profileID: tab.profileID)
        enginePages[tab.id] = engine
        return engine
    }

    private func wrapPage(_ page: WebPage, profileID: String?) -> EnginePage {
        let profile = EngineProfileIdentity(id: isIncognito ? privateEngineProfileID : (profileID ?? "default"),
                                            isPrivate: isIncognito)
        return EnginePage(adapter: WebKitEnginePageAdapter(page: page, profile: profile))
    }

    private func navigateEngine(_ operation: (EnginePage) throws -> Void) {
        guard let tab = activeTab else { return }
        do { try operation(try enginePage(for: tab)) }
        catch { model.showToast(error.localizedDescription) }
    }

    func makePage(profileID: String?, context: NavigationRouter.Context, loading url: URL? = nil) -> WebPage {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = dataStore(profileID: profileID)
        if !isIncognito { configuration.webExtensionController = Extensions.shared.controller(profileID: profileID) }
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        model.applyContentBlocking(to: &configuration)
        if case .tab(let id) = context {
            PageState.install(in: &configuration) { [weak self] state in self?.pageDidSettle(state, tabID: id) }
            PasswordAutofill.shared.install(in: &configuration, tabID: id, offersToSave: !isIncognito)
        }
        let pictureInPicture = PictureInPicture.install(in: &configuration)
        let router = NavigationRouter(browser: self, context: context)
        let page = WebPage(configuration: configuration, navigationDecider: router, dialogPresenter: MacDialogs())
        if case .peek = context { peekRouter = (ObjectIdentifier(page), router.target) }
        pictureInPicture.attach(page)
        if case .tab(let id) = context {
            pictureInPicture.onRestore = { [weak self] in self?.showTabReturningFromPictureInPicture(id) }
        }
        // Inspect Element in the page's context menu, and Safari's Develop menu for the page.
        page.isInspectable = true
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
        pictureInPicture(tabID)?.detach()
        pages[tabID] = nil
        enginePages[tabID] = nil
        loadFailures[tabID] = nil
        devTools.drop(tabID)
        savedURLs[tabID] = nil
        recency.removeAll { $0 == tabID }
    }

    /// Unloads every page whose tab is gone from the library.
    func unloadPagesWithoutTabs() {
        pages.keys.filter { tab($0) == nil }.forEach(unload)
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
            if downloadRequested { model.showToast("Boaz can't download this link") }
            return downloadRequested ? .cancel : .allow
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

    // MARK: Tabs

    func activate(_ tab: SidebarItem) {
        guard tab.kind == .tab else { return }
        commandMode = nil
        if let split, !split.contains(tab.id) { self.split = nil }
        if let space = tab.spaceID, space != spaceID { switchSpace(to: space, restoringTab: false) }
        if !isPrivate(tab) { model.markActive(tab) }
        let previous = activeTabID
        activeTabID = tab.id
        if let spaceID { lastTabPerSpace[spaceID] = tab.id }
        if previous != tab.id { Extensions.shared.didActivate(tab, previous: previous, in: self) }
    }

    /// A new Today tab, at the top or right below `source`. One opened in the background starts loading without
    /// taking the window.
    func openTab(_ url: URL, title: String? = nil, below source: SidebarItem? = nil, inBackground: Bool = false) {
        let tab: SidebarItem
        if isIncognito {
            let index = source.flatMap { source in incognitoTabs.firstIndex { $0.id == source.id } }.map { $0 + 1 } ?? 0
            let above = index > 0 ? incognitoTabs[index - 1].position : nil
            let below = index < incognitoTabs.count ? incognitoTabs[index].position : nil
            let position = switch (above, below) {
            case let (above?, below?): (above + below) / 2
            case let (above?, nil): above + 1
            default: (below ?? 1) - 1
            }
            tab = SidebarItem(id: UUID().uuidString, spaceID: nil, profileID: "incognito", parentID: nil,
                              kind: .tab, title: title ?? url.host(), url: url, position: position, lastActiveAt: .now)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { incognitoTabs.insert(tab, at: index) }
        } else {
            guard let new = withAnimation(.spring(response: 0.35, dampingFraction: 0.8), {
                model.newTab(url, title: title, in: spaceID, below: source)
            }) else { return }
            tab = new
        }
        if inBackground {
            do { _ = try enginePage(for: tab) }
            catch { model.showToast(error.localizedDescription) }
        } else { activate(tab) }
    }

    func load(_ url: URL) {
        guard let tab = activeTab else { openTab(url); return }
        do { try enginePage(for: tab).navigate(to: url) }
        catch { model.showToast(error.localizedDescription) }
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

    /// Puts a page loaded again back where it was, and learns its favicon (skipped for incognito) once it finishes
    /// loading.
    func pageDidFinishLoading(page: WebPage) {
        guard !page.isLoading else { return }
        if let id = pages.first(where: { $0.value === page })?.key, let state = pendingRestores.removeValue(forKey: id),
           page.url?.isSamePage(as: state.url) == true {
            Task { await state.restore(on: page) }
        }
        guard !isIncognito, let pageURL = page.url else { return }
        Task {
            guard let href = try? await page.callJavaScript(Favicons.discoveryScript, contentWorld: .defaultClient) as? String,
                  let iconURL = URL(string: href, relativeTo: pageURL)?.absoluteURL else { return }
            Favicons.shared.learn(iconURL: iconURL, forPageAt: pageURL, isPrivate: false)
        }
    }

    /// The page's process ended: the reload that follows goes back to where the page was. The page has no address
    /// until then; the tab's is the one it showed.
    func pageDidTerminate(_ tabID: String) {
        guard let state = pageStates[tabID], let url = pages[tabID]?.url ?? tab(tabID)?.url,
              url.isSamePage(as: state.url) else { return }
        pendingRestores[tabID] = state
    }

    /// Where the page's scrolling came to rest (the page's script reports it). Not while the page waits to be put
    /// back (until then it sits at the top), nor once it has left view: off screen it is laid out at another size,
    /// which moves a page scrolled to its end. One that finished loading while no pane watched it isn't put back.
    private func pageDidSettle(_ state: PageState, tabID: String) {
        if pendingRestores[tabID] != nil {
            guard pages[tabID]?.isLoading == false else { return }
            pendingRestores[tabID] = nil
        }
        guard pagesInView.contains(tabID), tab(tabID) != nil else { return }
        pageStates.set(state, for: tabID)
    }

    /// Reads and keeps where a page in view is, as Boaz goes to the background. A page only scrolls in view, so its last
    /// report there already says where it is.
    private func rememberPageState(_ tabID: String) async {
        guard pendingRestores[tabID] == nil, pagesInView.contains(tabID), let page = pages[tabID], !page.isLoading,
              let state = await PageState.read(page), pendingRestores[tabID] == nil, tab(tabID) != nil else { return }
        pageStates.set(state, for: tabID)
    }

    /// Boaz is going to the background.
    func rememberPagesInView() {
        for id in pagesInView { Task { await rememberPageState(id) } }
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
        // A closed tab opens fresh, a pinned one at its pinned page's top.
        pageStates.remove(tab.id)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            if isPrivate(tab) {
                incognitoTabs.removeAll { $0.id == tab.id }
            } else if !model.isPinned(tab) {
                model.archive(tab)
            }
        }
    }

    /// A middle-click on a sidebar tab closes it as its row's button does, except that a pinned tab with nothing
    /// loaded leaves Pinned for the Archive, after a warning the user can turn off.
    func middleClick(_ tab: SidebarItem) {
        guard model.isPinned(tab), pages[tab.id] == nil else { close(tab); return }
        if Preferences.skipsPinnedRemovalWarning { removePinned(tab) } else { pinnedTabToRemove = tab }
    }

    func removePinned(_ tab: SidebarItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.archive(tab) }
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

    /// ⌘⇧R: forgets the site's cookies and stored data in the tab's profile, then reloads from the server. Only that
    /// site goes: WebKit keeps website data by registrable domain, so `www.example.com` clears `example.com`'s.
    func hardReload() {
        guard let tab = activeTab, let page = activePage else { return }
        let tabURL = loadFailures[tab.id]?.url ?? tab.url
        let host = activeURL?.host()?.lowercased()
        let store = dataStore(profileID: tab.profileID)
        Task {
            if let host {
                let types = WKWebsiteDataStore.allWebsiteDataTypes()
                let site = await store.dataRecords(ofTypes: types).filter {
                    let domain = $0.displayName.lowercased()
                    return host == domain || host.hasSuffix("." + domain)
                }
                if !site.isEmpty { await store.removeData(ofTypes: types, for: site) }
            }
            page.reload(tabURL: tabURL, fromOrigin: true)
        }
    }

    func goBack() {
        navigateEngine { try $0.goBack() }
    }

    func goForward() {
        navigateEngine { try $0.goForward() }
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
        let profileID = profileID ?? currentSpace?.profileID
        let page = makePage(profileID: profileID, context: .peek, loading: url)
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) { peek = Peek(page: page, profileID: profileID) }
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
                enginePages[tab.id] = wrapPage(peek.page, profileID: peek.profileID)
                recency.append(tab.id)
                if let peekRouter, peekRouter.page == ObjectIdentifier(peek.page) { peekRouter.target.context = .tab(tab.id) }
                PictureInPicture.controller(of: peek.page)?.onRestore = { [weak browser = self] in
                    browser?.showTabReturningFromPictureInPicture(tab.id)
                }
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
