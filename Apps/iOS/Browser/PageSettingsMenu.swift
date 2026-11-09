import BoazKit
import SwiftUI

/// The ellipsis menu's "Website Settings": permissions, pop-ups and content blocking for the current host.
struct WebsiteSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let tab: SidebarItem
    let host: String?
    @State private var settings: PageSettings.HostSettings

    init(tab: SidebarItem, host: String?) {
        self.tab = tab
        self.host = host
        _settings = State(initialValue: PageSettings.settings(forHost: host))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Camera", selection: $settings.camera) {
                        ForEach(PageSettings.Permission.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Microphone", selection: $settings.microphone) {
                        ForEach(PageSettings.Permission.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Location", selection: $settings.location) {
                        ForEach(PageSettings.Permission.allCases) { Text($0.label).tag($0) }
                    }
                } header: {
                    Text("Permissions")
                } footer: {
                    // WebPage has no permission hook for geolocation (only camera and microphone), so
                    // this site can't be stopped from asking iOS for location the way it can for those.
                    Text("Camera and microphone requests from this site are granted or denied as chosen here. Location can't be enforced the same way; iOS still asks on the site's behalf.")
                }
                Section("Pop-ups") {
                    Picker("Pop-ups", selection: $settings.popups) {
                        ForEach(PageSettings.PopupPolicy.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section {
                    Toggle("Content Blocking", isOn: $settings.contentBlocking)
                } footer: {
                    Text("Applies the next time this site opens in a new tab.")
                }
            }
            .navigationTitle(host ?? "Website Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } } }
        }
        .onChange(of: settings) { _, new in
            PageSettings.update(forHost: host, remember: !model.isPrivate(tab)) { $0 = new }
        }
    }
}
