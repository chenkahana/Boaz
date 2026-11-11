import BoazKit
import OSLog
import SwiftUI
import WebKit

/// App state for every posture. The sidebar comes from the shared store; web pages live here.
@Observable
final class AppModel {
    enum SearchTarget { case newTab, currentTab }
    enum Sheet: String, Identifiable { case library, settings; var id: String { rawValue } }
    struct Toast: Equatable { var message: String; var canUndo: Bool }

    /// Private tabs hang off this pseudo-parent and never reach the store, history or sync.
    static let incognitoParent = "incognito"

    var sidebar = Sidebar()
    /// Counts snapshots from the live observation (see `reloadSidebar`).
    @ObservationIgnored private var sidebarGeneration = 0
    /// Counts sidebar saves, which show before they are written (see `reloadSidebar`).
    @ObservationIgnored private var sidebarSaves = 0
    /// The page on screen. Remembered across launches: the app opens on it again (mobile has no home screen).
    var activeTabID: String? {
        didSet {
            guard activeTabID != oldValue else { return }
            swipeOrder = nil
            // One page never shows in both panes: the other pane takes this pane's tab in trade.
            if activeTabID != nil, activeTabID == otherPaneTabID { otherPaneTabID = oldValue }
            pagesInViewChanged()
            guard let activeTabID, !incognitoTabs.contains(where: { $0.id == activeTabID }) else { return }
            UserDefaults.standard.set(activeTabID, forKey: Self.lastTabKey)
        }
    }
    private static let lastTabKey = "lastTabID"
    /// The tab order a run of swipes between tabs follows (see `pageTab`).
    @ObservationIgnored private var swipeOrder: [String]?
    var searchTarget: SearchTarget? { didSet { if searchTarget == nil { remoteSuggestions.clear() } } }
    var searchText = "" { didSet { refreshHistorySuggestions(); refreshRemoteSuggestions() } }
    var historySuggestions: [HistoryVisit] = []
    /// The search engine's suggestions for `searchText`.
    let remoteSuggestions = SearchSuggestions()
    var sheet: Sheet?
    /// A window a page opened as a pop-up, such as a sign-in (`PagePopups`).
    var popup: PagePopup?
    var showOnboarding = false
    var toast: Toast?
    var hinge: DeviceHinge?
    var isIncognito = false
    private(set) var incognitoTabs: [SidebarItem] = []
    /// Last rendered image of each tab, shown on its card. Saved in Caches (`SnapshotCache`), except private tabs'.
    /// Observed per tab, so one new preview redraws only its own card.
    let snapshots = ObservedDictionary<String, UIImage>()
    /// Half-open, the screen holds two panes: the focused one shows `activeTabID`, the other `otherPaneTabID`.
    private(set) var isSplit = false
    /// The pane the user last touched (0 is the leading or top one); always 0 outside the split.
    private(set) var focusedPane = 0
    private(set) var otherPaneTabID: String? { didSet { if otherPaneTabID != oldValue { pagesInViewChanged() } } }
    /// The focused pane's tab carousel, over its page.
    var showsCoverFlow = false
    /// Counts requests to open the carousel, so one made while it is still closing brings it back.
    private(set) var coverFlowRequests = 0
    /// The page's settings panel, from the rail's "…" (the search panel is `searchTarget`; one panel at a time).
    var showsPageSettings = false
    /// Each tab's page colors along the viewport's edges, which the screen edges and chrome take on. Observed per
    /// tab, so a background tab's sample doesn't redraw the one on screen.
    let siteEdges = ObservedDictionary<String, SiteEdges>()
    /// Bumped on every edge-swipe back/forward commit; `TabBrowser` fires a haptic off it.
    var backForwardHaptic = 0

    // Caches touched while views render; observing them would re-render in a loop.
    @ObservationIgnored private var pages: [String: WebPage] = [:]
    @ObservationIgnored private var pageRecency: [String] = []
    @ObservationIgnored private var isClosingIdlePages = false
    @ObservationIgnored private(set) var store: BoazStore?
    /// iCloud sync with the user's other devices (a picked folder only when iCloud isn't available).
    @ObservationIgnored private(set) var sync: LibrarySync?
    /// Compiled once at launch; `nil` until ready, so the very first page or two may load unblocked.
    /// `nil` until compiled. Pages opened before then (the tab reopened at launch) hold their first load until they
    /// have the lists, so no page loads with its ads.
    @ObservationIgnored private var contentBlockLists: [WKContentRuleList]?
    /// Keeps the app running in the background until the writes queued before it went there have landed.
    @ObservationIgnored private var backgroundWrites = UIBackgroundTaskIdentifier.invalid
    @ObservationIgnored private var suspendRequests = 0
    @ObservationIgnored private var awaitingBlockLists: [(controller: WKUserContentController, load: () -> Void)] = []
    /// Runs once the current sheet has finished dismissing (a tab can't present while a sheet is leaving).
    @ObservationIgnored private var afterSheet: (() -> Void)?
    @ObservationIgnored private var historyLookup: Task<Void, Never>?
    /// The previews waiting for their pages to stop scrolling, by tab (see `pageDidScroll`).
    @ObservationIgnored private var settledCaptures: [String: Task<Void, Never>] = [:]
    /// Where each tab's page last came to rest, and at which address; a page loaded again (evicted from the live
    /// pages, or after a relaunch) goes back there. Kept across launches; private tabs' aren't kept.
    @ObservationIgnored private var scrollPositions = ScrollPosition.saved()
    /// Positions waiting for their tab's page to finish loading (`pageDidFinishLoading`).
    @ObservationIgnored private var pendingScrolls: [String: ScrollPosition] = [:]
    /// Tabs whose title is cooling down after a save, and whether it changed again meanwhile (`didChangeTitle`).
    @ObservationIgnored private var titleCooldowns: [String: Bool] = [:]
    /// The address each tab's current page was recorded at in history, which its later titles name (`didCommitLoad`).
    @ObservationIgnored private var visitURLs: [String: URL] = [:]
    /// The tab ids `pruneSnapshots` last saw.
    @ObservationIgnored private var liveItemIDs: Set<String> = []
    /// The stale-tab sweep waits until the tab open at the last quit is back on screen, which keeps it out of the sweep.
    @ObservationIgnored private var holdsSweeps = true
    private let maxLivePages = 8
    /// This iPhone, in the device list: its tabs are the ones opened here (see `SidebarItem.isMobileTab`).
    let deviceID = Device.localID(in: UserDefaults(suiteName: BoazStore.appGroup) ?? .standard)
    /// Archived by closing, newest last; observed so the More menu's Reopen Closed Tab stays current.
    private var closedTabs: [(tab: SidebarItem, archiveID: String?, snapshot: UIImage?)] = []
    private static let log = Logger(subsystem: "com.chenkahana.boaz", category: "app")

