#if DEFAULT_BROWSER
import SwiftUI
import UIKit

/// Settings › Default Browser: whether Boaz is the default browser, and a way to make it one. Compiled only with the
/// default browser entitlement (`web-browser.yml`), since iOS doesn't offer Boaz as a choice without it.
struct DefaultBrowserSection: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    /// The last answer from iOS this launch. `isDefault(_:)` is rate-limited, so it's asked once when Settings first
    /// opens and again on coming back from the Settings app, not on every appearance.
    private static var cached: Bool?
    @State private var isDefault = DefaultBrowserSection.cached

    var body: some View {
        Section {
            if isDefault == true {
                Label("Boaz is your default browser", systemImage: "checkmark.circle.fill")
            } else {
                Button("Make Boaz Your Default Browser") {
                    if let url = URL(string: UIApplication.openDefaultApplicationsSettingsURLString) { openURL(url) }
                }
            }
        } header: {
            Text("Default Browser")
        } footer: {
            if isDefault != true {
                Text("Links you tap in other apps open in your default browser. In Settings, choose Browser App, then Boaz.")
            }
        }
        .task { if Self.cached == nil { refresh() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { refresh() } }
    }

    private func refresh() {
        // Rate-limited (or otherwise unavailable): keep the last answer and keep offering the button.
        guard let answer = try? UIApplication.shared.isDefault(.webBrowser) else { return }
        Self.cached = answer
        isDefault = answer
    }
}
#endif
