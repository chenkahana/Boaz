import BoazKit
import SwiftUI
import WebKit

/// Which AI sheet is up. The page sheet presents from the tab's browser; the tidy sheets present from the root.
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

/// Tidy Tab Titles for the phone's tabs, for the menu. Tidy Tabs stays on the Mac: the phone has no folders to file
/// tabs into.
struct SpaceAIMenuItems: View {
    @Environment(AppModel.self) private var model
    @AppStorage(AIFeatures.preferenceKey) private var showAIFeatures = true

    var body: some View {
        if AIFeatures.showsEntryPoints(preference: showAIFeatures), !model.isIncognito {
            Section {
                Button("Tidy Tab Titles", systemImage: "character.cursor.ibeam") {
                    // The phone's stack is no space's; it stands in for one here.
                    AIPresenter.shared.request = .tidyTitles(spaceID: model.deviceID)
                }
            }
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

    /// The tidy sheet for the phone's tabs.
    func tidyAISheets() -> some View { modifier(TidySheets()) }
}

private struct TidySheets: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { AIPresenter.shared.request.map { if case .page = $0 { false } else { true } } ?? false },
            set: { if !$0 { AIPresenter.shared.request = nil } })) {
            switch AIPresenter.shared.request {
            case .tidyTitles:
                TidyTitlesView(tabs: model.phoneTabs) { model.applyTitles($0) }
            default:
                EmptyView()
            }
        }
    }
}

extension AppModel {
    func applyTitles(_ changes: [TabTidier.TitleChange]) {
        let records = changes.compactMap { change -> SidebarItem? in
            guard var tab = sidebar.items.first(where: { $0.id == change.tab.id }) else { return nil }
            tab.title = change.title
            tab.modifiedAt = .now
            return tab
        }
        saveAI(records, done: "Renamed \(records.count) tab\(records.count == 1 ? "" : "s")")
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
