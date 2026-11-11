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
        selectedSpaceID = spaces.first?.id
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

    /// Pins the page in the chosen space, or opens it as a tab on this iPhone (on top of its stack, with the chosen
    /// space's website data).
    @MainActor
    func save(pinned: Bool) {
        guard let store, let url = pageURL, let spaceID = selectedSpaceID,
              let space = spaces.first(where: { $0.id == spaceID })
        else {
            errorMessage = "Nothing to save yet."
            return
        }
        do {
            let title = pageTitle.isEmpty ? (url.host() ?? url.absoluteString) : pageTitle
            let tab: SidebarItem
            if pinned {
                let sidebar = try store.sidebar()
                guard let box = sidebar.container(.pinned, in: space.id) else {
                    errorMessage = "Couldn't find \(space.title)'s tabs."
                    return
                }
                tab = SidebarItem(id: UUID().uuidString, spaceID: space.id, profileID: space.profileID,
                                  parentID: box.id, kind: .tab, title: title, url: url,
                                  position: sidebar.nextPosition(in: box.id))
            } else {
                // The App Group's defaults hold the same device id the app uses.
                tab = .mobileTab(url: url, title: title, profileID: space.profileID,
                                 deviceID: Device.localID(in: UserDefaults(suiteName: BoazStore.appGroup) ?? .standard))
            }
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
