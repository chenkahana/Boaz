import Accessibility
import AppKit
import BoazKit
import OSLog
import SwiftUI
import SystemConfiguration
import WebKit

/// App-wide state shared by every window: the store, the live sidebar snapshot, archive/undo and shortcuts.
/// Per-window state (current space, open pages, split, peek) lives in `BrowserState`.
@Observable
final class MacModel {
    static let shared = MacModel()
    private static let log = Logger(subsystem: "com.chenkahana.boaz", category: "app")
    /// Data store identifiers of deleted profiles whose site data WebKit hasn't removed yet.
    private static let pendingSiteDataKey = "pendingSiteDataRemovals"

    struct Toast: Equatable {
        var id = UUID()
        var message: String
        var canUndo = false
    }

    var sidebar = Sidebar()
    var loadError: String?
    var toast: Toast?
    let keyBindings = KeyBindings()
    /// This Mac, in the device list: the sidebar's Today shows only the tabs opened here (see `SidebarItem.deviceID`).
    let deviceID = Device.localID(in: .standard)

    @ObservationIgnored private(set) var store: BoazStore?
    /// iCloud sync with the user's other devices (a picked folder only when iCloud isn't available).
    @ObservationIgnored private(set) var sync: LibrarySync?
    @ObservationIgnored weak var lastActiveBrowser: BrowserState?
    @ObservationIgnored private var openWindowAction: OpenWindowAction?
    @ObservationIgnored private var pendingExternalURLs: [URL] = []
    /// A URL waiting for the next main window to appear ("Open in Boaz" from a Quick Window with no window open).
    @ObservationIgnored var pendingMainURL: URL?
    /// The address each tab's current page was recorded at in history, which its later titles name (`didCommitLoad`).
    @ObservationIgnored private var visitURLs: [String: URL] = [:]
    /// A tab the next main window should show ("Open in New Window").
    @ObservationIgnored var pendingMainTabID: String?
    /// Each entry is one undoable close: a single tab, or every tab from one Clear.
    @ObservationIgnored private var closedTabs: [[(tab: SidebarItem, archiveID: String?)]] = []
    @ObservationIgnored private var dataStores: [UUID: WKWebsiteDataStore] = [:]
    /// `nil` until compiled. Pages made before then (the tabs reopened at launch) hold their first load until they
    /// have the lists, so no page loads with its ads.
    @ObservationIgnored private var contentBlockLists: [WKContentRuleList]?
    @ObservationIgnored private var awaitingBlockLists: [(controller: WKUserContentController, load: () -> Void)] = []
    @ObservationIgnored private var started = false
    /// First launch: the first main window to appear shows the setup flow.
    @ObservationIgnored var needsOnboarding = false
    /// The stale-tab sweep waits until the restored windows have their tabs back, which keeps those tabs out of it.
    @ObservationIgnored private var holdsSweeps = true
    @ObservationIgnored private var restoringWindows = 0
    @ObservationIgnored private var browsers: [WeakBrowser] = []
    /// Where each tab's page was last read, which a page loaded again goes back to (`PageState`). Incognito windows
    /// keep their own, in memory.
    @ObservationIgnored let pageStates = PageState.Store.saved()
    @ObservationIgnored private var windowsToRestore = SavedWindow.load()
    @ObservationIgnored private var openedRestoredWindows = false
    /// Set once the app has agreed to quit, so the windows closing on the way out don't count as closed by hand.
    @ObservationIgnored var isQuitting = false

