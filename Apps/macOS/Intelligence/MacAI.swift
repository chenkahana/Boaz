import FolioKit
import SwiftUI

/// The window's AI sheet: Summarize/Ask for a tab, or tidying a space.
struct MacAISheet: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    let request: AIRequest

    var body: some View {
        switch request {
        case .page(let tabID, let mode):
            if let tab = browser.tab(tabID) {
                PageAssistantView(page: browser.page(for: tab), mode: mode)
            }
        case .tidyTabs(let spaceID):
            if let space = model.space(spaceID) {
                TidyTabsView(tabs: model.todayTabs(in: space)) { model.applyTidy($0, in: space) }
            }
        case .tidyTitles(let spaceID):
            if let space = model.space(spaceID) {
                TidyTitlesView(tabs: model.allPinnedTabs(in: space)) { model.applyTitles($0) }
            }
        }
    }
}

/// View menu: Summarize Page (⌥⌘S) and Ask This Page for the active tab.
struct PageAICommands: View {
    @AppStorage(AIFeatures.preferenceKey) private var showAIFeatures = true
    let browser: BrowserState?

    var body: some View {
        if AIFeatures.showsEntryPoints(preference: showAIFeatures) {
            Button("Summarize Page") { open(.summary) }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(browser?.activeTab == nil)
            Button("Ask This Page…") { open(.ask) }
                .disabled(browser?.activeTab == nil)
            Divider()
        }
    }

    private func open(_ mode: PageAssistantView.Mode) {
        guard let browser, let tab = browser.activeTab else { return }
        browser.ai = .page(tabID: tab.id, mode: mode)
    }
}

/// Summarize Page in a tab's context menu (it opens the tab first).
struct TabAIMenuItems: View {
    @AppStorage(AIFeatures.preferenceKey) private var showAIFeatures = true
    @Environment(BrowserState.self) private var browser
    let tab: SidebarItem

    var body: some View {
        if AIFeatures.showsEntryPoints(preference: showAIFeatures), tab.url != nil {
            Button("Summarize Page") {
                browser.activate(tab)
                browser.ai = .page(tabID: tab.id, mode: .summary)
            }
        }
    }
}

/// Tidy Tabs and Tidy Tab Titles in the space menu.
struct SpaceAIMenuItems: View {
    @AppStorage(AIFeatures.preferenceKey) private var showAIFeatures = true
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    let space: Space

    var body: some View {
        if AIFeatures.showsEntryPoints(preference: showAIFeatures), !browser.isIncognito {
            Divider()
            Button("Tidy Tabs…") { browser.ai = .tidyTabs(spaceID: space.id) }
                .disabled(model.todayTabs(in: space).count < TabTidier.minimumTabs)
            Button("Tidy Tab Titles…") { browser.ai = .tidyTitles(spaceID: space.id) }
        }
    }
}

/// The undo behind the toast that announced an AI change; the toast's Undo runs it instead of reopening a tab.
enum AIUndo {
    private static var pending: (toastID: UUID, undo: () -> Void)?

    static func register(toast id: UUID?, _ undo: @escaping () -> Void) {
        pending = id.map { ($0, undo) }
    }

    /// Runs the undo registered for this toast. False when there is none, so the caller does its own.
    static func perform(for toastID: UUID) -> Bool {
        guard let pending, pending.toastID == toastID else { return false }
        self.pending = nil
        pending.undo()
        return true
    }
}

extension MacModel {
    /// Creates the plan's folders at the end of Today and moves its tabs in, as one undoable change.
    func applyTidy(_ plan: TabTidier.Plan, in space: Space) {
        guard let box = sidebar.container(.unpinned, in: space.id) else { return }
        let records = TabTidier.records(for: plan, today: box, in: sidebar)
        guard !records.isEmpty else { return }
        let before = records.compactMap { item($0.id) }
        let folders = records.filter { $0.kind == .folder }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { commit(records) }
        showToast("Tidied into \(folders.count) folder\(folders.count == 1 ? "" : "s")", canUndo: true)
        AIUndo.register(toast: toast?.id) { [weak self] in
            let removed = folders.map { var folder = $0; folder.deletedAt = .now; return folder }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { self?.commit(before + removed) }
        }
    }

    func applyTitles(_ changes: [TabTidier.TitleChange]) {
        let before = changes.compactMap { item($0.tab.id) }
        let renamed = before.map { tab in
            var tab = tab
            tab.title = changes.first { $0.tab.id == tab.id }?.title ?? tab.title
            return tab
        }
        guard !renamed.isEmpty else { return }
        commit(renamed)
        showToast("Renamed \(renamed.count) tab\(renamed.count == 1 ? "" : "s")", canUndo: true)
        AIUndo.register(toast: toast?.id) { [weak self] in self?.commit(before) }
    }

    /// Moves a Today folder's tabs back into Today and removes the folder.
    func ungroup(_ folder: SidebarItem) {
        guard folder.kind == .folder, let parent = folder.parentID else { return }
        var position = sidebar.nextPosition(in: parent)
        var records = sidebar.children(of: folder.id).map { child in
            var child = child
            child.parentID = parent
            child.position = position
            position += 1
            return child
        }
        var removed = folder
        removed.deletedAt = .now
        records.append(removed)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { commit(records) }
    }
}
