import BoazKit
import Foundation

/// Same UserDefaults keys and values as the iOS app, so the settings mean the same thing on both.
enum ArchiveInterval: Int, CaseIterable, Identifiable {
    case twelveHours = 43_200, day = 86_400, week = 604_800, month = 2_592_000, never = 0
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .twelveHours: "12 hours"
        case .day: "1 day"
        case .week: "7 days"
        case .month: "30 days"
        case .never: "Never"
        }
    }
}

enum Preferences {
    static let archiveAfterKey = "archiveAfter"
    static let searchEngineKey = "searchEngine"
    static let blockTrackersKey = "blockTrackers"
    /// The sidebar rows' point size, read through `@AppStorage` (default `SidebarStyle.defaultTextSize`).
    static let sidebarTextSizeKey = "sidebarTextSize"
    /// Set from the "Don't ask again" box on the warning before a middle-click removes a pinned tab.
    static let skipsPinnedRemovalWarningKey = "skipsPinnedRemovalWarning"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            archiveAfterKey: ArchiveInterval.week.rawValue,
            searchEngineKey: SearchEngine.duckDuckGo.rawValue,
            blockTrackersKey: true,
        ])
    }

    static var archiveAfter: ArchiveInterval {
        ArchiveInterval(rawValue: UserDefaults.standard.integer(forKey: archiveAfterKey)) ?? .week
    }
    /// Ads and trackers (`ContentBlocking`); applies to pages opened after it changes.
    static var blockTrackers: Bool { UserDefaults.standard.bool(forKey: blockTrackersKey) }
    static var skipsPinnedRemovalWarning: Bool { UserDefaults.standard.bool(forKey: skipsPinnedRemovalWarningKey) }
    static var searchEngine: SearchEngine {
        SearchEngine(rawValue: UserDefaults.standard.string(forKey: searchEngineKey) ?? "") ?? .duckDuckGo
    }
}
