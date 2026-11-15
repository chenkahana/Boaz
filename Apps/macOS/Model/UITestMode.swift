import AppKit

/// Launch contract for the BoazUITests suite. Inactive unless the app is launched with `-BoazUITest YES`.
enum UITestMode {
    static let isActive = UserDefaults.standard.bool(forKey: "BoazUITest")

    /// Wipes this bundle id's persisted defaults, not the `-BoazUITest YES` launch argument (a separate domain
    /// `removePersistentDomain` doesn't touch). Without this, a run inherits whatever the LAST run quit with —
    /// its window frame, which space/tab it had open (`MacModel.SavedWindow`, UserDefaults key "openWindows"),
    /// the chosen app icon — because this bundle id's UserDefaults persist across launches the same way the real
    /// app's would, while the on-disk store is a fresh temp directory every time. Call once, before anything
    /// reads a persisted default (`applicationDidFinishLaunching`, first thing).
    static func resetDefaultsIfNeeded() {
        // Only the ad hoc test build (`make uitest`), never a real install launched with the flag by mistake.
        guard isActive, let bundleID = Bundle.main.bundleIdentifier, bundleID.hasSuffix(".uitest") else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
    }

    /// `-BoazUITestAppearance light|dark` pins the app's appearance whatever the Mac is set to: `-AppleInterfaceStyle`
    /// can turn a Light Mac dark, but nothing in it turns a Dark Mac light.
    static func applyAppearanceIfNeeded() {
        guard isActive else { return }
        switch UserDefaults.standard.string(forKey: "BoazUITestAppearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
    }

    private static func path(_ key: String) -> URL? {
        guard isActive, let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else { return nil }
        return URL(fileURLWithPath: value)
    }

    /// Fresh library directory for this run, so tests never touch the user's library.
    static let storeDirectory: URL? = isActive
        ? FileManager.default.temporaryDirectory.appendingPathComponent("BoazUITest-\(ProcessInfo.processInfo.processIdentifier)")
        : nil
    /// JSON describing spaces, pinned tabs and folders to seed (`BOAZ_UITEST_FIXTURES`).
    static var fixturesURL: URL? { path("BOAZ_UITEST_FIXTURES") }
    /// Folder the Library panel lists instead of ~/Downloads (`BOAZ_UITEST_DOWNLOADS_DIR`).
    static var downloadsDirectory: URL? { path("BOAZ_UITEST_DOWNLOADS_DIR") }
    /// Canned GitHub GraphQL responses for live folders (`BOAZ_GITHUB_FIXTURE`).
    static var githubFixtureURL: URL? { path("BOAZ_GITHUB_FIXTURE") }
}