    init() {
        UserDefaults.standard.register(defaults: [
            Preferences.archiveAfterKey: ArchiveInterval.day.rawValue,
            Preferences.searchEngineKey: SearchEngine.duckDuckGo.rawValue,
            Preferences.searchSuggestionsKey: true,
            Preferences.blockTrackersKey: true,
            Preferences.hideCookieBannersKey: true,
        ])
    }

    // MARK: Lifecycle

    func start() async {
        // Compiling EasyList the first time takes a few seconds; the library loads meanwhile.
        Task {
            let lists = await ContentBlocking.compiledLists()
            contentBlockLists = lists
            for page in awaitingBlockLists {
                lists.forEach(page.controller.add)
                page.load()
            }
            awaitingBlockLists = []
        }
        do {
            let sync = try prepareSync()
            guard let store else { return }
            // A device joining an existing library gets it from there; a lone device starts with a Personal space.
            if try store.isEmpty() {
                // Welcome goes up at once; the library (joined or starter) lands behind it.
                showOnboarding = Onboarding.shouldShow(store)
                await sync.start()
            }
            try StarterLibrary.seedIfEmpty(store)
            showOnboarding = showOnboarding || Onboarding.shouldShow(store)
            // Tabs filed under a space's Today by 0.2.3 and before join the stack.
            try await store.adoptMobileStack(deviceID: deviceID)
            Task { await restoreSnapshots(from: store) }
            Task { await sync.start() }
            registerDevice()
            await observeSidebar(store)
        } catch {
            Self.log.error("Opening the library failed: \(String(describing: error))")
            showToast("Couldn't open your library. Try reopening Boaz.")
        }
    }

    /// Follows the library for the life of the app. Any database error ends an observation (a fetch interrupted
    /// by the background suspension, say), so it starts again, backing off while the errors persist.
    private func observeSidebar(_ store: BoazStore) async {
        var failures = 0
        while !Task.isCancelled {
            do {
                for try await snapshot in store.sidebarUpdates() {
                    failures = 0
                    sidebar = snapshot
                    sidebarGeneration += 1
                    // Also how the stale-tab sweep's archived tabs lose their previews: the sweep lands as an update.
                    pruneSnapshots()
                    if sidebarGeneration == 1 {
                        reopenLastTab()
                        holdsSweeps = false
                        archiveStaleTabs()
                    }
                }
                return
            } catch {
                failures += 1
                Self.log.error("Following the library failed: \(String(describing: error))")
                // Only a library that never showed up is worth telling the user about.
                if failures == 1, sidebarGeneration == 0 { showToast("Couldn't open your library. Try reopening Boaz.") }
                try? await Task.sleep(for: .seconds(min(1 << min(failures, 5), 30)))
            }
        }
    }

    /// Opens the library and its sync once. A push or background refresh can launch the app with no scene.
    @discardableResult
    func prepareSync() throws -> LibrarySync {
        if let sync { return sync }
        let store = try BoazStore.onDisk(appGroup: BoazStore.appGroup)
        self.store = store
        let sync = LibrarySync(store: store)
        self.sync = sync
        return sync
    }

    /// Syncs for a push or background refresh. The database is suspended in the background, so it is woken for
    /// the work and suspended again if the app is still in the background.
    func backgroundSync() async {
        guard let sync = try? prepareSync() else { return }
        BoazStore.resumeDatabases()
        await sync.syncNow()
        if UIApplication.shared.applicationState == .background { BoazStore.suspendDatabases() }
    }

    /// Suspends the database for the background once the writes already queued have run: suspending fails the
    /// ones still waiting, and the sidebar would keep showing changes that were never saved.
    func suspendDatabase() {
        guard let store else { return BoazStore.suspendDatabases() }
        suspendRequests += 1
        let request = suspendRequests
        if backgroundWrites == .invalid {
            backgroundWrites = UIApplication.shared.beginBackgroundTask { [weak self] in self?.finishSuspending() }
        }
        Task {
            await store.waitForQueuedWrites()
            // A later request's wait covers this one's writes too, and it finishes last.
            if request == suspendRequests { finishSuspending() }
        }
    }

    private func finishSuspending() {
        guard backgroundWrites != .invalid else { return }
        if UIApplication.shared.applicationState == .background { BoazStore.suspendDatabases() }
        UIApplication.shared.endBackgroundTask(backgroundWrites)
        backgroundWrites = .invalid
    }

    /// Picks up rows the share extension wrote while the app was away: the live observation only sees this
    /// process's own commits. It is read once the saves already queued are written, and dropped if the observation
    /// delivers a newer snapshot or a save happens meanwhile, so it never takes back a change the sidebar shows.
    func reloadSidebar() {
        guard let store else { return }
        let generation = sidebarGeneration, saves = sidebarSaves
        Task {
            await store.waitForQueuedWrites()
            guard let fresh = try? await store.loadSidebar(), generation == sidebarGeneration, saves == sidebarSaves
            else { return }
            sidebar = fresh
            pruneSnapshots()
        }
    }

