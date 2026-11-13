#if BOAZ_CHROMIUM
import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ChromiumExtensionManagement {
    struct Installed: Identifiable {
        let id: String
        let name: String
        let version: String
        let enabled: Bool
        let canDisable: Bool
        let canEnable: Bool
        let canUninstall: Bool
    }
    private let api: BoazHostAPI
    private let profile: BoazHostProfile
    private(set) var installed: [Installed] = []
    private(set) var error: String?

    private init(api: BoazHostAPI, profile: BoazHostProfile) {
        self.api = api
        self.profile = profile
    }

    static func present(api: BoazHostAPI, profile: BoazHostProfile, window: NSWindow) {
        guard window.attachedSheet == nil else { return }
        let model = ChromiumExtensionManagement(api: api, profile: profile)
        model.refresh()
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "Chromium Extensions"
        sheet.contentViewController = NSHostingController(rootView: ManagementView(model: model) {
            window.endSheet(sheet)
        })
        window.beginSheet(sheet) { _ in sheet.orderOut(nil); sheet.contentViewController = nil }
    }

    private final class InstallRequest {
        weak var window: NSWindow?
        init(window: NSWindow) { self.window = window }
        func finish(_ result: BoazHostExtensionInstallResult) {
            guard window?.isVisible == true else { return }
            switch result {
            case BOAZ_EXTENSION_INSTALLED: MacModel.shared.showToast("Extension installed.")
            case BOAZ_EXTENSION_INSTALL_CANCELLED: break
            default: MacModel.shared.showToast("The extension could not be installed. The file may be invalid or its permissions may need additional approval.")
            }
        }
    }

    static func install(api: BoazHostAPI, handle: BoazHostWindow, window: NSWindow, unpacked: Bool = false) {
        guard window.attachedSheet == nil,
              let install = unpacked ? api.install_unpacked_extension : api.install_extension else { return }
        let panel = NSOpenPanel()
        panel.title = unpacked ? "Load Developer Extension" : "Install Chromium Extension"
        panel.message = unpacked ? "Choose a developer extension folder. Boaz will ask you to confirm that you trust it before loading." : "Choose a signed CRX file. Boaz will ask you to review its permissions before installing."
        panel.canChooseDirectories = unpacked
        panel.canChooseFiles = !unpacked
        panel.allowsMultipleSelection = false
        if !unpacked { panel.allowedContentTypes = [UTType(filenameExtension: "crx") ?? .data] }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url, window.isVisible else { return }
            let path = url.resolvingSymlinksInPath().path
            guard unpacked || url.pathExtension.lowercased() == "crx" else {
                MacModel.shared.showToast("Choose a signed CRX extension file.")
                return
            }
            let context = Unmanaged.passRetained(InstallRequest(window: window)).toOpaque()
            let result = path.withCString { install(handle, $0, 1, { context, _, _, result in
                guard let context else { return }
                MainActor.assumeIsolated {
                    let request = Unmanaged<InstallRequest>.fromOpaque(context).takeRetainedValue()
                    DispatchQueue.main.async { request.finish(result) }
                }
            }, context) }
            if result != BOAZ_HOST_OK {
                Unmanaged<InstallRequest>.fromOpaque(context).release()
                MacModel.shared.showToast("Extension installation is unavailable for this window or another installation is still running.")
            }
        }
    }

    func refresh() {
        error = nil
        guard let enumerate = api.enumerate_managed_extensions else {
            error = "Extension management is unavailable."
            return
        }
        installed = []
        let result = enumerate(profile, { context, id, name, version, enabled, canDisable, canEnable, canUninstall in
            guard let context, let id, let name, let version else { return }
            MainActor.assumeIsolated {
                let model = Unmanaged<ChromiumExtensionManagement>.fromOpaque(context).takeUnretainedValue()
                model.installed.append(Installed(id: String(cString: id), name: String(cString: name),
                    version: String(cString: version), enabled: enabled != 0, canDisable: canDisable != 0, canEnable: canEnable != 0, canUninstall: canUninstall != 0))
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        if result != BOAZ_HOST_OK {
            installed = []
            error = "Extensions could not be read for this profile."
        }
    }

    func disable(_ extensionID: String) {
        guard installed.contains(where: { $0.id == extensionID && $0.enabled && $0.canDisable }),
              let disable = api.disable_extension else { return }
        let result = extensionID.withCString { disable(profile, $0) }
        refresh()
        if result != BOAZ_HOST_OK {
            error = "This extension could not be disabled. It may be required by a policy or the profile may have closed."
        }
    }

    func enable(_ extensionID: String) {
        guard installed.contains(where: { $0.id == extensionID && !$0.enabled && $0.canEnable }),
              let enable = api.enable_extension else { return }
        let result = extensionID.withCString { enable(profile, $0) }
        refresh()
        if result != BOAZ_HOST_OK {
            error = "This extension could not be enabled. It may need additional permission approval or be restricted by a policy."
        }
    }

    func remove(_ extensionID: String) {
        guard installed.contains(where: { $0.id == extensionID && $0.canUninstall }),
              let uninstall = api.uninstall_extension else {
            error = "This extension cannot be removed. Refresh the list to check its current status."
            return
        }
        let result = extensionID.withCString { uninstall(profile, $0) }
        refresh()
        if result != BOAZ_HOST_OK {
            error = "This extension could not be removed. It may be required by a policy or the profile may have closed."
        }
    }

    private struct ManagementView: View {
        let model: ChromiumExtensionManagement
        let done: () -> Void
        @State private var removal: Installed?
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Chromium Extensions").font(.title2.weight(.semibold))
                Text("Installed extensions for this profile.").foregroundStyle(.secondary)
                if let error = model.error {
                    Text(error).foregroundStyle(.red).accessibilityLabel(error)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if model.installed.isEmpty && model.error == nil {
                            Text("No extensions are installed in this profile.").foregroundStyle(.secondary)
                        }
                        ForEach(model.installed) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name).fontWeight(.medium)
                                    Text("Version \(item.version) · \(item.enabled ? "Enabled" : "Disabled")")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if item.enabled && !item.canDisable {
                                        Text("Required by the browser or a policy.")
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else if !item.enabled && !item.canEnable {
                                        Text("Additional approval or policy review is required.")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if item.enabled && item.canDisable {
                                    Button("Disable") { model.disable(item.id) }
                                        .accessibilityLabel("Disable \(item.name)")
                                } else if !item.enabled && item.canEnable {
                                    Button("Enable") { model.enable(item.id) }
                                        .accessibilityLabel("Enable \(item.name)")
                                }
                                if item.canUninstall {
                                    Button("Remove", role: .destructive) { removal = item }
                                        .accessibilityLabel("Remove \(item.name)")
                                }
                            }
                            Divider()
                        }
                    }
                }
                HStack {
                    Button("Refresh") { model.refresh() }
                    Spacer()
                    Button("Done", action: done).keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(minWidth: 480, minHeight: 360)
            .alert("Remove extension?", isPresented: Binding(
                get: { removal != nil }, set: { if !$0 { removal = nil } }
            ), presenting: removal) { item in
                Button("Cancel", role: .cancel) { removal = nil }
                Button("Remove", role: .destructive) {
                    removal = nil
                    model.remove(item.id)
                }
            } message: { item in
                Text("Remove “\(item.name)” from this profile? Its extension data may also be removed.")
            }
        }
    }
}
#endif