    init() {
        Preferences.registerDefaults()
    }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        // Compiling EasyList the first time takes a few seconds; the library loads meanwhile.
        Task {
            let lists = await ContentBlocking.compiledLists()
            contentBlockLists = lists
            for page in awaitingBlockLists { lists.forEach(page.controller.add); page.load() }
            awaitingBlockLists = []
        }
        let store: BoazStore
        do {
            store = try BoazStore.onDisk()
            self.store = store
            let sync = LibrarySync(store: store)
            self.sync = sync
            // A device joining an existing library gets it from there; a lone device starts with a Personal space.
            var askedEarly = false
            if try store.isEmpty() {
                // Welcome goes up at once; the library (joined or starter) lands behind it.
                needsOnboarding = Onboarding.shouldShow(store)
                askedEarly = true
                await sync.start()
            }
            try StarterLibrary.seedIfEmpty(store)
            if !askedEarly { needsOnboarding = Onboarding.shouldShow(store) }
            Task { await sync.start() }
            registerDevice()
            Task { await archiveLoop() }
            Task { await fetchLoop(sync) }
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                   queue: .main) { _ in
                MainActor.assumeIsolated {
                    MacModel.shared.archiveStaleTabs()
                    MacModel.shared.registerDevice()
                    Task { await sync.syncNow() }
                }
            }
            NotificationCenter.default.addObserver(forName: NSApplication.willResignActiveNotification, object: nil,
                                                   queue: .main) { _ in
                MainActor.assumeIsolated { MacModel.shared.openBrowsers.forEach { $0.rememberPagesInView() } }
            }
        } catch {
            loadError = String(describing: error)
            return
        }
        // Not tied to the window whose task started the app: closing that window would stop the sidebar following
        // the library, and a new space wouldn't show until relaunch.
        Task { await observeSidebar(store) }
    }

    /// Follows the library for the life of the app. Any database error ends an observation, so it starts again,
    /// backing off while the errors persist.
    private func observeSidebar(_ store: BoazStore) async {
        var failures = 0
        var loaded = false
        while !Task.isCancelled {
            do {
                for try await snapshot in store.sidebarUpdates() {
                    failures = 0
                    let removed = sidebar.profiles.filter { old in
                        !snapshot.profiles.contains { $0.id == old.id || $0.dataStoreID == old.dataStoreID }
                    }
                    let removedIDs = Set(removed.map(\.id))
                    // Read before the snapshot: a profile deleted on another device arrives without its tabs.
                    let removedTabs = sidebar.items.filter { removedIDs.contains($0.profileID) }.map(\.id)
                    sidebar = snapshot
                    pageStates.prune(keeping: Set(snapshot.items.map(\.id)))
                    if !removed.isEmpty { closePages(of: removedIDs, tabIDs: removedTabs) }
                    removeSiteData(removed.map(\.dataStoreID))
                    guard !loaded else { continue }
                    loaded = true
                    // What an earlier run couldn't remove, unless sync has since brought its profile back.
                    let live = Set(snapshot.profiles.map(\.dataStoreID))
                    removeSiteData((UserDefaults.standard.stringArray(forKey: Self.pendingSiteDataKey) ?? [])
                        .compactMap(UUID.init).filter { !live.contains($0) })
                    Extensions.shared.loadInstalled()
                    // A launch without a main window (a link to a Quick Window) has nothing to restore.
                    Task {
                        try? await Task.sleep(for: .seconds(10))
                        releaseSweeps()
                    }
                }
                return
            } catch {
                failures += 1
                // Windows waiting for a library that never loaded stop waiting.
                if sidebar.spaces.isEmpty { loadError = String(describing: error) }
                try? await Task.sleep(for: .seconds(min(1 << min(failures, 5), 30)))
            }
        }
    }

    private func archiveLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30 * 60))
            archiveStaleTabs()
        }
    }

    /// CloudKit pushes can go missing, and a Mac browser can stay frontmost for hours, so the app checks for
    /// changes from other devices every couple of minutes while it's in use, or every ten in Low Power Mode.
    private func fetchLoop(_ sync: LibrarySync) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(ProcessInfo.processInfo.isLowPowerModeEnabled ? 600 : 120))
            if NSApplication.shared.isActive { await sync.syncNow() }
        }
    }

    /// Moves Today tabs untouched for the chosen interval into the archive (same setting as iOS).
    func archiveStaleTabs() {
        let interval = Preferences.archiveAfter
        guard interval != .never, !holdsSweeps, let store else { return }
        Task {
            do {
                let count = try await store.archiveStaleTabs(olderThan: TimeInterval(interval.rawValue), onDevice: deviceID)
                if count > 0 { showToast("Archived \(count) inactive tab\(count == 1 ? "" : "s")") }
            } catch {
                showToast("Couldn't archive tabs: \(error.localizedDescription)")
            }
        }
    }

    /// A main window waiting for the library to restore its tab. Windows restored together all wait for it, so
    /// the sweep runs once none is left (a turn later, for one whose task hasn't started yet).
    func beginRestoring() { restoringWindows += 1 }

    func endRestoring() {
        restoringWindows -= 1
        Task {
            await Task.yield()
            // Restored windows still opening haven't begun restoring yet.
            if restoringWindows == 0 && windowsToRestore.isEmpty { releaseSweeps() }
        }
    }

    /// Lets the stale-tab sweep run, once the main windows have restored their tabs (or there was none to restore).
    private func releaseSweeps() {
        guard holdsSweeps else { return }
        holdsSweeps = false
        archiveStaleTabs()
    }

    /// Refreshes this Mac's name and last-seen time, so the iPhone can say which Mac a tab is open on.
    func registerDevice() {
        guard let store else { return }
        let name = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac"
        Task { try? await store.registerDevice(id: deviceID, name: name, platform: .macOS) }
    }

    // MARK: Windows

    func registerOpenWindow(_ action: OpenWindowAction) {
        openWindowAction = action
        guard !pendingExternalURLs.isEmpty else { return }
        let pending = pendingExternalURLs
        pendingExternalURLs = []
        // Outside the view or menu update that registered the action.
        Task { openExternal(pending) }
    }

    /// Links from other apps open in a Quick Window.
    func openExternal(_ urls: [URL]) {
        let urls = urls.filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") && $0.host() != nil }
        guard let openWindowAction else { pendingExternalURLs += urls; return }
        for url in urls { openWindowAction(id: "little", value: url) }
    }

    /// Opens a URL as a Today tab in the most recent main window, creating one if needed.
    func openInMainWindow(_ url: URL, title: String? = nil) {
        if let browser = lastActiveBrowser, !browser.isIncognito, let window = browser.window, window.isVisible {
            browser.openTab(url, title: title)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            pendingMainURL = url
            openWindowAction?(id: "main")
        }
    }

    func openWindow(id: String) { openWindowAction?(id: id) }

    // MARK: Window restoration

    /// macOS only reopens windows itself when "Close windows when quitting an application" is off, and it's on by
    /// default. So the app remembers its main windows and reopens them at launch.
    struct SavedWindow: Codable {
        static let key = "openWindows"
        var spaceID: String?
        var tabID: String?
        var frame: String?
        var minimized: Bool?

        static func load() -> [SavedWindow] {
            guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([SavedWindow].self, from: data)) ?? []
        }
    }

    private struct WeakBrowser { weak var browser: BrowserState? }

    /// The main windows open now (not Incognito).
    var openBrowsers: [BrowserState] { browsers.compactMap(\.browser) }

    func register(_ browser: BrowserState) {
        guard !browser.isIncognito else { return }
        browsers.removeAll { $0.browser == nil || $0.browser === browser }
        browsers.append(WeakBrowser(browser: browser))
    }

    func windowWillClose(_ browser: BrowserState) {
        browsers.removeAll { $0.browser == nil || $0.browser === browser }
        if !isQuitting { saveOpenWindows() }
    }

    /// Saves the open main windows, back to front, for the next launch.
    func saveOpenWindows() {
        // Until every saved window is back, the list on disk is still the one to restore.
        guard windowsToRestore.isEmpty else { return }
        let order = NSApp.orderedWindows
        let depth = { (browser: BrowserState) in order.firstIndex { $0 === browser.window } ?? order.count }
        let windows = browsers.compactMap(\.browser).filter {
            $0.window?.isVisible == true || $0.window?.isMiniaturized == true
        }
        // While quitting, windows already gone would leave nothing to restore; what was saved last stands.
        guard !(isQuitting && windows.isEmpty) else { return }
        let saved = windows.sorted { depth($0) > depth($1) }
            .map { SavedWindow(spaceID: $0.spaceID, tabID: $0.activeTabID, frame: $0.window?.frameDescriptor,
                               minimized: $0.window?.isMiniaturized) }
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: SavedWindow.key)
    }

    /// The window a new main window brings back from the last run, if any. The first to ask opens the rest.
    func claimSavedWindow() -> SavedWindow? {
        guard !windowsToRestore.isEmpty else { return nil }
        let saved = windowsToRestore.removeFirst()
        if !openedRestoredWindows {
            openedRestoredWindows = true
            for _ in windowsToRestore { openWindowAction?(id: "main") }
        }
        return saved
    }

    func openInNewWindow(_ tab: SidebarItem) {
        pendingMainTabID = tab.id
        openWindowAction?(id: "main")
    }

    // MARK: Reads

    func space(_ id: String?) -> Space? { id.flatMap { id in sidebar.spaces.first { $0.id == id } } }
    func item(_ id: String?) -> SidebarItem? { id.flatMap { id in sidebar.items.first { $0.id == id } } }

    func pinnedItems(in space: Space) -> [SidebarItem] {
        sidebar.container(.pinned, in: space.id).map { sidebar.children(of: $0.id) } ?? []
    }

    func todayTabs(in space: Space) -> [SidebarItem] { sidebar.todayTabs(in: space.id, onDevice: deviceID) }

    func favorites(profileID: String?) -> [SidebarItem] {
        guard let profileID = profileID ?? sidebar.profiles.first?.id else { return [] }
        return sidebar.favorites(profileID: profileID)
    }

    /// Tabs in sidebar order: favorites, pinned (inside expanded folders), then Today.
    func visibleTabs(in space: Space) -> [SidebarItem] {
        func flatten(_ items: [SidebarItem]) -> [SidebarItem] {
            items.flatMap { item -> [SidebarItem] in
                switch item.kind {
                case .tab: [item]
                case .folder: item.isExpanded ? flatten(sidebar.children(of: item.id)) : []
                case .container: []
                }
            }
        }
        return favorites(profileID: space.profileID) + flatten(pinnedItems(in: space)) + todayTabs(in: space)
    }

    /// Every tab under a space's pinned container, including collapsed folders.
    func allPinnedTabs(in space: Space) -> [SidebarItem] {
        func flatten(_ parent: String) -> [SidebarItem] {
            sidebar.children(of: parent).flatMap { $0.kind == .folder ? flatten($0.id) : [$0] }
        }
        return sidebar.container(.pinned, in: space.id).map { flatten($0.id) } ?? []
    }

    func container(of item: SidebarItem) -> SidebarItem? {
        var current: SidebarItem? = item
        while let node = current, node.kind != .container { current = self.item(node.parentID) }
        return current
    }

    func isPinned(_ tab: SidebarItem) -> Bool { container(of: tab).map { $0.containerKind != .unpinned } ?? false }
    func isFavorite(_ tab: SidebarItem) -> Bool { container(of: tab)?.containerKind == .favorites }

    /// Ad and tracker blocking for a new page, when it's on.
    func applyContentBlocking(to configuration: inout WebPage.Configuration) {
        guard Preferences.blockTrackers, let contentBlockLists else { return }
        contentBlockLists.forEach(configuration.userContentController.add)
    }

    /// A new page's first load, held until the page has its block lists if they're still compiling.
    /// `onFailure` hears why this load failed, if it does.
    func load(_ url: URL, in page: WebPage, configuration: WebPage.Configuration,
              onFailure: ((LoadFailure) -> Void)? = nil) {
        let start = { (page: WebPage) in
            let load = page.load(URLRequest(url: url))
            guard let onFailure else { return }
            Task { if let failure = await LoadFailure.of(load, page: page, url: url) { onFailure(failure) } }
        }
        guard Preferences.blockTrackers, contentBlockLists == nil else {
            start(page)
            return
        }
        awaitingBlockLists.append((configuration.userContentController, { [weak page] in
            // Unless the page went somewhere else in the meantime.
            if let page, page.url == nil { start(page) }
        }))
    }

    func dataStore(for profileID: String) -> WKWebsiteDataStore {
        guard let profile = sidebar.profiles.first(where: { $0.id == profileID }) else { return .default() }
        if let store = dataStores[profile.dataStoreID] { return store }
        let store = WKWebsiteDataStore(forIdentifier: profile.dataStoreID)
        dataStores[profile.dataStoreID] = store
        return store
    }

    func historySuggestions(_ query: String) async -> [HistoryVisit] {
        guard let store else { return [] }
        return (try? await store.historySuggestions(matching: query, limit: 6)) ?? []
    }

    // MARK: Tabs

    /// New Today tab at the top of the list, as in Arc, or right below `source` when that's a Today tab.
    @discardableResult
    func newTab(_ url: URL, title: String? = nil, in spaceID: String?, below source: SidebarItem? = nil) -> SidebarItem? {
        guard let space = space(spaceID) ?? sidebar.spaces.first,
              let box = sidebar.container(.unpinned, in: space.id) else { return nil }
        let positions = sidebar.children(of: box.id).map(\.position)
        let position: Double
        if let source, source.parentID == box.id {
            position = positions.filter { $0 > source.position }.min().map { (source.position + $0) / 2 } ?? source.position + 1
        } else {
            position = (positions.min() ?? 1) - 1
        }
        let tab = SidebarItem(id: UUID().uuidString, spaceID: space.id, profileID: space.profileID, parentID: box.id,
                              kind: .tab, title: title ?? url.host(), url: url, position: position, lastActiveAt: .now,
                              deviceID: deviceID)
        commit(tab)
        return tab
    }

    func markActive(_ tab: SidebarItem) {
        guard var item = item(tab.id) else { return }
        item.lastActiveAt = .now
        item.isUnread = false
        commit(item)
    }

    /// Persists where a tab navigated (callers skip private tabs). In history it only names the visit its load
    /// recorded (`didCommitLoad`).
    func didNavigate(_ tabID: String, url: URL?, title: String) {
        guard var item = item(tabID) else { return }
        // A pinned or favorite tab keeps its saved address and title; only Today tabs follow the page.
        let pinned = isPinned(item)
        // WebKit shows about:blank for a load it refused outright; the tab keeps the address it was asked for.
        let newURL = pinned || url?.absoluteString == "about:blank" ? item.url : url ?? item.url
        // A new page without a title yet doesn't take the previous page's.
        let newTitle = pinned && item.title != nil ? item.title
            : !title.isEmpty ? title : newURL == item.url ? item.title : nil
        if item.url != newURL || item.title != newTitle {
            item.url = newURL
            item.title = newTitle
            commit(item)
        }
        // Only the page the visit was recorded for names it: the address is still the previous page's while the
        // next one loads, and that page's title may arrive before its commit is seen.
        if !title.isEmpty, let url, let visit = visitURLs[tabID], url.isSamePage(as: visit) {
            store?.updateVisitTitle(title, for: visit, profileID: item.profileID)
        }
    }

    /// A tab's page committed a new load: one history visit, at the address the load ended on (callers skip private
    /// tabs). Server redirect hops and same-document address changes (`replaceState`, fragments) never commit, so
    /// none adds a visit.
    func didCommitLoad(_ tabID: String, url: URL?) {
        guard let item = item(tabID), let url, url.scheme?.hasPrefix("http") == true else {
            visitURLs[tabID] = nil
            return
        }
        visitURLs[tabID] = url
        // The title at commit may still be the previous page's; the page's own arrives through `didNavigate`.
        store?.recordVisit(profileID: item.profileID, url: url, title: nil)
    }

    /// A settled page changed address on its own (`pushState`, as single-page sites navigate): a new page in history,
    /// unless only the fragment changed (callers skip private tabs and pages still loading). `replaceState` while a
    /// load is in flight (a search page tidying its address) adds none.
    func didChangeAddress(_ tabID: String, url: URL?, title: String) {
        guard let item = item(tabID), let url, url.scheme?.hasPrefix("http") == true,
              visitURLs[tabID].map({ !url.isSamePage(as: $0) }) ?? true else { return }
        visitURLs[tabID] = url
        store?.recordVisit(profileID: item.profileID, url: url, title: title.isEmpty ? nil : title)
    }

    /// Closing a Today tab archives it; ⌘⇧T brings it back.
    func archive(_ tab: SidebarItem, reason: String = "closed", toast: Bool = true) {
        guard let entry = archiveEntry(tab, reason: reason) else { return }
        closedTabs.append([entry])
        if toast { showToast("Tab archived", canUndo: true) }
    }

    private func archiveEntry(_ tab: SidebarItem, reason: String) -> (tab: SidebarItem, archiveID: String?)? {
        // A second close of the same tab (a double click, say) would archive it twice.
        guard item(tab.id) != nil else { return nil }
        var removed = tab
        removed.deletedAt = .now
        sidebar.upsert(removed)
        do {
            // Undo after the sweep got there first would bring back a tab that is also in the archive.
            guard case .archived(let entry)? = try store?.archive(tab, reason: reason) else { return nil }
            return (tab, entry?.id)
        } catch {
            showToast("Couldn't archive tab: \(error.localizedDescription)")
            return nil
        }
    }

    /// Archives every Today tab as one batch, so Undo brings them all back.
    func clearToday(in space: Space) {
        // Tabs in Today's folders (from Tidy Tabs) go too, and the emptied folders with them; Undo restores both.
        let folders = sidebar.container(.unpinned, in: space.id)
            .map { sidebar.children(of: $0.id).filter { $0.kind == .folder } } ?? []
        let tabs = todayTabs(in: space) + folders.flatMap { sidebar.children(of: $0.id).filter { $0.kind == .tab } }
        guard !tabs.isEmpty, let store else { return }
        let now = Date.now
        let emptied = folders.map { var folder = $0; folder.deletedAt = now; folder.modifiedAt = now; return folder }
        let archived: [ArchiveOutcome]
        do {
            archived = try store.archive(tabs, reason: "cleared", saving: emptied, at: now)
        } catch {
            showToast("Couldn't archive tabs: \(error.localizedDescription)")
            return
        }
        var updated = sidebar
        for item in tabs.map({ var tab = $0; tab.deletedAt = now; return tab }) + emptied { updated.upsert(item) }
        sidebar = updated
        // Tabs the sweep archived first stay archived on Undo.
        let entries = zip(tabs, archived).compactMap { tab, outcome -> (tab: SidebarItem, archiveID: String?)? in
            guard case .archived(let entry) = outcome else { return nil }
            return (tab, entry?.id)
        }
        closedTabs.append(entries + folders.map { (tab: $0, archiveID: nil) })
        showToast("Archived \(tabs.count) tab\(tabs.count == 1 ? "" : "s")", canUndo: true)
    }

    /// Restores the last close (all of a Clear's tabs) and returns the first restored tab.
    func reopenClosedTab() -> SidebarItem? {
        var batch: [(tab: SidebarItem, archiveID: String?)] = []
        // A tab whose space, profile or folder was deleted since stays in the Archive: there's nowhere to put it back.
        while batch.isEmpty, let last = closedTabs.popLast() {
            // A Clear's tabs can sit in its folders, which come back with them.
            let kept = Set(last.filter { item($0.tab.parentID) != nil }.map(\.tab.id))
            batch = last.filter { item($0.tab.parentID) != nil || $0.tab.parentID.map(kept.contains) == true }
        }
        guard !batch.isEmpty else { return nil }
        let restored = batch.map { tab, _ in
            var restored = tab
            restored.deletedAt = nil
            restored.lastActiveAt = .now
            return restored
        }
        commit(restored)
        for case let (_, archiveID?) in batch { try? store?.removeFromArchive(archiveID) }
        return restored.first
    }

    func restore(_ item: ArchiveItem) -> SidebarItem? {
        try? store?.removeFromArchive(item.id)
        return newTab(item.url, title: item.title, in: item.spaceID ?? lastActiveBrowser?.spaceID)
    }

    /// Pinned → Today; Today or Favorites → Pinned.
    func togglePin(_ tab: SidebarItem) {
        let unpinning = isPinned(tab) && !isFavorite(tab)
        guard let spaceID = tab.spaceID ?? lastActiveBrowser?.spaceID,
              let target = sidebar.container(unpinning ? .unpinned : .pinned, in: spaceID) else { return }
        move(tab.id, into: target.id, before: nil)
        showToast(unpinning ? "Unpinned" : "Pinned")
    }

    /// Moves a tab to another space, keeping it pinned or in Today.
    func move(_ tab: SidebarItem, to space: Space) {
        guard let target = sidebar.container(isPinned(tab) ? .pinned : .unpinned, in: space.id) else { return }
        move(tab.id, into: target.id, before: nil)
    }

    func addToFavorites(_ tab: SidebarItem) {
        guard let box = sidebar.favoritesContainer(profileID: tab.profileID) else { return }
        move(tab.id, into: box.id, before: nil)
    }

    func toggleExpanded(_ folder: SidebarItem) {
        var item = folder
        item.isExpanded.toggle()
        commit(item)
    }

    func rename(_ item: SidebarItem, to title: String) {
        var item = item
        item.title = title
        commit(item)
    }

    func newFolder(in space: Space) {
        guard let box = sidebar.container(.pinned, in: space.id) else { return }
        let folder = SidebarItem(id: UUID().uuidString, spaceID: space.id, profileID: space.profileID,
                                 parentID: box.id, kind: .folder, title: "New Folder",
                                 position: sidebar.nextPosition(in: box.id))
        commit(folder)
    }

    /// Moves an item under `parentID`, before `beforeID` (or last). Keeps folders out of favorites and out of
    /// their own subtree, and carries the space across for whole folders.
    func move(_ id: String, into parentID: String, before beforeID: String?) {
        guard id != parentID, id != beforeID, var item = self.item(id), item.kind != .container,
              let parent = self.item(parentID) else { return }
        let targetContainer = container(of: parent)
        if item.kind == .folder, targetContainer?.containerKind == .favorites || isDescendant(parentID, of: id) { return }
        let siblings = sidebar.children(of: parentID).filter { $0.id != id }
        if let beforeID, let index = siblings.firstIndex(where: { $0.id == beforeID }) {
            let next = siblings[index].position
            item.position = index > 0 ? (siblings[index - 1].position + next) / 2 : next - 1
        } else {
            item.position = (siblings.last?.position ?? -1) + 1
        }
        // A tab moved into Today becomes this Mac's; pinned and favorite tabs are every device's.
        if targetContainer?.containerKind != .unpinned {
            item.deviceID = nil
        } else if item.kind == .tab, container(of: item)?.containerKind != .unpinned {
            item.deviceID = deviceID
        }
        item.parentID = parentID
        let spaceID = targetContainer?.containerKind == .favorites ? nil : parent.spaceID
        var changed = [item]
        if item.spaceID != spaceID {
            changed[0].spaceID = spaceID
            if item.kind == .folder { changed += descendants(of: id).map { var d = $0; d.spaceID = spaceID; return d } }
        }
        commit(changed)
    }

    private func descendants(of id: String) -> [SidebarItem] {
        sidebar.children(of: id).flatMap { [$0] + descendants(of: $0.id) }
    }

    private func isDescendant(_ id: String, of ancestor: String) -> Bool {
        var current = item(id)
        while let node = current {
            if node.id == ancestor { return true }
            current = item(node.parentID)
        }
        return false
    }

    // MARK: Spaces

    func isLastSpaceOfProfile(_ space: Space) -> Bool {
        !sidebar.spaces.contains { $0.id != space.id && $0.profileID == space.profileID }
    }

    /// What deleting a space takes with it, for its confirmation.
    func deletionMessage(for space: Space) -> String {
        let tabs = "Its tabs move to the Archive, on all your devices."
        guard isLastSpaceOfProfile(space), let profile = sidebar.profiles.first(where: { $0.id == space.profileID })
        else { return tabs }
        return tabs + " It's the last space of the \(profile.name) profile, so the profile is removed too: its "
            + "favorites move to the Archive, and its site data, like logins and cookies, is deleted."
    }

    /// Deletes a space; windows showing it move to another first. The library keeps at least one space.
    func deleteSpace(_ space: Space) {
        guard let other = sidebar.spaces.first(where: { $0.id != space.id }) else { return }
        let windows = browsers.compactMap(\.browser)
        // Its pages close before any window leaves it, so a video playing there doesn't float as the window moves on.
        let tabIDs = sidebar.items.filter { $0.spaceID == space.id && $0.kind == .tab }.map(\.id)
        for browser in windows { tabIDs.forEach(browser.unload) }
        for browser in windows where browser.spaceID == space.id { browser.switchSpace(to: other.id) }
        do { try store?.deleteSpace(space.id) } catch { showToast("Couldn't delete space: \(error.localizedDescription)") }
    }

    /// WebKit won't delete a data store while a page uses it, so a deleted profile's pages close first: its tabs and
    /// peeks in every window, its extensions, and Quick Windows (which close themselves, `QuickWindow`).
    private func closePages(of profileIDs: Set<String>, tabIDs: [String]) {
        for browser in browsers.compactMap(\.browser) {
            tabIDs.forEach(browser.unload)
            // Tabs another Mac archived in an earlier sync batch already left the sidebar; their pages still hold
            // the profile's data store.
            browser.unloadPagesWithoutTabs()
            if let peek = browser.peek, peek.profileID.map(profileIDs.contains) ?? false { browser.peek = nil }
        }
        Extensions.shared.forget(profileIDs: profileIDs)
    }

    /// A deleted profile's WebKit data on this Mac (logins, cookies, caches), deleted here or on another device.
    /// Recorded first, so what doesn't go now (a download still using it, a quit) goes at next launch.
    private func removeSiteData(_ identifiers: [UUID]) {
        guard !identifiers.isEmpty else { return }
        identifiers.forEach { dataStores[$0] = nil }
        func setPending(_ change: (inout Set<String>) -> Void) {
            var pending = Set(UserDefaults.standard.stringArray(forKey: Self.pendingSiteDataKey) ?? [])
            change(&pending)
            UserDefaults.standard.set(pending.sorted(), forKey: Self.pendingSiteDataKey)
        }
        setPending { $0.formUnion(identifiers.map(\.uuidString)) }
        Task {
            for id in identifiers {
                // Closed pages let go of the store once their views are gone.
                for attempt in 1...5 {
                    do {
                        try await WKWebsiteDataStore.remove(forIdentifier: id)
                        setPending { $0.remove(id.uuidString) }
                        break
                    } catch {
                        guard attempt == 5 else { try? await Task.sleep(for: .seconds(attempt)); continue }
                        Self.log.error("Removing site data \(id) failed; next launch retries: \(String(describing: error))")
                    }
                }
            }
        }
    }

    func update(_ space: Space, save: Bool = true) {
        var space = space
        space.modifiedAt = .now
        if let index = sidebar.spaces.firstIndex(where: { $0.id == space.id }) { sidebar.spaces[index] = space }
        guard save else { return }
        do { try store?.save([space]) } catch { showToast("Couldn't save: \(error.localizedDescription)") }
    }

    // MARK: Helpers

    func commit(_ item: SidebarItem) { commit([item]) }

    func commit(_ items: [SidebarItem]) {
        let items = items.map { var item = $0; item.modifiedAt = .now; return item }
        for item in items { sidebar.upsert(item) }
        // Every tab click and navigation lands here, so the write never holds up the main thread.
        store?.saveInBackground(items) { [weak self] error in self?.showToast("Couldn't save: \(error.localizedDescription)") }
    }

    func showToast(_ message: String, canUndo: Bool = false) {
        let toast = Toast(message: message, canUndo: canUndo)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { self.toast = toast }
        // Toasts are visual only; VoiceOver hears them, and gets longer to reach Undo.
        AccessibilityNotification.Announcement(message).post()
        let voiceOver = NSWorkspace.shared.isVoiceOverEnabled
        Task {
            try? await Task.sleep(for: .seconds(canUndo ? (voiceOver ? 10 : 5) : 2.5))
            if self.toast == toast { withAnimation(.easeOut(duration: 0.25)) { self.toast = nil } }
        }
    }
}
