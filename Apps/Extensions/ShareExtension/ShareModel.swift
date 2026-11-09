import BoazKit
import Foundation
import UniformTypeIdentifiers

/// Loads the shared page from the host app's extension item, and writes "Add to Boaz" straight
/// into the store via the App Group — the main app picks it up through its live observation.
@Observable
final class ShareModel {
    var pageTitle = ""
    var pageURL: URL?
    var spaces: [Space] = []
    var selectedSpaceID: String?
    var didSave = false
    var errorMessage: String?

    @ObservationIgnored private let context: NSExtensionContext?
    @ObservationIgnored private let store: BoazStore?

    init(context: NSExtensionContext?) {
        self.context = context
        self.store = try? BoazStore.onDisk(appGroup: BoazStore.appGroup, migrate: false)
        Task { await loadSpaces() }
        loadSharedItem()
    }

    private func loadSpaces() async {
        guard let store, let sidebar = try? await store.loadSidebar() else { return }
        spaces = sidebar.spaces
        let defaults = UserDefaults(suiteName: BoazStore.appGroup)
        if let saved = defaults?.string(forKey: "currentSpaceID"), spaces.contains(where: { $0.id == saved }) {
            selectedSpaceID = saved
        } else {
            selectedSpaceID = spaces.first?.id
        }
    }

    private func loadSharedItem() {
        guard let item = context?.inputItems.first as? NSExtensionItem,
              let provider = item.attachments?.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) })
        else { return }
        pageTitle = item.attributedContentText?.string ?? item.attributedTitle?.string ?? ""
        provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] coded, _ in
            guard let url = coded as? URL else { return }
            Task { @MainActor in self?.pageURL = url }
        }
    }

    @MainActor
    func save(pinned: Bool) {
        guard let store, let url = pageURL, let spaceID = selectedSpaceID,
              let space = spaces.first(where: { $0.id == spaceID })
        else {
            errorMessage = "Nothing to save yet."
            return
        }
        do {
            let sidebar = try store.sidebar()
            guard let box = sidebar.container(pinned ? .pinned : .unpinned, in: space.id) else {
                errorMessage = "Couldn't find \(space.title)'s tabs."
                return
            }
            let title = pageTitle.isEmpty ? (url.host() ?? url.absoluteString) : pageTitle
            let tab = SidebarItem(id: UUID().uuidString, spaceID: space.id, profileID: space.profileID,
                                  parentID: box.id, kind: .tab, title: title, url: url,
                                  position: sidebar.nextPosition(in: box.id))
            try store.save([tab])
            didSave = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel() {
        context?.cancelRequest(withError: NSError(domain: "com.chenkahana.boaz.share", code: 0))
    }

    func complete() {
        context?.completeRequest(returningItems: nil)
    }
}
