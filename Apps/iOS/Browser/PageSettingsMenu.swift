import SwiftUI

/// The ellipsis menu's "Website Settings": permissions, pop-ups and content blocking for the current host.
struct WebsiteSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let host: String?
    let isPrivate: Bool
    @State private var settings: PageSettings.HostSettings

    init(host: String?, isPrivate: Bool) {
        self.host = host
        self.isPrivate = isPrivate
        _settings = State(initialValue: PageSettings.settings(forHost: host, isPrivate: isPrivate))
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
                } header: {
                    Text("Permissions")
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
            PageSettings.update(forHost: host, isPrivate: isPrivate) { $0 = new }
        }
    }
}