    /// Moves Today tabs untouched for the chosen interval into the archive, as Arc does.
    func archiveStaleTabs() {
        let interval = Preferences.archiveAfter
        guard interval != .never, !holdsSweeps, let store else { return }
        // The pages on screen are in use, however long ago they were picked (the second pane's may never have been).
        let showing = [activeTabID, otherPaneTabID].compactMap { $0.flatMap(item(withID:)) }.filter { !isPrivate($0) }
        for var tab in showing {
            tab.lastActiveAt = .now
            commit(tab)
        }
        Task {
            do {
                let count = try await store.archiveStaleTabs(olderThan: TimeInterval(interval.rawValue), onDevice: deviceID)
                if count > 0 { showToast("Archived \(count) inactive tab\(count == 1 ? "" : "s")") }
            } catch {
                Self.log.error("Archiving stale tabs failed: \(String(describing: error))")
                showToast("Couldn't archive inactive tabs.")
            }
        }
    }

    /// Brings back the previews saved before the last quit, and forgets those of tabs that are gone.
    private func restoreSnapshots(from store: BoazStore) async {
        let started = Date.now
        guard let ids = try? await store.loadSidebar().items.map(\.id) else { return }
        let saved = await SnapshotCache.load(keeping: Set(ids), writtenBefore: started)
        for (id, image) in saved where snapshots[id] == nil { snapshots[id] = image }
        // A snapshot that landed meanwhile (the launch sweep's, say) was pruned before these arrived.
        if sidebarGeneration > 0 {
            liveItemIDs = []
            pruneSnapshots()
        }
    }

    /// Refreshes this iPhone's name and last-seen time for the user's other devices.
    func registerDevice() {
        guard let store else { return }
        Task {
            do {
                try await store.registerDevice(id: deviceID, name: UIDevice.current.name, platform: .iOS)
            } catch {
                Self.log.error("Recording this device failed: \(String(describing: error))")
            }
        }
    }

    // MARK: Reads

    /// The Mac's spaces, for Tabs on Your Mac. The phone's own tabs are in none of them.
    var spaces: [Space] { sidebar.spaces }
    var activeTab: SidebarItem? { activeTabID.flatMap(item(withID:)) }
    /// Whether the library's first snapshot has landed; a new tab needs its profile.
    var hasLibrary: Bool { !sidebar.profiles.isEmpty }

    /// The phone's tabs, most recently used first: its mobile stack, or the private tabs in Incognito. The stack
    /// is no space's (`SidebarItem.isMobileTab`); the Mac's spaces are only for picking pages from.
    var phoneTabs: [SidebarItem] {
        isIncognito ? incognitoTabs.sorted { ($0.lastActiveAt ?? $0.createdAt) > ($1.lastActiveAt ?? $1.createdAt) }
            : sidebar.mobileTabs(onDevice: deviceID)
    }

    /// Whether a tab is one of this iPhone's own (not a space's, not another device's, not private).
    func isMine(_ tab: SidebarItem) -> Bool { tab.isMobileTab && tab.deviceID == deviceID }

    /// New tabs browse with the default profile's website data; a page picked from the Mac keeps its tab's.
    private var defaultProfileID: String? {
        (sidebar.profiles.first { $0.isDefault } ?? sidebar.profiles.first)?.id
    }

    /// The tab a pane shows; the second pane exists only in the split.
    func tabID(inPane pane: Int) -> String? { pane == focusedPane ? activeTabID : otherPaneTabID }

    func tab(inPane pane: Int) -> SidebarItem? { tabID(inPane: pane).flatMap(item(withID:)) }

    func isPinned(_ tab: SidebarItem) -> Bool {
        guard let parent = tab.parentID, !isPrivate(tab) else { return false }
        return ancestorContainer(of: parent)?.containerKind != .unpinned
    }

    func isPrivate(_ tab: SidebarItem) -> Bool { tab.parentID == Self.incognitoParent }

    /// Whether a tab is open here: every tab of this iPhone's is, and any tab whose page has been opened.
    func isOpen(_ tab: SidebarItem) -> Bool { pages[tab.id] != nil || isMine(tab) }

    // MARK: Pages

    func page(for tab: SidebarItem) -> WebPage {
        pageRecency.removeAll { $0 == tab.id }
        pageRecency.append(tab.id)
        if let page = pages[tab.id] { return page }
        let tabIsPrivate = isPrivate(tab)
        var configuration = WebPage.Configuration()
        if tabIsPrivate { configuration.websiteDataStore = .nonPersistent() }
        // Videos play in the page, as in Safari, rather than jumping to fullscreen (the iPhone default). Autoplay keeps
        // WebKit's default: nothing plays before the user taps.
        configuration.mediaPlaybackBehavior = .allowsInlinePlayback
        let blocksContent = Preferences.blockTrackers
            && PageSettings.settings(for: tab.url, isPrivate: tabIsPrivate).contentBlocking
        if blocksContent, let contentBlockLists { contentBlockLists.forEach(configuration.userContentController.add) }
        if Preferences.hideCookieBanners {
            configuration.userContentController.addUserScript(CookieBanners.userScript())
        }
        configuration.userContentController.addUserScript(SiteEdges.userScript())
        configuration.userContentController.add(SiteEdges.Messages { [weak self] edges, url in
            self?.didSampleEdges(edges, at: url, tabID: tab.id, isPrivate: tabIsPrivate)
        }, contentWorld: .defaultClient, name: SiteEdges.messageName)
        // Website Settings' camera/microphone pickers, per host; re-read on every request, so a change
        // made while the tab is open takes effect on the site's next request, not just its next open. Keyed by
        // the page's host, as the sheet is: an embedded frame doesn't get its own say.
        configuration.deviceSensorAuthorization = .init { [weak self] permission, _, _ in
            guard case .mediaCapture(let type) = permission else { return .prompt }
            let host = self?.pages[tab.id]?.url?.host() ?? tab.url?.host()
            return PageSettings.mediaCaptureDecision(type, host: host, isPrivate: tabIsPrivate)
        }
        let dataStore = configuration.websiteDataStore
        let decider = BoazNavigationDecider(
            isPrivate: tabIsPrivate,
            page: { [weak self] in self?.pages[tab.id] },
            onBackForward: { [weak self] in self?.backForwardHaptic += 1 },
            hostPopups: { [weak self] in self?.hostPopups(for: tab.id, isPrivate: tabIsPrivate) },
            onDownload: { [weak self] response in
                self?.discardIfDownloadOnly(tab.id)
                self?.handleDownload(response, dataStore: dataStore)
            })
        let pictureInPicture = PictureInPicture.install(in: &configuration)
        let page = WebPage(configuration: configuration, navigationDecider: decider)
        pictureInPicture.attach(page)
        pictureInPicture.onRestore = { [weak self] in
            guard let self, let tab = self.item(withID: tab.id), !self.pagesInView.contains(tab.id) else { return }
            self.activate(tab)
        }
        page.customUserAgent = PageSettings.userAgent(forHost: tab.url?.host(), isPrivate: tabIsPrivate)
        if let url = tab.url {
            if blocksContent, contentBlockLists == nil {
                awaitingBlockLists.append((configuration.userContentController, { [weak page] in
                    // Unless the page went somewhere else in the meantime.
                    if let page, page.url == nil { page.load(URLRequest(url: url)) }
                }))
            } else {
                page.load(URLRequest(url: url))
            }
        }
        pages[tab.id] = page
        if let position = scrollPositions[tab.id], position.url == tab.url { pendingScrolls[tab.id] = position }
        closeIdlePages()
        return page
    }

