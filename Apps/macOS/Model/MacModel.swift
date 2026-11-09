import Accessibility
import AppKit
import FolioKit
import SwiftUI
import WebKit

/// App-wide state shared by every window: the store, the live sidebar snapshot, archive/undo and shortcuts.
/// Per-window state (current space, open pages, split, peek) lives in `BrowserState`.
@Observable
final class MacModel {
    static let shared = MacModel()

    struct Toast: Equatable {
        var id = UUID()
        var message: String
        var canUndo = false
    }

    var sidebar = Sidebar()
    var loadError: String?
    var toast: Toast?
    let keyBindings = KeyBindings()

    @ObservationIgnored private(set) var store: FolioStore?
    /// iCloud sync with the user's other devices (a picked folder only when iCloud isn't available).
    @ObservationIgnored private(set) var sync: LibrarySync?
    @ObservationIgnored weak var lastActiveBrowser: BrowserState?
    @ObservationIgnored private var openWindowAction: OpenWindowAction?
    @ObservationIgnored private var pendingExternalURLs: [URL] = []
    /// A URL waiting for the next main window to appear ("Open in Folio" from Little Folio with no window open).
    @ObservationIgnored var pendingMainURL: URL?
    /// A tab the next main window should show ("Open in New Window").
    @ObservationIgnored var pendingMainTabID: String?
    /// Each entry is one undoable close: a single tab, or every tab from one Clear.
    @ObservationIgnored private var closedTabs: [[(tab: SidebarItem, archiveID: String?)]] = []
    @ObservationIgnored private var dataStores: [UUID: WKWebsiteDataStore] = [:]
    @ObservationIgnored private var contentBlockLists: [WKContentRuleList] = []
    @ObservationIgnored private var themeSaves: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var started = false
    /// First launch: the first main window to appear shows the setup flow.
    @ObservationIgnored var needsOnboarding = false

