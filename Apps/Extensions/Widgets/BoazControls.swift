import AppIntents
import SwiftUI
import WidgetKit

/// Control Center, the Lock Screen and the Action button: a new tab, which in Boaz opens on the search panel, so the
/// same control serves "search the web" too.
struct NewTabControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.chenkahana.boaz.control.new-tab") {
            ControlWidgetButton(action: OpenNewTabIntent()) {
                Label("New Tab", systemImage: "plus")
            }
        }
        .displayName("New Tab")
        .description("Opens Boaz ready to search or enter an address.")
    }
}

struct OpenNewTabIntent: AppIntent {
    static let title: LocalizedStringResource = "New Tab"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(BoazLink.search()))
    }
}
