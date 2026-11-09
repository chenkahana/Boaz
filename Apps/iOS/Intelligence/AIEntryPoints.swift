import BoazKit
import SwiftUI
import WebKit

/// Which AI sheet is up. The page sheet presents from the tab's browser (it can sit in a full-screen cover);
/// the tidy sheets present from the root.
@Observable
final class AIPresenter {
    static let shared = AIPresenter()
    var request: AIRequest?
}

/// Summarize Page and Ask This Page, for the browser's More menu.
struct PageAIMenuItems: View {
    @AppStorage(AIFeatures.preferenceKey) private var showAIFeatures = true
    let tab: SidebarItem

    var body: some View {
        if AIFeatures.showsEntryPoints(preference: showAIFeatures) {
            Section {
                Button("Summarize Page", systemImage: "sparkles") {
                    AIPresenter.shared.request = .page(tabID: tab.id, mode: .summary)
                }
                Button("Ask This Page", systemImage: "text.bubble") {
                    AIPresenter.shared.request = .page(tabID: tab.id, mode: .ask)
                }
            }
        }
    }
}

/// Tidy Tabs and Tidy Tab Titles for the current space, for the home menu and the Today header.
struct SpaceAIMenuItems: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AIFeatures.preferenceKey) private var showAIFeatures = true

    var body: some View {
        if AIFeatures.showsEntryPoints(preference: showAIFeatures), !model.isIncognito, let space = model.currentSpace {
            Section {
                Button("Tidy Tabs", systemImage: "sparkles") { AIPresenter.shared.request = .tidyTabs(spaceID: space.id) }
                    .disabled(model.todayTabs(in: space).count < TabTidier.minimumTabs)
                Button("Tidy Tab Titles", systemImage: "character.cursor.ibeam") {
                    AIPresenter.shared.request = .tidyTitles(spaceID: space.id)
                }
            }
        }
    }
}

/// The Today header's sparkles menu.
struct TodayAIMenu: View {
    @AppStorage(AIFeatures.preferenceKey) private var showAIFeatures = true

    var body: some View {
        if AIFeatures.showsEntryPoints(preference: showAIFeatures) {
            Menu {
                SpaceAIMenuItems()
            } label: {
                Image(systemName: "sparkles").font(.footnote.weight(.semibold))
                    .frame(width: 44, height: 28).contentShape(.rect)
            }
            .accessibilityLabel("Tidy with Apple Intelligence")
        }
    }
}

extension View {
    /// The page sheet, shown over `tab`'s browser.
    func pageAISheet(tab: SidebarItem, page: WebPage) -> some View {
        sheet(isPresented: Binding(
            get: { if case .page(tab.id, _) = AIPresenter.shared.request { true } else { false } },
            set: { if !$0 { AIPresenter.shared.request = nil } })) {
            if case .page(_, let mode) = AIPresenter.shared.request {
                PageAssistantView(page: page, mode: mode).presentationDetents([.medium, .large])
            }
        }
    }

    /// The tidy sheets for the current space.
    func tidyAISheets() -> some View { modifier(TidySheets()) }
}

private struct TidySheets: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { AIPresenter.shared.request.map { if case .page = $0 { false } else { true } } ?? false },
            set: { if !$0 { AIPresenter.shared.request = nil } })) {
            switch AIPresenter.shared.request {
            case .tidyTabs(let spaceID):
                if let space = model.spaces.first(where: { $0.id == spaceID }) {
                    TidyTabsView(tabs: model.todayTabs(in: space)) { model.applyTidy($0, in: space) }
                }
            case .tidyTitles(let spaceID):
                if let space = model.spaces.first(where: { $0.id == spaceID }) {
                    TidyTitlesView(tabs: model.allPinnedTabs(in: space)) { model.applyTitles($0) }
                }
            default:
                EmptyView()
            }
        }
    }
}

extension AppModel {
    /// Every tab under a space's pinned section, including those in folders.
    func allPinnedTabs(in space: Space) -> [SidebarItem] {
        func flatten(_ parent: String) -> [SidebarItem] {
            sidebar.children(of: parent).flatMap { $0.kind == .folder ? flatten($0.id) : $0.kind == .tab ? [$0] : [] }
        }
        return sidebar.container(.pinned, in: space.id).map { flatten($0.id) } ?? []
    }

    /// Creates the plan's folders at the end of Today and moves its tabs in.
    func applyTidy(_ plan: TabTidier.Plan, in space: Space) {
        guard let box = sidebar.container(.unpinned, in: space.id) else { return }
        let records = TabTidier.records(for: plan, today: box, in: sidebar)
        saveAI(records, done: "Tidied into \(plan.groups.count) folder\(plan.groups.count == 1 ? "" : "s")")
    }

    func applyTitles(_ changes: [TabTidier.TitleChange]) {
        let records = changes.compactMap { change -> SidebarItem? in
            guard var tab = sidebar.items.first(where: { $0.id == change.tab.id }) else { return nil }
            tab.title = change.title
            tab.modifiedAt = .now
            return tab
        }
        saveAI(records, done: "Renamed \(records.count) tab\(records.count == 1 ? "" : "s")")
    }

    /// Moves a Today folder's tabs back into Today and removes the folder.
    func ungroup(_ folder: SidebarItem) {
        guard folder.kind == .folder, let parent = folder.parentID else { return }
        var position = sidebar.nextPosition(in: parent)
        var records: [SidebarItem] = sidebar.children(of: folder.id).map { child in
            var child = child
            child.parentID = parent
            child.position = position
            child.modifiedAt = .now
            position += 1
            return child
        }
        var removed = folder
        removed.deletedAt = .now
        removed.modifiedAt = .now
        records.append(removed)
        saveAI(records, done: nil)
    }

    private func saveAI(_ records: [SidebarItem], done: String?) {
        guard !records.isEmpty else { return }
        withAnimation(.snappy) { for record in records { sidebar.upsert(record) } }
        do {
            try store?.save(records)
            if let done { showToast(done) }
        } catch {
            showToast("Couldn't save. Try again.")
        }
    }
}
