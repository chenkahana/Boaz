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
    var currentSpaceID: String? {
        didSet {
            guard currentSpaceID != oldValue else { return }
            UserDefaults(suiteName: BoazStore.appGroup)?.set(currentSpaceID, forKey: "currentSpaceID")
        }
    }
    var activeTabID: String?
    var searchTarget: SearchTarget? { didSet { if searchTarget == nil { remoteSuggestions.clear() } } }
    var searchText = "" { didSet { refreshHistorySuggestions(); refreshRemoteSuggestions() } }
    var historySuggestions: [HistoryVisit] = []
    /// The search engine's suggestions for `searchText`.
    let remoteSuggestions = SearchSuggestions()
    var sheet: Sheet?
    var showOnboarding = false
    var toast: Toast?
    var hinge: DeviceHinge?
    var isIncognito = false
    private(set) var incognitoTabs: [SidebarItem] = []
    /// Last rendered image of each tab, shown on its card. Saved in Caches (`SnapshotCache`), except private tabs'.
    var snapshots: [String: UIImage] = [:]
    /// The folded layout's tab carousel of Today tabs, over the page or the home screen.
    var showsCoverFlow = false
    /// Counts requests to open the carousel, so one made while it is still closing brings it back.
    private(set) var coverFlowRequests = 0
    /// The page's settings panel, from the rail's "…" (the search panel is `searchTarget`; one panel at a time).
    var showsPageSettings = false
    /// Each tab's page colors along the viewport's edges, which the screen edges and chrome take on.
    private(set) var siteEdges: [String: SiteEdges] = [:]
    /// Bumped on every edge-swipe back/forward commit; `TabBrowser` fires a haptic off it.
    var backForwardHaptic = 0

    // Caches touched while views render; observing them would re-render in a loop.
    @ObservationIgnored private var pages: [String: WebPage] = [:]
    @ObservationIgnored private var pageRecency: [String] = []
    @ObservationIgnored private(set) var store: BoazStore?
    /// iCloud sync with the user's other devices (a picked folder only when iCloud isn't available).
    @ObservationIgnored private(set) var sync: LibrarySync?
    /// Compiled once at launch; `nil` until ready, so the very first page or two may load unblocked.
    @ObservationIgnored private var contentBlockLists: [WKContentRuleList] = []
    /// Runs once the current sheet has finished dismissing (a tab can't present while a sheet is leaving).
    @ObservationIgnored private var afterSheet: (() -> Void)?
    private let maxLivePages = 8
    /// This iPhone, in the device list: Today shows only the tabs opened here (see `SidebarItem.deviceID`).
    let deviceID = Device.localID(in: UserDefaults(suiteName: BoazStore.appGroup) ?? .standard)
    /// Archived by closing, newest last; observed so the More menu's Reopen Closed Tab stays current.
    private var closedTabs: [(tab: SidebarItem, archiveID: String?)] = []
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
        Task { contentBlockLists = await ContentBlocking.compiledLists() }
        do {
            let sync = try prepareSync()
            guard let store = self.store else { return }
            // A device joining an existing library gets it from there; a lone device starts with a Personal space.
            if try store.isEmpty() {
                // Welcome goes up at once; the library (joined or starter) lands behind it.
                showOnboarding = Onboarding.shouldShow(store)
                await sync.start()
            }
            try StarterLibrary.seedIfEmpty(store)
            showOnboarding = showOnboarding || Onboarding.shouldShow(store)
            Task { await restoreSnapshots(from: store) }
            Task { await sync.start() }
            archiveStaleTabs()
            registerDevice()
            for try await snapshot in store.sidebarUpdates() {
                sidebar = snapshot
                sidebarGeneration += 1
                // Also how the stale-tab sweep's archived tabs lose their previews: the sweep lands as an update.
                pruneSnapshots()
                if currentSpace == nil { currentSpaceID = snapshot.spaces.first?.id }
            }
        } catch {
            Self.log.error("Opening the library failed: \(String(describing: error))")
            showToast("Couldn't open your library. Try reopening Boaz.")
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

    /// Picks up rows the share extension wrote while the app was away: the live observation only sees this
    /// process's own commits. A snapshot the observation delivers meanwhile is newer, so this one is dropped.
    func reloadSidebar() {
        guard let store else { return }
        let generation = sidebarGeneration
        Task {
            guard let fresh = try? await store.loadSidebar(), generation == sidebarGeneration else { return }
            sidebar = fresh
            pruneSnapshots()
        }
    }

    /// Moves Today tabs untouched for the chosen interval into the archive, as Arc does.
    func archiveStaleTabs() {
        let interval = Preferences.archiveAfter
        guard interval != .never, let store else { return }
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
        guard let ids = try? await store.loadSidebar().items.map(\.id) else { return }
        let saved = await SnapshotCache.load(keeping: Set(ids))
        snapshots.merge(saved) { live, _ in live }
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

    var spaces: [Space] { sidebar.spaces }
    var currentSpace: Space? { sidebar.spaces.first { $0.id == currentSpaceID } }
    var activeTab: SidebarItem? {
        activeTabID.flatMap { id in sidebar.items.first { $0.id == id } ?? incognitoTabs.first { $0.id == id } }
    }
    var isDeskPosture: Bool { hinge?.status == .partiallyOpen }

    func todayTabs(in space: Space) -> [SidebarItem] { sidebar.todayTabs(in: space.id, onDevice: deviceID) }

    func pinnedItems(in space: Space) -> [SidebarItem] {
        guard let box = sidebar.container(.pinned, in: space.id) else { return [] }
        return sidebar.children(of: box.id)
    }

    func favorites(for space: Space) -> [SidebarItem] { sidebar.favorites(profileID: space.profileID) }

    func isPinned(_ tab: SidebarItem) -> Bool {
        guard let parent = tab.parentID, !isPrivate(tab) else { return false }
        return ancestorContainer(of: parent)?.containerKind != .unpinned
    }

    func isPrivate(_ tab: SidebarItem) -> Bool { tab.parentID == Self.incognitoParent }

    // MARK: Pages

    func page(for tab: SidebarItem) -> WebPage {
        pageRecency.removeAll { $0 == tab.id }
        pageRecency.append(tab.id)
        if let page = pages[tab.id] { return page }
        let tabIsPrivate = isPrivate(tab)
        var configuration = WebPage.Configuration()
        if tabIsPrivate { configuration.websiteDataStore = .nonPersistent() }
        if Preferences.blockTrackers, PageSettings.settings(for: tab.url, isPrivate: tabIsPrivate).contentBlocking {
            contentBlockLists.forEach(configuration.userContentController.add)
        }
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
            onDownload: { [weak self] response in
                self?.discardIfDownloadOnly(tab.id)
                self?.handleDownload(response, dataStore: dataStore)
            })
        let page = WebPage(configuration: configuration, navigationDecider: decider)
        page.customUserAgent = PageSettings.userAgent(forHost: tab.url?.host(), isPrivate: tabIsPrivate)
        if let url = tab.url { page.load(URLRequest(url: url)) }
        pages[tab.id] = page
        while pageRecency.count > maxLivePages {
            pages[pageRecency.removeFirst()] = nil
        }
        return page
    }

    /// Called by `TabBrowser`'s single `page.navigations` subscriber on every finished load — the
    /// async sequence only supports one consumer, so AppModel never subscribes to it directly.
    func pageDidFinishLoading(_ tab: SidebarItem) {
        guard let page = pages[tab.id] else { return }
        let tabIsPrivate = isPrivate(tab)
        captureSnapshot(of: page, tab: tab)
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

    /// Downscaled render of a tab's current page, dropped when the tab closes.
    private func captureSnapshot(of page: WebPage, tab: SidebarItem) {
        let persist = !isPrivate(tab)
        Task { [weak self] in
            guard let data = try? await page.exported(as: .image(snapshotWidth: 400)),
                  let image = UIImage(data: data),
                  // The tab may have closed while the page rendered.
                  let self, self.isLive(tab.id) else { return }
            self.snapshots[tab.id] = image
            if persist { SnapshotCache.save(data, for: tab.id) }
        }
    }

    private func isLive(_ tabID: String) -> Bool {
        sidebar.items.contains { $0.id == tabID } || incognitoTabs.contains { $0.id == tabID }
    }

    /// Forgets the previews of tabs that are gone: archived by the stale-tab sweep, or closed on another device.
    private func pruneSnapshots() {
        for id in snapshots.keys where !isLive(id) {
            snapshots[id] = nil
            SnapshotCache.remove(id)
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
        pages[tabID] = nil
        pageRecency.removeAll { $0 == tabID }
        snapshots[tabID] = nil
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
                let (_, name) = try await Downloads.save(response, cookieStore: dataStore.httpCookieStore)
                self?.showToast("Downloaded \(name)")
            } catch {
                Self.log.error("Download failed: \(String(describing: error))")
                self?.showToast("Couldn't download the file. Try again.")
            }
        }
    }

    /// Persists where a tab has navigated to, and records the visit in history (except private tabs).
    func didNavigate(_ tab: SidebarItem, url: URL?, title: String) {
        guard var item = sidebar.items.first(where: { $0.id == tab.id }) ?? incognitoTabs.first(where: { $0.id == tab.id })
        else { return }
        // A pinned tab keeps its saved address and title; only Today tabs follow the page.
        let pinned = isPinned(item)
        let newURL = pinned ? item.url : url ?? item.url
        let newTitle = title.isEmpty || (pinned && item.title != nil) ? item.title : title
        if item.url != newURL || item.title != newTitle {
            item.url = newURL
            item.title = newTitle
            commit(item)
        }
        if !isPrivate(item), let url, url.scheme?.hasPrefix("http") == true {
            try? store?.recordVisit(profileID: item.profileID, url: url, title: title.isEmpty ? newTitle : title)
        }
    }

    // MARK: Actions

    func beginSearch(_ target: SearchTarget) {
        searchText = target == .currentTab ? (activeTab?.url?.absoluteString ?? "") : ""
        searchTarget = target
        if asksSearchEngine { remoteSuggestions.warm(Preferences.searchEngine) }
    }

    func submitSearch() {
        defer { searchTarget = nil }
        guard let url = SearchInput.url(for: searchText, searchTemplate: Preferences.searchEngine.template) else { return }
        if searchTarget == .currentTab, let tab = activeTab {
            page(for: tab).load(URLRequest(url: url))
        } else {
            openNewTab(url)
        }
    }

    func openNewTab(_ url: URL, title: String? = nil) {
        searchTarget = nil
        if isIncognito {
            let tab = SidebarItem(id: UUID().uuidString, spaceID: nil, profileID: "incognito",
                                  parentID: Self.incognitoParent, kind: .tab, title: title ?? url.host(), url: url,
                                  position: Double(incognitoTabs.count), lastActiveAt: .now)
            incognitoTabs.append(tab)
            activeTabID = tab.id
            return
        }
        guard let space = currentSpace, let box = sidebar.container(.unpinned, in: space.id) else { return }
        let tab = SidebarItem(id: UUID().uuidString, spaceID: space.id, profileID: space.profileID, parentID: box.id,
                              kind: .tab, title: title ?? url.host(), url: url,
                              position: sidebar.nextPosition(in: box.id), lastActiveAt: .now, deviceID: deviceID)
        commit(tab)
        activate(tab)
    }

    func activate(_ tab: SidebarItem) {
        guard tab.kind == .tab else { return }
        searchTarget = nil
        if let previous = activeTab, previous.id != tab.id, let page = pages[previous.id] {
            captureSnapshot(of: page, tab: previous)
        }
        var item = tab
        item.lastActiveAt = .now
        item.isUnread = false
        commit(item)
        if let space = tab.spaceID { currentSpaceID = space }
        activeTabID = tab.id
    }

    func goHome() {
        if let tab = activeTab, let page = pages[tab.id] { captureSnapshot(of: page, tab: tab) }
        showsPageSettings = false
        activeTabID = nil
    }

    func openCoverFlow() {
        // The page's card should show it as it is now, not as it first loaded.
        if let tab = activeTab, let page = pages[tab.id] { captureSnapshot(of: page, tab: tab) }
        showsPageSettings = false
        searchTarget = nil
        showsCoverFlow = true
        coverFlowRequests += 1
    }

    /// Closing sends a tab to the archive (like Arc); undo brings it back and removes the archive entry.
    func close(_ tab: SidebarItem) {
        if activeTabID == tab.id { activeTabID = neighbor(of: tab)?.id }
        pages[tab.id] = nil
        pageRecency.removeAll { $0 == tab.id }
        snapshots[tab.id] = nil
        SnapshotCache.remove(tab.id)
        if isPrivate(tab) {
            incognitoTabs.removeAll { $0.id == tab.id }
            return
        }
        var removed = tab
        removed.deletedAt = .now
        sidebar.upsert(removed)
        do {
            let archived = try store?.archive(tab, reason: "closed")
            closedTabs.append((tab, archived?.id))
            showToast("Tab archived", canUndo: true)
        } catch {
            Self.log.error("Archiving a tab failed: \(String(describing: error))")
            showToast("Couldn't archive the tab. Try again.")
        }
    }

    var canReopenClosedTab: Bool { !closedTabs.isEmpty }

    func undoClose() {
        guard let (tab, archiveID) = closedTabs.popLast() else { return }
        var restored = tab
        restored.deletedAt = nil
        commit(restored)
        if let archiveID { try? store?.removeFromArchive(archiveID) }
        showToast("Tab restored")
    }

    func restore(_ item: ArchiveItem) {
        try? store?.removeFromArchive(item.id)
        if let space = item.spaceID, sidebar.spaces.contains(where: { $0.id == space }) { currentSpaceID = space }
        openAfterSheet(item.url, title: item.title)
    }

    func openAfterSheet(_ url: URL, title: String?) {
        afterSheet = { [weak self] in self?.openNewTab(url, title: title) }
        sheet = nil
    }

    func sheetDidDismiss() {
        afterSheet?()
        afterSheet = nil
    }

    func togglePin(_ tab: SidebarItem) {
        guard let space = tab.spaceID.flatMap({ id in sidebar.spaces.first { $0.id == id } }),
              let target = sidebar.container(isPinned(tab) ? .unpinned : .pinned, in: space.id) else { return }
        var item = tab
        // Unpinning keeps the tab where its page is now, not where it was pinned.
        if isPinned(tab), let page = pages[tab.id], let url = page.url {
            item.url = url
            if !page.title.isEmpty { item.title = page.title }
        }
        item.parentID = target.id
        item.position = sidebar.nextPosition(in: target.id)
        // Pinned tabs are every device's; an unpinned one joins this iPhone's Today.
        item.deviceID = isPinned(tab) ? deviceID : nil
        commit(item)
        showToast(isPinned(item) ? "Pinned" : "Unpinned")
    }

    func isFavorite(_ tab: SidebarItem) -> Bool {
        guard let parent = tab.parentID, !isPrivate(tab) else { return false }
        return ancestorContainer(of: parent)?.containerKind == .favorites
    }

    /// Moves a tab into this profile's Favorites, as the page settings menu's "Add to Favorites" does.
    func addToFavorites(_ tab: SidebarItem) {
        guard let box = sidebar.favoritesContainer(profileID: tab.profileID) else { return }
        var item = tab
        item.parentID = box.id
        item.position = sidebar.nextPosition(in: box.id)
        commit(item)
        showToast("Added to Favorites")
    }

    /// Whether a pinned tab's page has browsed away from where it was pinned.
    func hasWandered(_ tab: SidebarItem) -> Bool {
        guard isPinned(tab), let page = pages[tab.id] else { return false }
        return PinnedAnchor.hasWandered(page, from: tab.url)
    }

    func returnToPinnedPage(_ tab: SidebarItem) {
        guard let url = tab.url else { return }
        page(for: tab).load(URLRequest(url: url))
    }

    func toggleExpanded(_ folder: SidebarItem) {
        var item = folder
        item.isExpanded.toggle()
        commit(item)
    }

    func setIncognito(_ on: Bool) {
        guard on != isIncognito else { return }
        if !on {
            for tab in incognitoTabs { pages[tab.id] = nil }
            pageRecency.removeAll { id in incognitoTabs.contains { $0.id == id } }
            incognitoTabs = []
            PageSettings.forgetPrivateChoices()
            PageZoom.forgetPrivateLevels()
            if let id = activeTabID, sidebar.items.first(where: { $0.id == id }) == nil { activeTabID = nil }
        }
        isIncognito = on
        showToast(on ? "Incognito on" : "Incognito off — private tabs closed")
    }

    /// Moves to the previous (-1) or next (+1) tab in the active tab's list. Returns false at the ends.
    @discardableResult
    func pageTab(by offset: Int) -> Bool {
        guard let tab = activeTab else { return false }
        let siblings = siblings(of: tab)
        guard let index = siblings.firstIndex(where: { $0.id == tab.id }),
              siblings.indices.contains(index + offset) else { return false }
        activate(siblings[index + offset])
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
        do {
            try store?.save([item])
        } catch {
            Self.log.error("Saving a sidebar item failed: \(String(describing: error))")
            showToast("Couldn't save. Try again.")
        }
    }

    private func refreshHistorySuggestions() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        historySuggestions = searchTarget == .newTab && !isIncognito && query.count > 1
            ? (try? store?.historySuggestions(matching: query, limit: 4)) ?? [] : []
    }

    /// Whether typing may be sent to the search engine for suggestions: never in private browsing.
    var asksSearchEngine: Bool {
        searchTarget != nil && Preferences.searchSuggestions && !isIncognito && activeTab.map(isPrivate) != true
    }

    private func refreshRemoteSuggestions() {
        guard asksSearchEngine, !SearchSuggestions.looksLikeAddress(searchText) else { return remoteSuggestions.clear() }
        remoteSuggestions.update(searchText, engine: Preferences.searchEngine)
    }

    /// The tabs listed alongside `tab`; another device's Today tabs aren't listed here.
    private func siblings(of tab: SidebarItem) -> [SidebarItem] {
        isPrivate(tab) ? incognitoTabs : sidebar.children(of: tab.parentID ?? "").filter {
            $0.kind == .tab && ($0.deviceID == nil || $0.deviceID == deviceID)
        }
    }

    private func neighbor(of tab: SidebarItem) -> SidebarItem? {
        let siblings = siblings(of: tab)
        guard let index = siblings.firstIndex(where: { $0.id == tab.id }) else { return nil }
        return siblings.indices.contains(index + 1) ? siblings[index + 1]
            : siblings.indices.contains(index - 1) ? siblings[index - 1] : nil
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
