#if BOAZ_CHROMIUM
import AppKit
import SwiftUI

@MainActor
@Observable
final class ChromiumExtensionManagement {
    struct Installed: Identifiable {
        let id: String
        let name: String
        let version: String
        let enabled: Bool
        let canDisable: Bool
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

    func refresh() {
        error = nil
        guard let enumerate = api.enumerate_managed_extensions else {
            error = "Extension management is unavailable."
            return
        }
        installed = []
        let result = enumerate(profile, { context, id, name, version, enabled, canDisable in
            guard let context, let id, let name, let version else { return }
            MainActor.assumeIsolated {
                let model = Unmanaged<ChromiumExtensionManagement>.fromOpaque(context).takeUnretainedValue()
                model.installed.append(Installed(id: String(cString: id), name: String(cString: name),
                    version: String(cString: version), enabled: enabled != 0, canDisable: canDisable != 0))
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

    private struct ManagementView: View {
        let model: ChromiumExtensionManagement
        let done: () -> Void
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
                                    }
                                }
                                Spacer()
                                if item.enabled && item.canDisable {
                                    Button("Disable") { model.disable(item.id) }
                                        .accessibilityLabel("Disable \(item.name)")
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
        }
    }
}
#endif
