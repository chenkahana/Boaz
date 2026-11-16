import AppKit
import BoazKit
import Foundation

/// Keeps every live folder's tabs current: each minute (five in Low Power Mode or while the screens sleep), and at
/// once on wake, sign-in, a filter change or Refresh.
///
/// A refresh writes only what changed: new pull requests become tabs, renamed ones are retitled, and closed or merged
/// ones leave, except a tab open in a window, which stays until it's closed. Badges and status stay on this Mac
/// (`LiveFolderState`), so the minute-by-minute churn never reaches CloudKit.
@Observable
final class LiveFolderRefresher {
    static let shared = LiveFolderRefresher()

    private(set) var states: [String: LiveFolderState] = [:]
    private(set) var refreshing: Set<String> = []

    @ObservationIgnored private weak var model: MacModel?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var sleeper: Task<Void, Never>?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var pokedWhileRefreshing = false
    @ObservationIgnored private var screensAsleep = false
    @ObservationIgnored private var teams: (login: String, names: [String], fetchedAt: Date)?

    private var interval: Duration {
        ProcessInfo.processInfo.isLowPowerModeEnabled || screensAsleep ? .seconds(300) : .seconds(60)
    }

    func start(_ model: MacModel) {
        guard !started else { return }
        started = true
        self.model = model
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { LiveFolderRefresher.shared.screensAsleep = true }
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    LiveFolderRefresher.shared.screensAsleep = false
                    LiveFolderRefresher.shared.refreshNow()
                }
            }
        }
        NotificationCenter.default.addObserver(forName: .githubAccountDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                LiveFolderRefresher.shared.teams = nil
                LiveFolderRefresher.shared.refreshNow()
            }
        }
        Task {
            states = (try? await model.store?.liveFolderStates()) ?? [:]
            // The library loads after the store opens; the first pass waits for it.
            for _ in 0..<60 where model.sidebar.spaces.isEmpty { try? await Task.sleep(for: .milliseconds(500)) }
            await loop()
        }
    }

    /// Refreshes every live folder now (or right after the refresh under way).
    func refreshNow() {
        if isRefreshing { pokedWhileRefreshing = true } else { sleeper?.cancel() }
    }

    func state(of folder: SidebarItem) -> LiveFolderState? { states[folder.id] }

    private func loop() async {
        while !Task.isCancelled {
            await refreshAll()
            if pokedWhileRefreshing { pokedWhileRefreshing = false; continue }
            let interval = interval
            let sleeper = Task { _ = try? await Task.sleep(for: interval) }
            self.sleeper = sleeper
            await sleeper.value
        }
    }

    private func refreshAll() async {
        guard let model else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let allLive = model.sidebar.items.filter { $0.kind == .folder && $0.liveSource?.provider == LiveSource.githubPulls }
        for id in states.keys where !allLive.contains(where: { $0.id == id }) {
            states[id] = nil
            model.store?.setLiveFolderState(nil, folderID: id)
        }
        // A disabled profile's live folders keep their last-known state; they just stop reaching GitHub.
        let folders = allLive.filter { Preferences.liveFoldersEnabled(for: $0.profileID) }
        guard !folders.isEmpty else { return }
        let auth = GitHubAuth.shared
        guard let client = auth.client else {
            for folder in folders { record(folder, error: "Not signed in to GitHub") }
            return
        }
        await auth.loadViewer()
        for folder in folders { await refresh(folder, with: client, login: auth.viewer?.login) }
    }

    private func refresh(_ folder: SidebarItem, with client: GitHubClient, login: String?) async {
        guard let source = folder.liveSource else { return }
        refreshing.insert(folder.id)
        defer { refreshing.remove(folder.id) }
        do {
            var qualifiers: [String] = []
            for filter in GitHubPullFilter.allCases where source.has(filter.rawValue) {
                switch filter {
                case .createdByMe: qualifiers.append("author:@me")
                case .reviewRequests: qualifiers.append("review-requested:@me")
                case .assignedToMe: qualifiers.append("assignee:@me")
                case .mentioned: qualifiers.append("mentions:@me")
                case .teamReviewRequests:
                    qualifiers += await teamNames(client, login: login).prefix(20).map { "team-review-requested:\($0)" }
                }
            }
            let result = try await client.searchPulls(qualifiers, repositories: source.repositories)
            // A pull request in several searches is listed once: its newest copy, else the first filter's.
            var byURL: [URL: GitHubPull] = [:]
            for pull in qualifiers.flatMap({ result.pulls[$0] ?? [] }) where byURL[pull.url].map({ $0.updatedAt < pull.updatedAt }) ?? true {
                byURL[pull.url] = pull
            }
            let pulls = byURL.values.sorted { ($0.updatedAt, $0.url.absoluteString) > ($1.updatedAt, $1.url.absoluteString) }
            guard let model, let current = model.item(folder.id), current.liveSource != nil else { return }
            let previous = states[folder.id]
            let withheld = Set(result.singleSignOn.map { $0.organization.lowercased() })
            // Only tabs this Mac listed last time leave: another Mac's token can see different pull requests, and
            // an organization's results held back for single sign-on say nothing about its pull requests.
            let kept = apply(pulls, to: current, in: model) { tab in
                previous?.items[tab.id] != nil && !withheld.contains(tab.url?.pathComponents.dropFirst().first?.lowercased() ?? "")
            }
            var items = Dictionary(pulls.map { (SidebarItem.liveChildID(folderID: folder.id, url: $0.url), $0.status) },
                                   uniquingKeysWith: { a, _ in a })
            for id in kept { items[id] = previous?.items[id] }
            let repositories = Set(previous?.repositories ?? []).union(pulls.map(\.repository.nameWithOwner))
                .union(source.repositories)
            save(LiveFolderState(
                folderID: folder.id, lastRefreshAt: .now, lastError: nil, items: items,
                repositories: repositories.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending },
                singleSignOn: result.singleSignOn))
        } catch is CancellationError {
        } catch {
            record(folder, error: error.localizedDescription)
        }
    }

    /// The folder's tabs, made to list `pulls` (newest first); unlisted ones go if `mayRemove`. Writes only rows that
    /// change. Returns the unlisted tabs that stay.
    private func apply(_ pulls: [GitHubPull], to folder: SidebarItem, in model: MacModel,
                       mayRemove: (SidebarItem) -> Bool) -> Set<String> {
        let existing = model.sidebar.children(of: folder.id)
        var changes: [SidebarItem] = []
        var listed = Set<String>()
        for (index, pull) in pulls.enumerated() {
            let id = SidebarItem.liveChildID(folderID: folder.id, url: pull.url)
            listed.insert(id)
            let position = Double(index)
            if var tab = model.item(id) {
                // One the user moved out of the folder is theirs now.
                guard tab.parentID == folder.id, tab.title != pull.title || tab.position != position else { continue }
                tab.title = pull.title
                tab.position = position
                changes.append(tab)
            } else {
                changes.append(SidebarItem(id: id, spaceID: folder.spaceID, profileID: folder.profileID, parentID: folder.id,
                                           kind: .tab, title: pull.title, url: pull.url, position: position))
            }
        }
        let now = Date.now
        var kept = Set<String>()
        for var tab in existing where tab.isLiveChild(of: folder) && !listed.contains(tab.id) {
            guard mayRemove(tab), !isOpen(tab.id, in: model) else { kept.insert(tab.id); continue }
            tab.deletedAt = now
            changes.append(tab)
        }
        if !changes.isEmpty { model.commit(changes) }
        return kept
    }

    private func isOpen(_ tabID: String, in model: MacModel) -> Bool {
        model.openBrowsers.contains { $0.hasOpenPage(tabID) }
    }

    private func teamNames(_ client: GitHubClient, login: String?) async -> [String] {
        guard let login else { return [] }
        let cached = teams?.login == login ? teams : nil
        if let cached, cached.fetchedAt.timeIntervalSinceNow > -3600 { return cached.names }
        // A token without `read:org` (a fine-grained one, say) can't list teams: the other filters still refresh,
        // with the teams last listed, and the lookup is retried in an hour.
        let names = (try? await client.teams(login: login)) ?? cached?.names ?? []
        teams = (login, names, .now)
        return names
    }

    private func record(_ folder: SidebarItem, error: String) {
        var state = states[folder.id] ?? LiveFolderState(folderID: folder.id)
        guard state.lastError != error else { return }
        state.lastError = error
        save(state)
    }

    private func save(_ state: LiveFolderState) {
        guard states[state.folderID] != state else { return }
        states[state.folderID] = state
        model?.store?.setLiveFolderState(state, folderID: state.folderID)
    }

    /// "Updated just now", "Updated 3 minutes ago", or "Failed to update", for the folder's menu.
    func statusLine(for folder: SidebarItem) -> String {
        guard let state = states[folder.id] else { return refreshing.contains(folder.id) ? "Updating…" : "Not updated yet" }
        if let error = state.lastError { return error == "Not signed in to GitHub" ? error : "Failed to update" }
        guard let date = state.lastRefreshAt else { return "Not updated yet" }
        if date.timeIntervalSinceNow > -60 { return "Updated just now" }
        return "Updated " + date.formatted(.relative(presentation: .named))
    }
}