    /// Over the limit, the least recently used pages close, except those in a pane and those playing, recording or
    /// in full screen: music in a background tab keeps playing however many tabs open after it.
    private func closeIdlePages() {
        guard pages.count > maxLivePages, !isClosingIdlePages else { return }
        isClosingIdlePages = true
        Task {
            let close = await PageResidency.pagesToClose(recency: pageRecency, pages: pages, limit: maxLivePages,
                                                         keeping: pagesInView)
            for id in close where !pagesInView.contains(id) {
                pageRecency.removeAll { $0 == id }
                pages[id] = nil
            }
            isClosingIdlePages = false
        }
    }

    private var pagesInView: Set<String> { Set([tabID(inPane: 0), tabID(inPane: 1)].compactMap(\.self)) }

    /// Pop-ups open in a sheet; any other window loads in the tab that opened it. A site whose pop-ups are blocked
    /// gets neither for the windows its scripts open.
    private func hostPopups(for tabID: String, isPrivate: Bool) {
        guard let page = pages[tabID] else { return }
        _ = PagePopups.install(on: page, allowsScriptWindows: { [weak page] in
            PageSettings.settings(for: page?.url, isPrivate: isPrivate).popups != .block
        }, present: { [weak self] in self?.popup = $0 }, dismiss: { [weak self] closed in
            self?.popup = PagePopups.remaining(after: closed, shown: self?.popup)
        }, fallback: { [weak page] action in page?.load(action.request) })
    }

    // MARK: Picture in Picture

    @ObservationIgnored private var shownPages: Set<String> = []
    @ObservationIgnored private var isInForeground = true

    /// A video still playing in a tab that leaves the screen floats in Picture in Picture; one Boaz floated returns to
    /// its tab when the tab shows again.
    private func pagesInViewChanged() {
        let now = pagesInView
        let previous = shownPages
        shownPages = now
        guard isInForeground else { return }
        for id in previous.subtracting(now) { pictureInPicture(id)?.floatOnLeaving() }
        for id in now.subtracting(previous) { pictureInPicture(id)?.returnFromLeaving() }
    }

    /// Leaving Boaz (Home, another app) floats the video on screen; coming back returns it.
    func sceneDidChange(isActive: Bool) {
        guard isActive != isInForeground else { return }
        isInForeground = isActive
        for id in pagesInView {
            if isActive { pictureInPicture(id)?.returnFromLeaving() } else { pictureInPicture(id)?.floatOnLeaving() }
        }
    }

    private func pictureInPicture(_ tabID: String) -> PictureInPicture? {
        pages[tabID].flatMap(PictureInPicture.controller(of:))
    }

    /// Called by `TabBrowser`'s single `page.navigations` subscriber on every finished load — the
    /// async sequence only supports one consumer, so AppModel never subscribes to it directly.
    func pageDidFinishLoading(_ tab: SidebarItem) {
        guard let page = pages[tab.id] else { return }
        let tabIsPrivate = isPrivate(tab)
        captureSnapshot(of: page, tab: tab)
        if let position = pendingScrolls.removeValue(forKey: tab.id), position.url == page.url {
            Task { _ = try? await page.callJavaScript(ScrollPosition.restoreScript, arguments: ["y": position.y]) }
        }
        Task {
            guard let pageURL = page.url,
                  let href = try? await page.callJavaScript(Favicons.discoveryScript, contentWorld: .defaultClient) as? String,
                  let iconURL = URL(string: href, relativeTo: pageURL)?.absoluteURL else { return }
            Favicons.shared.learn(iconURL: iconURL, forPageAt: pageURL, isPrivate: tabIsPrivate)
        }
    }

    /// Until the new page reports its own edge colors, a page or site seen before shows the colors it had.
    func restoreSiteEdges(for tab: SidebarItem) {
        guard !isPrivate(tab), let cached = SiteEdges.cached(for: pages[tab.id]?.url), siteEdges[tab.id] != cached
        else { return }
        siteEdges[tab.id] = cached
    }

    /// The page's live edge sampler (`SiteEdges.userScript`) reports only changes. Private tabs' colors aren't cached.
    private func didSampleEdges(_ edges: SiteEdges, at url: URL?, tabID: String, isPrivate: Bool) {
        if !isPrivate, let url { SiteEdges.remember(edges, for: url) }
        if siteEdges[tabID] != edges { siteEdges[tabID] = edges }
    }

    /// Downscaled render of what a tab's page shows on screen (the viewport as scrolled, not the top of the
    /// document), dropped when the tab closes.
    private func captureSnapshot(of page: WebPage, tab: SidebarItem) {
        Task { await snapshot(page, tab: tab) }
    }

    /// The showing tab's preview, refreshed as it is about to be left for a new tab or another app, while its
    /// page still shows.
    func captureActiveSnapshot() {
        if let tab = activeTab, let page = pages[tab.id] { captureSnapshot(of: page, tab: tab) }
    }

