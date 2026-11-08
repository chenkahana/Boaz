import AppIntents
import UIKit

/// Opens a page in Folio. Runs `openAppWhenRun` so the app is foregrounded, then the request is
/// routed through `DeepLink` the same way a widget tap or `.onOpenURL` is handled.
struct OpenInFolioIntent: AppIntent {
    static let title: LocalizedStringResource = "Open in Folio"
    static let openAppWhenRun = true

    @Parameter(title: "Page")
    var url: URL

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$url) in Folio")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let link = DeepLink.url(forOpening: url) {
            await UIApplication.shared.open(link)
        }
        return .result()
    }
}

/// Searches Folio for `searchTerm`. Runs `openAppWhenRun` so the app is foregrounded, then the
/// request is routed through `DeepLink`. The Shortcut phrase below stays static (no embedded
/// `\.$searchTerm`): AppIntents' metadata processor rejects a `String` parameter referenced inside
/// an `AppShortcut` phrase, requiring `AppEntity`/`AppEnum` there instead, and halts the whole
/// app's build otherwise.
struct SearchInFolioIntent: AppIntent {
    static let title: LocalizedStringResource = "Search in Folio"
    static let openAppWhenRun = true

    @Parameter(title: "Search")
    var searchTerm: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search \(\.$searchTerm) in Folio")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let link = DeepLink.url(forSearching: searchTerm) {
            await UIApplication.shared.open(link)
        }
        return .result()
    }
}

struct FolioShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SearchInFolioIntent(),
            phrases: ["Search in \(.applicationName)"],
            shortTitle: "Search",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: OpenInFolioIntent(),
            phrases: ["Open in \(.applicationName)"],
            shortTitle: "Open",
            systemImageName: "safari"
        )
    }
}
