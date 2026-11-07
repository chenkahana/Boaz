import FolioKit
import SwiftUI
import WebKit

/// App state for every posture. The sidebar comes from the shared store; web pages live here.
@Observable
final class AppModel {
    enum SearchTarget { case newTab, currentTab }
    struct Toast: Equatable { var message: String; var canUndo: Bool }

    var sidebar = Sidebar()
    var currentSpaceID: String?
    var activeTabID: String?
    var searchTarget: SearchTarget?
    var searchText = ""
    var toast: Toast?
    var hinge: DeviceHinge?

    // Caches touched while views render; observing them would re-render in a loop.
    @ObservationIgnored private var pages: [String: WebPage] = [:]
    @ObservationIgnored private var pageRecency: [String] = []
    @ObservationIgnored private var closedTabs: [SidebarItem] = []
    @ObservationIgnored private var store: FolioStore?
    private let maxLivePages = 8

    // MARK: Lifecycle

    func start() async {
        do {
            let store = try FolioStore.onDisk()
            self.store = store
            #if DEBUG
            if try store.isEmpty() { try SampleData.seed(store) }
            #endif
            for try await snapshot in store.sidebarUpdates() {
                sidebar = snapshot
                if currentSpace == nil { currentSpaceID = snapshot.spaces.first?.id }
            }
        } catch {
            showToast("Couldn't open library: \(error.localizedDescription)")
        }
    }

    // MARK: Reads

    var spaces: [Space] { sidebar.spaces }
    var currentSpace: Space? { sidebar.spaces.first { $0.id == currentSpaceID } }
    var activeTab: SidebarItem? { activeTabID.flatMap { id in sidebar.items.first { $0.id == id } } }
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
        guard let parent = tab.parentID else { return false }
        return ancestorContainer(of: parent)?.containerKind != .unpinned
    }

    // MARK: Pages

    func page(for tab: SidebarItem) -> WebPage {
        pageRecency.removeAll { $0 == tab.id }
        pageRecency.append(tab.id)
        if let page = pages[tab.id] { return page }
        let page = WebPage()
        if let url = tab.url { page.load(URLRequest(url: url)) }
        pages[tab.id] = page
        while pageRecency.count > maxLivePages {
            pages[pageRecency.removeFirst()] = nil
        }
        return page
    }

    /// Persists where a tab has navigated to, so the sidebar and sync see the live page.
    func didNavigate(_ tab: SidebarItem, url: URL?, title: String) {
        guard var item = sidebar.items.first(where: { $0.id == tab.id }) else { return }
        let newTitle = title.isEmpty ? item.title : title
        guard item.url != url || item.title != newTitle else { return }
        if let url { item.url = url }
        item.title = newTitle
        commit(item)
    }

    // MARK: Actions

    func beginSearch(_ target: SearchTarget) {
        searchText = target == .currentTab ? (activeTab?.url?.absoluteString ?? "") : ""
        searchTarget = target
    }

    func submitSearch() {
        defer { searchTarget = nil }
        guard let url = SearchInput.url(for: searchText) else { return }
        if searchTarget == .currentTab, let tab = activeTab {
            page(for: tab).load(URLRequest(url: url))
        } else {
            openNewTab(url)
        }
    }

    func openNewTab(_ url: URL) {
        guard let space = currentSpace, let box = sidebar.container(.unpinned, in: space.id) else { return }
        let tab = SidebarItem(id: UUID().uuidString, spaceID: space.id, profileID: space.profileID, parentID: box.id,
                              kind: .tab, title: url.host(), url: url,
                              position: sidebar.nextPosition(in: box.id), lastActiveAt: .now)
        commit(tab)
        activate(tab)
    }

    func activate(_ tab: SidebarItem) {
        guard tab.kind == .tab else { return }
        var item = tab
        item.lastActiveAt = .now
        item.isUnread = false
        commit(item)
        if let space = tab.spaceID { currentSpaceID = space }
        activeTabID = tab.id
    }

    func goHome() { activeTabID = nil }

    func close(_ tab: SidebarItem) {
        if activeTabID == tab.id { activeTabID = neighbor(of: tab)?.id }
        var item = tab
        item.deletedAt = .now
        commit(item)
        closedTabs.append(tab)
        pages[tab.id] = nil
        pageRecency.removeAll { $0 == tab.id }
        showToast("Tab closed", canUndo: true)
    }

    func undoClose() {
        guard var tab = closedTabs.popLast() else { return }
        tab.deletedAt = nil
        tab.modifiedAt = .now
        commit(tab)
        showToast("Tab restored")
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

    /// Moves to the previous (-1) or next (+1) tab in the active tab's list. Returns false at the ends.
    @discardableResult
    func pageTab(by offset: Int) -> Bool {
        guard let tab = activeTab, let parent = tab.parentID else { return false }
        let siblings = sidebar.children(of: parent).filter { $0.kind == .tab }
        guard let index = siblings.firstIndex(where: { $0.id == tab.id }),
              siblings.indices.contains(index + offset) else { return false }
        activate(siblings[index + offset])
        return true
    }

    // MARK: Helpers

    private func commit(_ item: SidebarItem) {
        var item = item
        item.modifiedAt = .now
        sidebar.upsert(item)
        do { try store?.save([item]) } catch { showToast("Couldn't save: \(error.localizedDescription)") }
    }

    private func neighbor(of tab: SidebarItem) -> SidebarItem? {
        guard let parent = tab.parentID else { return nil }
        let siblings = sidebar.children(of: parent).filter { $0.kind == .tab }
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

    private func showToast(_ message: String, canUndo: Bool = false) {
        let toast = Toast(message: message, canUndo: canUndo)
        self.toast = toast
        Task {
            try? await Task.sleep(for: .seconds(canUndo ? 4 : 2))
            if self.toast == toast { self.toast = nil }
        }
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