    /// Keeps a showing tab's preview (either pane's) at what it shows once its page comes to rest. By the time a
    /// tab is left its page is already moving (the toolbar drags it) or gone, and no longer renders what was on screen.
    func pageDidScroll(_ tab: SidebarItem) {
        settledCaptures[tab.id]?.cancel()
        settledCaptures[tab.id] = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let page = pages[tab.id] else { return }
            settledCaptures[tab.id] = nil
            await rememberScroll(of: page, tab: tab)
            await snapshot(page, tab: tab)
        }
    }

    /// Drops a position waiting to be put back once the page is no longer loading the address it was saved at: it
    /// finished while its browser wasn't watching, or went somewhere else first.
    func dropStalePendingScroll(_ tab: SidebarItem) {
        guard let position = pendingScrolls[tab.id], let page = pages[tab.id], let url = page.url,
              !page.isLoading || !url.isSamePage(as: position.url) else { return }
        pendingScrolls[tab.id] = nil
    }

    /// Saves where the page came to rest. Not while it loads: a page loading again sits at the top until its
    /// position is put back.
    private func rememberScroll(of page: WebPage, tab: SidebarItem) async {
        guard !isPrivate(tab), !page.isLoading, let url = page.url,
              let y = (try? await page.callJavaScript("return window.scrollY;") as? NSNumber)?.doubleValue,
              scrollPositions[tab.id] != ScrollPosition(url: url, y: y) else { return }
        scrollPositions[tab.id] = ScrollPosition(url: url, y: y)
        ScrollPosition.save(scrollPositions)
    }

    private func snapshot(_ page: WebPage, tab: SidebarItem) async {
        // A page whose web view has left the screen renders at a default size, not as it was last seen; the
        // preview taken while it showed is kept instead.
        guard pageOwners[tab.id] != nil,
              let data = try? await page.exported(as: .image(snapshotWidth: 400)),
              pageOwners[tab.id] != nil,
              let image = UIImage(data: data),
              // The tab may have closed while the page rendered.
              isLive(tab.id) else { return }
        snapshots[tab.id] = image
        if !isPrivate(tab) { SnapshotCache.save(data, for: tab.id) }
    }

    private func isLive(_ tabID: String) -> Bool {
        sidebar.items.contains { $0.id == tabID } || incognitoTabs.contains { $0.id == tabID }
    }

    /// Forgets the previews of tabs that are gone: archived by the stale-tab sweep, or closed on another device.
    /// Most updates only edit tabs that are still there, so nothing is checked until the set of tabs changes.
    private func pruneSnapshots() {
        let ids = Set(sidebar.items.map(\.id))
        guard ids != liveItemIDs else { return }
        liveItemIDs = ids
        let live = ids.union(incognitoTabs.map(\.id))
        for id in snapshots.keys where !live.contains(id) {
            snapshots[id] = nil
            SnapshotCache.remove(id)
        }
        let kept = scrollPositions.filter { ids.contains($0.key) }
        if kept.count != scrollPositions.count {
            scrollPositions = kept
            ScrollPosition.save(kept)
        }
    }

    // WebKit traps when two WebViews show the same WebPage. That happens for a moment whenever the posture
    // changes: the old layout's browser is still on screen while the new layout's appears. So each browser
    // claims its tab's page, and a new claim only gets the page once the current host's WebView is gone.
    private(set) var pageOwners: [String: UUID] = [:]
    @ObservationIgnored private var pageClaims: [String: UUID] = [:]
    @ObservationIgnored private var pageReleasing: [String: UUID] = [:]

    func claimPage(_ tabID: String, host: UUID) {
        guard pageOwners[tabID] != host else { return }
        if pageReleasing[tabID] != nil {
            pageClaims[tabID] = host
        } else if let owner = pageOwners[tabID] {
            pageReleasing[tabID] = owner
            pageClaims[tabID] = host
            pageOwners[tabID] = nil
        } else {
            pageOwners[tabID] = host
        }
    }

    /// Called once a browser's WebView has left the screen, or the browser itself went away.
    func releasePage(_ tabID: String, host: UUID) {
        if pageClaims[tabID] == host { pageClaims[tabID] = nil }
        if pageOwners[tabID] == host { pageOwners[tabID] = nil }
        if pageReleasing[tabID] == host { pageReleasing[tabID] = nil }
        if pageReleasing[tabID] == nil, pageOwners[tabID] == nil, let next = pageClaims.removeValue(forKey: tabID) {
            pageOwners[tabID] = next
        }
    }

    /// A Today or private tab whose only navigation turned into a download never showed a page. Drop it,
    /// rather than keep a tab that downloads the file again every time it's opened.
    private func discardIfDownloadOnly(_ tabID: String) {
        guard pages[tabID]?.backForwardList.currentItem == nil,
              let tab = sidebar.items.first(where: { $0.id == tabID }) ?? incognitoTabs.first(where: { $0.id == tabID }),
              !isPinned(tab) else { return }
        if activeTabID == tabID { activeTabID = nil }
        if otherPaneTabID == tabID { otherPaneTabID = nil }
        pages[tabID] = nil
        pageRecency.removeAll { $0 == tabID }
        snapshots[tabID] = nil
        siteEdges[tabID] = nil
        SnapshotCache.remove(tabID)
        if isPrivate(tab) {
            incognitoTabs.removeAll { $0.id == tabID }
        } else {
            var removed = tab
            removed.deletedAt = .now
            commit(removed)
        }
    }

    /// Re-fetches a non-renderable response with the page's own cookies and saves it to Downloads.
    private func handleDownload(_ response: URLResponse, dataStore: WKWebsiteDataStore) {
        Task { [weak self] in
            do {
                let (_, name) = try await Downloads.save(response, dataStore: dataStore)
                self?.showToast("Downloaded \(name)")
            } catch {
                Self.log.error("Download failed: \(String(describing: error))")
                self?.showToast("Couldn't download the file. Try again.")
            }
        }
    }

    /// Persists where a tab has navigated to. In history it only names the visit its load recorded (`didCommitLoad`).
    func didNavigate(_ tab: SidebarItem, url: URL?, title: String) {
        guard var item = sidebar.items.first(where: { $0.id == tab.id }) ?? incognitoTabs.first(where: { $0.id == tab.id })
        else { return }
        // A pinned tab keeps its saved address and title; only Today tabs follow the page.
        let pinned = isPinned(item)
        // WebKit shows about:blank for a load it refused outright; the tab keeps the address it was asked for.
        let newURL = pinned || url?.absoluteString == "about:blank" ? item.url : url ?? item.url
        let newTitle = title.isEmpty || (pinned && item.title != nil) ? item.title : title
        if item.url != newURL || item.title != newTitle {
            item.url = newURL
            item.title = newTitle
            commit(item)
        }
        // Only the page the visit was recorded for names it: the address is still the previous page's while the
        // next one loads, and that page's title may arrive before its commit is seen.
        if !title.isEmpty, let url, let visit = visitURLs[tab.id], url.isSamePage(as: visit) {
            store?.updateVisitTitle(title, for: visit, profileID: item.profileID)
        }
    }

    /// A page committed a new load: one history visit (except private tabs), at the address the load ended on. The
    /// address also changes for a load that hasn't committed yet, at every server redirect hop and for same-document
    /// updates (`replaceState`, fragments); none of those commit, so none adds a visit.
    func didCommitLoad(_ tab: SidebarItem) {
        guard !isPrivate(tab), let page = pages[tab.id], let url = page.url, url.scheme?.hasPrefix("http") == true else {
            visitURLs[tab.id] = nil
            return
        }
        visitURLs[tab.id] = url
        // The title at commit may still be the previous page's; the page's own arrives through `didNavigate`.
        store?.recordVisit(profileID: tab.profileID, url: url, title: nil)
    }

    /// A page that isn't loading changed address on its own (`pushState`, as single-page sites navigate): a new page
    /// in history, unless only the fragment changed. `replaceState` while a load is in flight (a search page tidying
    /// its address) adds none.
    private func recordSameDocumentVisit(_ tab: SidebarItem, page: WebPage) {
        guard !isPrivate(tab), !page.isLoading, let url = page.url, url.scheme?.hasPrefix("http") == true,
              visitURLs[tab.id].map({ !url.isSamePage(as: $0) }) ?? true else { return }
        visitURLs[tab.id] = url
        store?.recordVisit(profileID: tab.profileID, url: url, title: page.title.isEmpty ? nil : page.title)
    }

    /// Pages that animate their title (unread counts, timers) would otherwise save, sync and refetch the whole
    /// sidebar on every tick. A title change is saved at once, then at most every two seconds with the latest title.
    /// A new page gets its title saved at once, not after the previous page's cooldown.
    func didChangeURL(_ tab: SidebarItem) {
        titleCooldowns[tab.id] = nil
        guard let page = pages[tab.id] else { return }
        recordSameDocumentVisit(tab, page: page)
        didNavigate(tab, url: page.url, title: page.title)
    }

    func didChangeTitle(_ tab: SidebarItem) {
        guard titleCooldowns[tab.id] == nil else { titleCooldowns[tab.id] = true; return }
        guard let page = pages[tab.id] else { return }
        didNavigate(tab, url: page.url, title: page.title)
        titleCooldowns[tab.id] = false
        Task {
            try? await Task.sleep(for: .seconds(2))
            if titleCooldowns.removeValue(forKey: tab.id) == true { didChangeTitle(tab) }
        }
    }

    // MARK: Actions

    func beginSearch(_ target: SearchTarget) {
        searchText = target == .currentTab ? (activeTab?.url?.absoluteString ?? "") : ""
        searchTarget = target
        if asksSearchEngine { remoteSuggestions.warm(Preferences.searchEngine) }
        // The page about to be left for a new tab is still on screen, under the panel.
        if target == .newTab { captureActiveSnapshot() }
    }

    func submitSearch() {
        // A second Go or suggestion tap while the panel closes would open a duplicate tab.
        guard searchTarget != nil else { return }
        defer { searchTarget = nil }
        guard let url = SearchInput.url(for: searchText, searchTemplate: Preferences.searchEngine.template) else { return }
        if searchTarget == .currentTab, let tab = activeTab {
            page(for: tab).load(URLRequest(url: url))
        } else {
            openNewTab(url)
        }
    }

    /// Opens a page in a new tab, on top of the stack. It browses with `profileID`'s website data, else the default
    /// profile's.
    func openNewTab(_ url: URL, title: String? = nil, profileID: String? = nil) {
        searchTarget = nil
        if isIncognito {
            let tab = SidebarItem(id: UUID().uuidString, spaceID: nil, profileID: "incognito",
                                  parentID: Self.incognitoParent, kind: .tab, title: title ?? url.host(), url: url,
                                  position: Double(incognitoTabs.count), lastActiveAt: .now)
            incognitoTabs.append(tab)
            activeTabID = tab.id
            return
        }
        guard let profileID = profileID ?? defaultProfileID else { return }
        let tab = SidebarItem.mobileTab(url: url, title: title, profileID: profileID, deviceID: deviceID)
        commit(tab)
        activate(tab)
    }

    func activate(_ tab: SidebarItem) {
        guard tab.kind == .tab else { return }
        // The phone shows only its own tabs: a space's tab (pinned, a favorite, or open on a Mac) is copied into a
        // new tab on top of the stack, with its website data, and the space's item stays as it is.
        if !isMine(tab), !isPrivate(tab) {
            guard let url = tab.url else { return }
            return openNewTab(url, title: tab.title, profileID: tab.profileID)
        }
        guard tab.id == otherPaneTabID else { return show(tab) }
        // The panes trade tabs (see `activeTabID`) in place: neither page slides, even when the change animates. All
        // of it goes in the transaction, which first publishes the changes made before it.
        var swap = Transaction(animation: nil)
        swap.disablesAnimations = true
        withTransaction(swap) { show(tab) }
    }

    private func show(_ tab: SidebarItem) {
        searchTarget = nil
        var item = tab
        item.lastActiveAt = .now
        item.isUnread = false
        commit(item)
        activeTabID = tab.id
        // A normal tab can't show in Incognito: opening one leaves it, closing the private tabs as Leave Incognito does.
        if isIncognito, !isPrivate(tab) { setIncognito(false) }
    }

    /// Entering the split, the page on screen takes the leading pane and the most recently used other tab the
    /// trailing one. Leaving it, the focused pane's tab stays on screen.
    func setSplit(_ on: Bool) {
        guard on != isSplit else { return }
        if !on, activeTabID == nil { activeTabID = otherPaneTabID }
        focusedPane = 0
        otherPaneTabID = on ? mostRecentTab(excluding: [activeTabID])?.id : nil
        isSplit = on
    }

    /// Touching a pane makes its tab the active one; the other pane's panels go away.
    func focusPane(_ pane: Int) {
        guard isSplit, pane != focusedPane else { return }
        showsCoverFlow = false
        showsPageSettings = false
        // Each pane keeps its tab, so nothing here may publish a moment where they've traded (see `activate`).
        focusedPane = pane
        if let tab = otherPaneTabID.flatMap(item(withID:)) {
            show(tab)
        } else {
            otherPaneTabID = activeTabID
            activeTabID = nil
        }
    }

    /// The top of the stack, skipping `ids`.
    private func mostRecentTab(excluding ids: [String?]) -> SidebarItem? {
        phoneTabs.first { !ids.contains($0.id) }
    }

    private func item(withID id: String) -> SidebarItem? {
        sidebar.items.first { $0.id == id } ?? incognitoTabs.first { $0.id == id }
    }

    /// The page open when the app last closed, else the top of the stack. Marked active like any tab the user opens
    /// (which keeps it out of the launch sweep). Unlike `activate`, it leaves a search panel a deep link opened
    /// meanwhile up.
    private func reopenLastTab() {
        guard activeTabID == nil else { return }
        let last = UserDefaults.standard.string(forKey: Self.lastTabKey)
        // Only one of the phone's own tabs (see `activate`); before 0.2.4 a pinned tab could be the one left open.
        guard var tab = phoneTabs.first(where: { $0.id == last }) ?? phoneTabs.first else { return }
        tab.lastActiveAt = .now
        tab.isUnread = false
        commit(tab)
        activeTabID = tab.id
    }

    func openCoverFlow() {
        showsPageSettings = false
        searchTarget = nil
        Task {
            // The deck grows out of the page's card, which must show the page as it is now, or the page jumps.
            if let tab = activeTab, let page = pages[tab.id] { await snapshot(page, tab: tab) }
            showsCoverFlow = true
            coverFlowRequests += 1
        }
    }

    /// Closing sends a tab to the archive (like Arc); undo brings it back and removes the archive entry.
    func close(_ tab: SidebarItem) {
        // A second close of the same tab (a double tap, say) would archive it twice.
        guard isLive(tab.id) else { return }
        // A pane whose tab goes shows the next most recent tab the other pane isn't showing.
        if activeTabID == tab.id { activeTabID = mostRecentTab(excluding: [tab.id, otherPaneTabID])?.id }
        if otherPaneTabID == tab.id { otherPaneTabID = mostRecentTab(excluding: [tab.id, activeTabID])?.id }
        pictureInPicture(tab.id)?.detach()
        pages[tab.id] = nil
        settledCaptures.removeValue(forKey: tab.id)?.cancel()
        pageRecency.removeAll { $0 == tab.id }
        let snapshot = snapshots[tab.id]
        snapshots[tab.id] = nil
        siteEdges[tab.id] = nil
        SnapshotCache.remove(tab.id)
        if isPrivate(tab) {
            incognitoTabs.removeAll { $0.id == tab.id }
            return
        }
        var removed = tab
        removed.deletedAt = .now
        sidebar.upsert(removed)
        do {
            // Undo after the sweep got there first would bring back a tab that is also in the archive.
            guard case .archived(let entry)? = try store?.archive(tab, reason: "closed") else { return }
            closedTabs.append((tab, entry?.id, snapshot))
            showToast("Tab archived", canUndo: true)
        } catch {
            Self.log.error("Archiving a tab failed: \(String(describing: error))")
            showToast("Couldn't archive the tab. Try again.")
        }
    }

    var canReopenClosedTab: Bool { !closedTabs.isEmpty }

    func undoClose() {
        guard let (tab, archiveID, snapshot) = closedTabs.popLast() else { return }
        var restored = tab
        restored.deletedAt = nil
        commit(restored)
        // The card comes back as it went, not as a placeholder until the page is next seen.
        if let snapshot {
            snapshots[tab.id] = snapshot
            SnapshotCache.save(snapshot, for: tab.id)
        }
        if let archiveID { try? store?.removeFromArchive(archiveID) }
        showToast("Tab restored")
    }

    /// Brings an archived page back as a new tab, with its website data if its profile is still here.
    func restore(_ item: ArchiveItem) {
        try? store?.removeFromArchive(item.id)
        let profileID = sidebar.profiles.contains { $0.id == item.profileID } ? item.profileID : nil
        openAfterSheet(item.url, title: item.title, profileID: profileID)
    }

    func openAfterSheet(_ url: URL, title: String?, profileID: String? = nil) {
        afterSheet = { [weak self] in self?.openNewTab(url, title: title, profileID: profileID) }
        sheet = nil
    }

    func sheetDidDismiss() {
        afterSheet?()
        afterSheet = nil
    }

    /// Entering starts on Incognito's own empty page, in both panes, so nothing browsed next is a normal tab's;
    /// leaving goes back to the normal tabs that were open.
    func setIncognito(_ on: Bool) {
        guard on != isIncognito else { return }
        if on {
            otherPaneTabID = nil
            activeTabID = incognitoTabs.last?.id
            isIncognito = true
        } else {
            for tab in incognitoTabs {
                pages[tab.id] = nil
                snapshots[tab.id] = nil
                siteEdges[tab.id] = nil
            }
            pageRecency.removeAll { id in incognitoTabs.contains { $0.id == id } }
            incognitoTabs = []
            PageSettings.forgetPrivateChoices()
            PageZoom.forgetPrivateLevels()
            if let id = otherPaneTabID, sidebar.items.first(where: { $0.id == id }) == nil { otherPaneTabID = nil }
            // Before the panes are filled again, which pick from the phone's tabs (`phoneTabs`), not the private ones.
            isIncognito = false
            if !sidebar.items.contains(where: { $0.id == activeTabID }) {
                activeTabID = nil
                reopenLastTab()
            }
            if isSplit, otherPaneTabID == nil { otherPaneTabID = mostRecentTab(excluding: [activeTabID])?.id }
        }
        showToast(on ? "Incognito on" : "Incognito off — private tabs closed")
    }

    /// Moves to the tab used before (-1) or after (+1) the active one, as the tab carousel lays them out (the most
    /// recent last). Returns false at the ends.
    /// Swiping through tabs keeps the order the first swipe saw, though each tab reached comes to the top of the
    /// stack: swiping back twice goes two tabs back rather than between the same two. Any other tab change ends it.
    @discardableResult
    func pageTab(by offset: Int) -> Bool {
        guard let tab = activeTab else { return false }
        let order = swipeOrder ?? phoneTabs.reversed().map(\.id)
        guard let index = order.firstIndex(of: tab.id), order.indices.contains(index + offset),
              let next = item(withID: order[index + offset]) else { return false }
        activate(next)
        swipeOrder = order
        return true
    }

    // MARK: Helpers

    /// Saves to the store, or updates the in-memory list for private tabs.
    private func commit(_ item: SidebarItem) {
        if isPrivate(item) {
            if let index = incognitoTabs.firstIndex(where: { $0.id == item.id }) { incognitoTabs[index] = item }
            return
        }
        var item = item
        item.modifiedAt = .now
        sidebar.upsert(item)
        sidebarSaves += 1
        // Every tab tap and navigation lands here, so the write never holds up the main thread.
        store?.saveInBackground([item]) { [weak self] error in
            Self.log.error("Saving a sidebar item failed: \(String(describing: error))")
            self?.showToast("Couldn't save. Try again.")
        }
    }

    /// Looks history up once typing pauses, off the main thread: matching scans the whole history.
    private func refreshHistorySuggestions() {
        historyLookup?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard searchTarget == .newTab, !isIncognito, query.count > 1, let store else {
            if !historySuggestions.isEmpty { historySuggestions = [] }
            return
        }
        // Until the lookup lands, only rows that still match are offered (and completed to).
        if historySuggestions.contains(where: { !$0.matches(query) }) { historySuggestions.removeAll { !$0.matches(query) } }
        historyLookup = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, let found = try? await store.historySuggestions(matching: query, limit: 4),
                  !Task.isCancelled else { return }
            historySuggestions = found
        }
    }

    /// Whether typing may be sent to the search engine for suggestions: never in private browsing.
    var asksSearchEngine: Bool {
        searchTarget != nil && Preferences.searchSuggestions && !isIncognito && activeTab.map(isPrivate) != true
    }

    private func refreshRemoteSuggestions() {
        guard asksSearchEngine, !SearchSuggestions.looksLikeAddress(searchText) else { return remoteSuggestions.clear() }
        remoteSuggestions.update(searchText, engine: Preferences.searchEngine)
    }

    private func ancestorContainer(of id: String) -> SidebarItem? {
        var current = sidebar.items.first { $0.id == id }
        while let item = current, item.kind != .container {
            current = item.parentID.flatMap { pid in sidebar.items.first { $0.id == pid } }
        }
        return current
    }

    func showToast(_ message: String, canUndo: Bool = false) {
        let toast = Toast(message: message, canUndo: canUndo)
        self.toast = toast
        AccessibilityNotification.Announcement(message).post()
        // VoiceOver users need longer to reach Undo.
        let undoTime: Double = UIAccessibility.isVoiceOverRunning ? 10 : 5
        Task {
            try? await Task.sleep(for: .seconds(canUndo ? undoTime : 2.5))
            if self.toast == toast { self.toast = nil }
        }
    }
}