    init() {
        Preferences.registerDefaults()
    }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        // Compiling EasyList the first time takes a few seconds; the library loads meanwhile.
        Task { contentBlockLists = await ContentBlocking.compiledLists() }
        do {
            let store = try FolioStore.onDisk()
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
            archiveStaleTabs()
            Task { await archiveLoop() }
            Task { await fetchLoop(sync) }
            NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                                   queue: .main) { _ in
                MainActor.assumeIsolated {
                    MacModel.shared.archiveStaleTabs()
                    Task { await sync.syncNow() }
                }
            }
            for try await snapshot in store.sidebarUpdates() { sidebar = snapshot }
        } catch {
            loadError = String(describing: error)
        }
    }

    private func archiveLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30 * 60))
            archiveStaleTabs()
        }
    }

    /// CloudKit pushes can go missing, and a Mac browser can stay frontmost for hours, so the app checks for
    /// changes from other devices every couple of minutes while it's in use.
    private func fetchLoop(_ sync: LibrarySync) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(120))
            if NSApplication.shared.isActive { await sync.syncNow() }
        }
    }

    /// Moves Today tabs untouched for the chosen interval into the archive (same setting as iOS).
    func archiveStaleTabs() {
        let interval = Preferences.archiveAfter
        guard interval != .never, let store else { return }
        Task {
            do {
                let count = try await store.archiveStaleTabs(olderThan: TimeInterval(interval.rawValue))
                if count > 0 { showToast("Archived \(count) inactive tab\(count == 1 ? "" : "s")") }
            } catch {
                showToast("Couldn't archive tabs: \(error.localizedDescription)")
            }
        }
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

    /// Links from other apps open in a Little Folio window, like Little Arc.
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

    func todayTabs(in space: Space) -> [SidebarItem] {
        sidebar.container(.unpinned, in: space.id).map { sidebar.children(of: $0.id).filter { $0.kind == .tab } } ?? []
    }

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
        guard Preferences.blockTrackers else { return }
        contentBlockLists.forEach(configuration.userContentController.add)
    }

    func dataStore(for profileID: String) -> WKWebsiteDataStore {
        guard let profile = sidebar.profiles.first(where: { $0.id == profileID }) else { return .default() }
        if let store = dataStores[profile.dataStoreID] { return store }
        let store = WKWebsiteDataStore(forIdentifier: profile.dataStoreID)
        dataStores[profile.dataStoreID] = store
        return store
    }

    func historySuggestions(_ query: String) -> [HistoryVisit] {
        (try? store?.historySuggestions(matching: query, limit: 6)) ?? []
    }

    // MARK: Tabs

    /// New Today tab at the top of the list, as in Arc.
    @discardableResult
    func newTab(_ url: URL, title: String? = nil, in spaceID: String?) -> SidebarItem? {
        guard let space = space(spaceID) ?? sidebar.spaces.first,
              let box = sidebar.container(.unpinned, in: space.id) else { return nil }
        let top = sidebar.children(of: box.id).map(\.position).min() ?? 1
        let tab = SidebarItem(id: UUID().uuidString, spaceID: space.id, profileID: space.profileID, parentID: box.id,
                              kind: .tab, title: title ?? url.host(), url: url, position: top - 1, lastActiveAt: .now)
        commit(tab)
        return tab
    }

    func markActive(_ tab: SidebarItem) {
        guard var item = item(tab.id) else { return }
        item.lastActiveAt = .now
        item.isUnread = false
        commit(item)
    }

    /// Persists where a tab navigated and records the visit (callers skip private tabs).
    func didNavigate(_ tabID: String, url: URL?, title: String) {
        guard var item = item(tabID) else { return }
        // A pinned or favorite tab keeps its saved address and title; only Today tabs follow the page.
        let pinned = isPinned(item)
        let newURL = pinned ? item.url : url ?? item.url
        let newTitle = title.isEmpty || (pinned && item.title != nil) ? item.title : title
        if item.url != newURL || item.title != newTitle {
            item.url = newURL
            item.title = newTitle
            commit(item)
        }
        if let url, url.scheme?.hasPrefix("http") == true {
            try? store?.recordVisit(profileID: item.profileID, url: url, title: title.isEmpty ? newTitle : title)
        }
    }

    /// Closing a Today tab archives it; ⌘⇧T brings it back.
    func archive(_ tab: SidebarItem, reason: String = "closed", toast: Bool = true) {
        guard let entry = archiveEntry(tab, reason: reason) else { return }
        closedTabs.append([entry])
        if toast { showToast("Tab archived", canUndo: true) }
    }

    private func archiveEntry(_ tab: SidebarItem, reason: String) -> (tab: SidebarItem, archiveID: String?)? {
        var removed = tab
        removed.deletedAt = .now
        sidebar.upsert(removed)
        do {
            let archived = try store?.archive(tab, reason: reason)
            return (tab, archived?.id)
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
        let archived = tabs.compactMap { archiveEntry($0, reason: "cleared") }
        guard !archived.isEmpty else { return }
        commit(folders.map { var folder = $0; folder.deletedAt = .now; return folder })
        closedTabs.append(archived + folders.map { (tab: $0, archiveID: nil) })
        showToast("Archived \(archived.count) tab\(archived.count == 1 ? "" : "s")", canUndo: true)
    }

    /// Restores the last close (all of a Clear's tabs) and returns the first restored tab.
    func reopenClosedTab() -> SidebarItem? {
        guard let batch = closedTabs.popLast() else { return nil }
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


    func update(_ space: Space, save: Bool = true) {
        var space = space
        space.modifiedAt = .now
        if let index = sidebar.spaces.firstIndex(where: { $0.id == space.id }) { sidebar.spaces[index] = space }
        guard save else { return }
        do { try store?.save([space]) } catch { showToast("Couldn't save: \(error.localizedDescription)") }
    }

    /// Live theme edit: updates the in-memory space at once, writes to the store after a short pause.
    func setThemeColor(_ color: NSColor, role: ThemeJSON.Role, of spaceID: String) {
        guard var space = space(spaceID) else { return }
        space.themeJSON = ThemeJSON.setting(color, role: role, in: space.themeJSON)
        update(space, save: false)
        themeSaves[spaceID]?.cancel()
        themeSaves[spaceID] = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let latest = self.space(spaceID) else { return }
            try? self.store?.save([latest])
        }
    }

    // MARK: Helpers

    func commit(_ item: SidebarItem) { commit([item]) }

    func commit(_ items: [SidebarItem]) {
        let items = items.map { var item = $0; item.modifiedAt = .now; return item }
        for item in items { sidebar.upsert(item) }
        do { try store?.save(items) } catch { showToast("Couldn't save: \(error.localizedDescription)") }
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

/// Edits Arc `windowTheme` JSON in place, keeping every key Folio doesn't understand.
enum ThemeJSON {
    enum Role: CaseIterable, Identifiable {
        case backgroundLight, backgroundDark, accent
        var id: Self { self }
        var label: String {
            switch self {
            case .backgroundLight: "Background (Light)"
            case .backgroundDark: "Background (Dark)"
            case .accent: "Accent"
            }
        }
        var path: [String] {
            switch self {
            case .backgroundLight: ["semanticColorPalette", "appearanceBased", "light", "background"]
            case .backgroundDark: ["semanticColorPalette", "appearanceBased", "dark", "background"]
            case .accent: ["primaryColorPalette", "midTone"]
            }
        }
    }

    static func setting(_ color: NSColor, role: Role, in json: Data?) -> Data {
        let root = json.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let rgb = color.usingColorSpace(.extendedSRGB) ?? color
        let value: [String: Any] = ["colorSpace": "extendedSRGB", "red": rgb.redComponent, "green": rgb.greenComponent,
                                    "blue": rgb.blueComponent, "alpha": rgb.alphaComponent]
        let updated = set(value, at: role.path[...], in: root)
        return (try? JSONSerialization.data(withJSONObject: updated, options: [.sortedKeys])) ?? (json ?? Data())
    }

    private static func set(_ value: Any, at path: ArraySlice<String>, in object: [String: Any]) -> [String: Any] {
        guard let key = path.first else { return object }
        var object = object
        object[key] = path.count == 1 ? value : set(value, at: path.dropFirst(), in: object[key] as? [String: Any] ?? [:])
        return object
    }
}
