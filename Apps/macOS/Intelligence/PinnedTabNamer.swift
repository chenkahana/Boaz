import BoazKit
import Foundation

/// Gives each tab that joins Pinned a short name with the on-device model, as Tidy Titles does, without asking: a tab
/// pinned or dragged there, or a pull request a live folder adds. Only a title still the one it arrived with is
/// replaced, so a tab the user renames meanwhile keeps their name.
final class PinnedTabNamer {
    static let shared = PinnedTabNamer()

    private weak var model: MacModel?
    private var queued: [String] = []
    /// Tabs pinned before their page had a title; named once it arrives.
    private var awaitingTitle: Set<String> = []
    private var worker: Task<Void, Never>?
    /// What one request holds and still leaves the model's 4096-token context room for its answer.
    private static let batchSize = 15

    func start(_ model: MacModel) { self.model = model }

    private var isEnabled: Bool {
        !UITestMode.isActive && (UserDefaults.standard.object(forKey: AIFeatures.preferenceKey) as? Bool ?? true)
            && AIFeatures.status == .available
    }

    /// Queues the tabs of a commit that weren't in Pinned before it (`wasPinned`) and are now, with those inside a
    /// folder that joined, and pinned tabs whose first title just arrived.
    func committed(_ items: [SidebarItem], wasPinned: Set<String>) {
        guard let model else { return }
        func tabs(in folder: SidebarItem) -> [SidebarItem] {
            model.sidebar.children(of: folder.id).flatMap { $0.kind == .folder ? tabs(in: $0) : [$0] }
        }
        var candidates: [SidebarItem] = []
        for item in items where item.deletedAt == nil {
            if item.kind == .folder, !wasPinned.contains(item.id), model.isInPinned(item) {
                candidates += tabs(in: item)
            } else if item.kind == .tab {
                candidates.append(item)
            }
        }
        for item in candidates where item.kind == .tab && item.deletedAt == nil {
            let joined = !wasPinned.contains(item.id) && model.isInPinned(item)
            guard joined || awaitingTitle.contains(item.id) else { continue }
            if item.title?.isEmpty ?? true {
                awaitingTitle.insert(item.id)
            } else {
                awaitingTitle.remove(item.id)
                queue([item.id])
            }
        }
    }

    /// Names these tabs again, as after a live folder takes a pull request's new title from GitHub.
    func queue(_ ids: [String]) {
        guard isEnabled, !ids.isEmpty else { return }
        queued.append(contentsOf: ids)
        guard worker == nil else { return }
        worker = Task {
            // One drag or refresh commits in several steps; gather them into one request.
            try? await Task.sleep(for: .milliseconds(300))
            await drain()
            worker = nil
        }
    }

    private func drain() async {
        while !queued.isEmpty {
            var seen = Set<String>()
            let ids = queued.filter { seen.insert($0).inserted }.prefix(Self.batchSize)
            queued.removeAll { ids.contains($0) }
            guard let model else { return }
            let tabs = ids.compactMap(model.item).filter { $0.deletedAt == nil && model.isInPinned($0) && !($0.title?.isEmpty ?? true) }
            guard !tabs.isEmpty, let changes = try? await TabTidier.titles(for: tabs) else { continue }
            let asked = Dictionary(tabs.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
            let renamed = changes.compactMap { change -> SidebarItem? in
                guard var tab = model.item(change.tab.id), tab.deletedAt == nil, tab.title == asked[tab.id] else { return nil }
                tab.title = change.title
                return tab
            }
            if !renamed.isEmpty { model.commit(renamed) }
        }
    }
}
