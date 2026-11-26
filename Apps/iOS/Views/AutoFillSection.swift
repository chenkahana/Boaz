#if AUTOFILL_EXTENSION
import AuthenticationServices
import SwiftUI

/// Settings › Passwords: whether Boaz fills passwords in other apps, and a way to turn it on. Compiled only with the
/// AutoFill extension (`autofill.yml`). Boaz asks iOS here only, when the user taps, never on its own.
struct AutoFillSection: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOn: Bool?

    var body: some View {
        Section {
            if isOn == true {
                Label("Used in Other Apps", systemImage: "checkmark.circle.fill")
            } else {
                Button("Use Boaz Passwords in Other Apps") { Task { await turnOn() } }
            }
        } footer: {
            Text(isOn == true ? "Turn it off in Settings › General › AutoFill & Passwords."
                              : "Fill your Boaz passwords in Safari and other apps from the key above the keyboard.")
        }
        .task { await refresh() }
        // The user may switch it in the Settings app while Boaz waits in the background.
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await refresh() } } }
    }

    private func refresh() async {
        isOn = await ASCredentialIdentityStore.shared.state().isEnabled
    }

    private func turnOn() async {
        if await ASSettingsHelper.requestToTurnOnCredentialProviderExtension() {
            await refresh()
        } else {
            try? await ASSettingsHelper.openCredentialProviderAppSettings()
        }
    }
}
#endif