/// A page's vertical scroll offset in CSS pixels (`window.scrollY`), and the address it was on.
struct ScrollPosition: Codable, Equatable {
    var url: URL
    var y: Double

    private static let key = "scrollPositions"

    static func saved() -> [String: ScrollPosition] {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([String: Self].self, from: $0) } ?? [:]
    }

    static func save(_ positions: [String: ScrollPosition]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(positions), forKey: key)
    }

    /// Scrolls to `y`, trying again for two seconds while the page is still too short to get there (late images,
    /// lazy content). Stops as soon as the user scrolls it.
    static let restoreScript = """
    var tries = 0, last = null;
    (function go() {
      if (last !== null && Math.abs(window.scrollY - last) > 2) { return; }
      window.scrollTo(0, y);
      last = window.scrollY;
      if (Math.abs(last - y) > 2 && ++tries < 20) { setTimeout(go, 100); }
    })();
    """
}

enum ArchiveInterval: Int, CaseIterable, Identifiable {
    case twelveHours = 43_200, day = 86_400, week = 604_800, month = 2_592_000, never = 0
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .twelveHours: "After 12 hours"
        case .day: "After 1 day"
        case .week: "After 7 days"
        case .month: "After 30 days"
        case .never: "Never"
        }
    }
}

enum Preferences {
    static let archiveAfterKey = "archiveAfter"
    static let searchEngineKey = "searchEngine"
    static let blockTrackersKey = "blockTrackers"
    static let hideCookieBannersKey = "hideCookieBanners"
    static let searchSuggestionsKey = "searchSuggestions"
    /// Read through `@AppStorage` (default on) by the views that tint.
    static let tintWithSiteColorsKey = "tintWithSiteColors"

    static var archiveAfter: ArchiveInterval {
        ArchiveInterval(rawValue: UserDefaults.standard.integer(forKey: archiveAfterKey)) ?? .day
    }
    static var searchEngine: SearchEngine {
        SearchEngine(rawValue: UserDefaults.standard.string(forKey: searchEngineKey) ?? "") ?? .duckDuckGo
    }
    static var searchSuggestions: Bool { UserDefaults.standard.bool(forKey: searchSuggestionsKey) }
    static var blockTrackers: Bool { UserDefaults.standard.bool(forKey: blockTrackersKey) }
    static var hideCookieBanners: Bool { UserDefaults.standard.bool(forKey: hideCookieBannersKey) }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("BoazDeviceDidShake")
}

extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .deviceDidShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}
