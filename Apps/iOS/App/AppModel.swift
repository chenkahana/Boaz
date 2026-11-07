import FolioKit
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
    var currentSpaceID: String?
    var activeTabID: String?
    var searchTarget: SearchTarget?
    var searchText = "" { didSet { refreshHistorySuggestions() } }
    var historySuggestions: [HistoryVisit] = []
    var sheet: Sheet?
    var toast: Toast?
    var hinge: DeviceHinge?
    var isIncognito = false
    private(set) var incognitoTabs: [SidebarItem] = []

    // Caches touched while views render; observing them would re-render in a loop.
    @ObservationIgnored private var pages: [String: WebPage] = [:]
    @ObservationIgnored private var pageRecency: [String] = []
    @ObservationIgnored private var closedTabs: [(tab: SidebarItem, archiveID: String?)] = []
    @ObservationIgnored private(set) var store: FolioStore?
    /// Runs once the current sheet has finished dismissing (a tab can't present while a sheet is leaving).
    @ObservationIgnored private var afterSheet: (() -> Void)?
    private let maxLivePages = 8

    init() {
        UserDefaults.standard.register(defaults: [
            Preferences.archiveAfterKey: ArchiveInterval.day.rawValue,
            Preferences.searchEngineKey: SearchEngine.duckDuckGo.rawValue,
        ])
    }

    // MARK: Lifecycle

    func start() async {
        do {
            let store = try FolioStore.onDisk()
            self.store = store
            #if DEBUG
            if try store.isEmpty() { try SampleData.seed(store) }
            #endif
            archiveStaleTabs()
            for try await snapshot in store.sidebarUpdates() {
                sidebar = snapshot
                if currentSpace == nil { currentSpaceID = snapshot.spaces.first?.id }
            }
        } catch {
            showToast("Couldn't open library: \(error.localizedDescription)")
        }
    }

    /// Moves Today tabs untouched for the chosen interval into the archive, as Arc does.
    func archiveStaleTabs() {
        let interval = Preferences.archiveAfter
        guard interval != .never, let store else { return }
        do {
            let count = try store.archiveStaleTabs(olderThan: TimeInterval(interval.rawValue))
            if count > 0 { showToast("Archived \(count) inactive tab\(count == 1 ? "" : "s")") }
        } catch {
            showToast("Couldn't archive tabs: \(error.localizedDescription)")
        }
    }

    // MARK: Reads

    var spaces: [Space] { sidebar.spaces }
    var currentSpace: Space? { sidebar.spaces.first { $0.id == currentSpaceID } }
    var activeTab: SidebarItem? {
        activeTabID.flatMap { id in sidebar.items.first { $0.id == id } ?? incognitoTabs.first { $0.id == id } }
    }
    var isDeskPosture: Bool { hinge?.status == .partiallyOpen }

    func todayTabs(in space: Space) -> [SidebarItem] {
        guard let box = sidebar.container(.unpinned, in: space.id) else { return [] }
        return sidebar.children(of: box.id).filter { $0.kind == .tab }
    }

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
        var configuration = WebPage.Configuration()
        if isPrivate(tab) { configuration.websiteDataStore = .nonPersistent() }
        let page = WebPage(configuration: configuration)
        if let url = tab.url { page.load(URLRequest(url: url)) }
        pages[tab.id] = page
        while pageRecency.count > maxLivePages {
            pages[pageRecency.removeFirst()] = nil
        }
        return page
    }

    /// Persists where a tab has navigated to, and records the visit in history (except private tabs).
    func didNavigate(_ tab: SidebarItem, url: URL?, title: String) {
        guard var item = sidebar.items.first(where: { $0.id == tab.id }) ?? incognitoTabs.first(where: { $0.id == tab.id })
        else { return }
        let newTitle = title.isEmpty ? item.title : title
        if item.url != url || item.title != newTitle {
            if let url { item.url = url }
            item.title = newTitle
            commit(item)
        }
        if !isPrivate(item), let url, url.scheme?.hasPrefix("http") == true {
            try? store?.recordVisit(profileID: item.profileID, url: url, title: newTitle)
        }
    }

    // MARK: Actions

    func beginSearch(_ target: SearchTarget) {
        searchText = target == .currentTab ? (activeTab?.url?.absoluteString ?? "") : ""
        searchTarget = target
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
                              position: sidebar.nextPosition(in: box.id), lastActiveAt: .now)
        commit(tab)
        activate(tab)
    }

    func activate(_ tab: SidebarItem) {
        guard tab.kind == .tab else { return }
        searchTarget = nil
        var item = tab
        item.lastActiveAt = .now
        item.isUnread = false
        commit(item)
        if let space = tab.spaceID { currentSpaceID = space }
        activeTabID = tab.id
    }

    func goHome() { activeTabID = nil }

    /// Closing sends a tab to the archive (like Arc); undo brings it back and removes the archive entry.
    func close(_ tab: SidebarItem) {
        if activeTabID == tab.id { activeTabID = neighbor(of: tab)?.id }
        pages[tab.id] = nil
        pageRecency.removeAll { $0 == tab.id }
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
            showToast("Tab closed", canUndo: true)
        } catch {
            showToast("Couldn't close tab: \(error.localizedDescription)")
        }
    }

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
        item.parentID = target.id
        item.position = sidebar.nextPosition(in: target.id)
        commit(item)
        showToast(isPinned(item) ? "Pinned" : "Unpinned")
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
            if let id = activeTabID, sidebar.items.first(where: { $0.id == id }) == nil { activeTabID = nil }
        }
        isIncognito = on
        showToast(on ? "Incognito on" : "Incognito off — private tabs closed")
    }

    /// Moves to the previous (-1) or next (+1) tab in the active tab's list. Returns false at the ends.
    @discardableResult
    func pageTab(by offset: Int) -> Bool {
        guard let tab = activeTab else { return false }
        let siblings = isPrivate(tab) ? incognitoTabs
            : sidebar.children(of: tab.parentID ?? "").filter { $0.kind == .tab }
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
        do { try store?.save([item]) } catch { showToast("Couldn't save: \(error.localizedDescription)") }
    }

    private func refreshHistorySuggestions() {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        historySuggestions = searchTarget == .newTab && !isIncognito && query.count > 1
            ? (try? store?.historySuggestions(matching: query, limit: 4)) ?? [] : []
    }

    private func neighbor(of tab: SidebarItem) -> SidebarItem? {
        let siblings = isPrivate(tab) ? incognitoTabs
            : sidebar.children(of: tab.parentID ?? "").filter { $0.kind == .tab }
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
        Task {
            try? await Task.sleep(for: .seconds(canUndo ? 5 : 2.5))
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

    static var archiveAfter: ArchiveInterval {
        ArchiveInterval(rawValue: UserDefaults.standard.integer(forKey: archiveAfterKey)) ?? .day
    }
    static var searchEngine: SearchEngine {
        SearchEngine(rawValue: UserDefaults.standard.string(forKey: searchEngineKey) ?? "") ?? .duckDuckGo
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("FolioDeviceDidShake")
}

extension UIWindow {
    override open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .deviceDidShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}
