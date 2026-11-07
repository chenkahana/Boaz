import FolioKit
import SwiftUI
import WebKit

@main
struct FolioMacApp: App {
    @State private var model = MacModel()

    var body: some Scene {
        WindowGroup {
            MacRootView()
                .environment(model)
                .tint(Theme.brand)
                .task { await model.start() }
        }
    }
}

/// Phase 0 shell: proves the shared store end to end. The real sidebar UI lands in Phase 3.
@Observable
final class MacModel {
    var sidebar = Sidebar()
    var selectedTabID: String?
    var loadError: String?
    let page = WebPage()
    private var store: FolioStore?

    func start() async {
        do {
            let store = try FolioStore.onDisk()
            self.store = store
            #if DEBUG
            if try store.isEmpty() { try SampleData.seed(store) }
            #endif
            for try await snapshot in store.sidebarUpdates() { sidebar = snapshot }
        } catch {
            loadError = String(describing: error)
        }
    }

    func open(_ tab: SidebarItem) {
        selectedTabID = tab.id
        if let url = tab.url { page.load(URLRequest(url: url)) }
    }
}

struct MacRootView: View {
    @Environment(MacModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selectedTabID) {
                ForEach(model.sidebar.spaces) { space in
                    Section("\(space.icon ?? "") \(space.title)") {
                        ForEach([SidebarItem.ContainerKind.pinned, .unpinned], id: \.self) { kind in
                            if let box = model.sidebar.container(kind, in: space.id) {
                                ItemRows(parentID: box.id)
                            }
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .onChange(of: model.selectedTabID) { _, id in
                if let tab = model.sidebar.items.first(where: { $0.id == id }) { model.open(tab) }
            }
        } detail: {
            WebView(model.page)
                .overlay {
                    if let error = model.loadError {
                        ContentUnavailableView("Store failed to open", systemImage: "exclamationmark.triangle",
                                               description: Text(error))
                    }
                }
        }
    }
}

private struct ItemRows: View {
    @Environment(MacModel.self) private var model
    let parentID: String

    var body: some View {
        ForEach(model.sidebar.children(of: parentID)) { item in
            switch item.kind {
            case .folder:
                DisclosureGroup {
                    ItemRows(parentID: item.id)
                } label: {
                    Label(item.title ?? "Folder", systemImage: "folder")
                }
            case .tab:
                Label(item.title ?? item.url?.absoluteString ?? "Tab", systemImage: "globe").tag(item.id)
            case .container:
                EmptyView()
            }
        }
    }
}
