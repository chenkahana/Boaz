#if BOAZ_CHROMIUM
import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class ChromiumSitePermissions {
    struct Permission: Identifiable {
        let id: Int32
        let origin: String
        let setting: Int32
        let canReset: Bool
        let embargoed: Bool
        var name: String {
            switch id {
            case 0: "Camera"
            case 1: "Microphone"
            case 2: "Notifications"
            default: "Unsupported permission"
            }
        }
        var status: String {
            switch setting {
            case 0: "Ask"
            case 1: "Allowed"
            case 2: "Blocked"
            default: "Other setting"
            }
        }
    }

    private let page: ChromiumEnginePageAdapter
    private let navigation: UInt64
    private(set) var permissions: [Permission] = []
    private(set) var error: String?
    var isCurrent: Bool {
        page.state.lifecycle == .active && !page.state.isLoading && page.state.navigationID == navigation
    }

    private init(page: ChromiumEnginePageAdapter) {
        self.page = page
        navigation = page.state.navigationID
    }

    static func present(page: ChromiumEnginePageAdapter, window: NSWindow) {
        guard window.isVisible, window.attachedSheet == nil else { return }
        let model = ChromiumSitePermissions(page: page)
        model.refresh()
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "Site Permissions"
        sheet.contentViewController = NSHostingController(rootView: PermissionsView(model: model) {
            window.endSheet(sheet)
        })
        window.beginSheet(sheet) { _ in
            sheet.orderOut(nil)
            sheet.contentViewController = nil
        }
    }

    func refresh() {
        permissions = []
        error = nil
        guard isCurrent, let enumerate = page.api.enumerate_site_permissions else {
            error = "Permissions are unavailable for this page. Close this panel and try again after the page loads."
            return
        }
        let result = enumerate(page.handle, navigation, { context, origin, kind, setting, canReset, embargoed in
            guard let context, let origin else { return }
            MainActor.assumeIsolated {
                let model = Unmanaged<ChromiumSitePermissions>.fromOpaque(context).takeUnretainedValue()
                model.permissions.append(Permission(id: kind, origin: String(cString: origin),
                    setting: setting, canReset: canReset != 0, embargoed: embargoed != 0))
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        if result != BOAZ_HOST_OK || !isCurrent {
            permissions = []
            error = "Site permissions could not be read. The page may have changed."
        }
    }

    func reset(_ kind: Int32) {
        guard isCurrent, permissions.contains(where: { $0.id == kind && $0.canReset }),
              let reset = page.api.reset_site_permission else {
            error = "This permission cannot be reset for the current page."
            return
        }
        let result = reset(page.handle, navigation, kind)
        refresh()
        if result != BOAZ_HOST_OK {
            error = "The permission could not be reset. It may be controlled by a policy or the page may have changed."
        }
    }

    private struct PermissionsView: View {
        let model: ChromiumSitePermissions
        let done: () -> Void
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Site Permissions").font(.title2.weight(.semibold))
                Text("Permissions for this top-level site. These controls do not change macOS device permissions or individual embedded frames.")
                    .font(.callout).foregroundStyle(.secondary)
                if !model.isCurrent {
                    Text("The page changed or closed. Reopen Site Permissions for the current page.")
                        .foregroundStyle(.secondary)
                }
                if let error = model.error { Text(error).foregroundStyle(.red) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.permissions) { permission in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(permission.origin).font(.caption).textSelection(.enabled)
                                HStack {
                                    Text(permission.name).fontWeight(.medium)
                                    Spacer()
                                    Text(permission.status).foregroundStyle(.secondary)
                                    Button("Reset") { model.reset(permission.id) }
                                        .disabled(!model.isCurrent || !permission.canReset)
                                        .accessibilityLabel("Reset \(permission.name) permission")
                                }
                                if permission.embargoed {
                                    Text("Requests are automatically blocked after previous dismissals or denials.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if !permission.canReset && permission.setting != 0 {
                                    Text("Reset is unavailable. This setting may be controlled by a policy.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Text("Reload the page to apply changes to active camera or microphone access.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Refresh") { model.refresh() }.disabled(!model.isCurrent)
                    Spacer()
                    Button("Done", action: done).keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(minWidth: 420, minHeight: 320)
        }
    }
}
#endif
