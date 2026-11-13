#if BOAZ_CHROMIUM
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import BoazKit

@MainActor
final class ChromiumExtensionMigration: NSObject, NSWindowDelegate {
    private static var active: [ObjectIdentifier: ChromiumExtensionMigration] = [:]
    private weak var parent: NSWindow?
    private let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 440),
                                styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private var completion: (() -> Void)?
    private var finished = false

    static func present(window: NSWindow, profileID: String, profiles: [BoazKit.Profile],
                        openStore: @escaping (URL) -> Void,
                        loadDeveloper: @escaping () -> Void) {
        guard window.attachedSheet == nil, active[ObjectIdentifier(window)] == nil else { return }
        let chooser = NSOpenPanel()
        chooser.title = "Choose Previous Extension List"
        chooser.message = "Choose the installed.json file from your previous Boaz extension folder."
        chooser.allowedContentTypes = [.json]
        chooser.allowsMultipleSelection = false
        chooser.canChooseDirectories = false
        chooser.beginSheetModal(for: window) { response in
            guard response == .OK, let url = chooser.url else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let result: Result<ChromiumExtensionMigrationInventory.Inventory, Error>
            do {
                guard url.lastPathComponent == "installed.json" else {
                    throw ChromiumExtensionMigrationInventory.InventoryError.invalidManifest
                }
                result = .success(try ChromiumExtensionMigrationInventory.read(from: url, profiles: profiles))
            } catch { result = .failure(error) }
            let controller = ChromiumExtensionMigration()
            controller.parent = window
            controller.panel.title = "Reinstall Previous Extensions"
            controller.panel.isReleasedWhenClosed = false
            controller.panel.delegate = controller
            controller.panel.contentView = NSHostingView(rootView: MigrationView(
                result: result, profileID: profileID,
                close: { [weak controller] in controller?.finish() },
                openStore: { [weak controller] url in controller?.finish { openStore(url) } },
                loadDeveloper: { [weak controller] in controller?.finish(action: loadDeveloper) }))
            active[ObjectIdentifier(window)] = controller
            window.beginSheet(controller.panel) { [controller, weak window] _ in
                let action = controller.completion
                controller.completion = nil
                if let window { active.removeValue(forKey: ObjectIdentifier(window)) }
                controller.panel.orderOut(nil)
                if window?.isVisible == true { action?() }
            }
        }
    }

    private func finish(action: (() -> Void)? = nil) {
        guard !finished else { return }
        finished = true
        completion = action
        if let parent, panel.sheetParent === parent { parent.endSheet(panel) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        finish()
        return false
    }
}

@MainActor
private struct MigrationView: View {
    let result: Result<ChromiumExtensionMigrationInventory.Inventory, Error>
    let profileID: String
    let close: () -> Void
    let openStore: (URL) -> Void
    let loadDeveloper: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Reinstall Previous Extensions").font(.title2.bold())
            Text("Review each extension and approve its permissions again. Nothing has been installed or copied by reading this list.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch result {
                    case .failure:
                        Text("The extension list could not be read. Choose a valid installed.json file and try again.")
                            .foregroundStyle(.red)
                    case .success(let inventory):
                        let group = inventory.groups.first { $0.profileID == profileID }
                        let otherCount = inventory.groups.filter { $0.profileID != profileID }.reduce(0) { $0 + $1.items.count }
                        if let group {
                            Text(group.profileName).font(.headline)
                            ForEach(group.items) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.name).font(.headline)
                                    Text(item.enabled ? "Previously enabled" : "Previously disabled")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if item.kind == .storeCandidate {
                                        Button("Review in Store") {
                                            guard item.extensionID.utf8.count == 32,
                                                  item.extensionID.utf8.allSatisfy({ (97...112).contains($0) }),
                                                  let url = URL(string: "https://chromewebstore.google.com/detail/\(item.extensionID)") else { return }
                                            openStore(url)
                                        }
                                        .accessibilityLabel("Review \(item.name) in Chrome Web Store")
                                    } else {
                                        Text("The previous ZIP does not prove a verified signature. Choose the original developer folder to review it as a developer extension.")
                                            .font(.caption).foregroundStyle(.secondary)
                                        Button("Choose Developer Folder…", action: loadDeveloper)
                                            .accessibilityLabel("Choose developer folder for \(item.name)")
                                    }
                                    Text("Reinstallation pending").font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Divider()
                            }
                        } else {
                            Text("No extensions in this list belong to the current profile.")
                        }
                        if otherCount > 0 {
                            Text("\(otherCount) extension(s) belong to other profiles. Open each profile’s window to review its extensions.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        if !inventory.issues.isEmpty {
                            Text("Records that could not be imported").font(.headline)
                            ForEach(inventory.issues) { issue in
                                Text(issue.message).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); Button("Close", action: close).keyboardShortcut(.cancelAction) }
        }
        .padding(20)
        .frame(width: 560, height: 440)
    }
}
#endif
