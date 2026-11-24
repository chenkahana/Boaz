import AppKit

/// Launch contract for the BoazUITests suite. Inactive unless the app is launched with `-BoazUITest YES`, and only
/// in a test build: the ad hoc `.uitest` build (`make uitest`) or a development-channel Chromium build. A release
/// install launched with the flag stays a normal app.
enum UITestMode {
    static let isActive = UserDefaults.standard.bool(forKey: "BoazUITest") && isTestBuild

    private static var isTestBuild: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".uitest") == true
            || Bundle.main.object(forInfoDictionaryKey: "BoazDistributionChannel") as? String == "development"
    }

    /// Wipes this bundle id's persisted defaults, not the `-BoazUITest YES` launch argument (a separate domain
    /// `removePersistentDomain` doesn't touch). Without this, a run inherits whatever the LAST run quit with —
    /// its window frame, which space/tab it had open (`MacModel.SavedWindow`, UserDefaults key "openWindows"),
    /// the chosen app icon — because this bundle id's UserDefaults persist across launches the same way the real
    /// app's would, while the on-disk store is a fresh temp directory every time. Call once, before anything
    /// reads a persisted default: `MacModel.shared` does, before the model exists, since the app creates it before
    /// `applicationDidFinishLaunching`.
    static func resetDefaultsIfNeeded() {
        // Only the ad hoc test build (`make uitest`), never a real install launched with the flag by mistake.
        guard isActive, let bundleID = Bundle.main.bundleIdentifier, bundleID.hasSuffix(".uitest") else { return }
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        // Earlier runs' libraries, unless that run is still going.
        let temporary = FileManager.default.temporaryDirectory
        for name in (try? FileManager.default.contentsOfDirectory(atPath: temporary.path)) ?? []
        where name.hasPrefix("BoazUITest-") {
            guard let pid = pid_t(name.dropFirst("BoazUITest-".count)), pid != getpid(),
                  kill(pid, 0) != 0, errno == ESRCH else { continue }
            try? FileManager.default.removeItem(at: temporary.appendingPathComponent(name))
        }
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

    /// `-BoazUITestToastSeconds N` keeps toasts up for N seconds, so a test can audit one before it goes.
    static var toastSeconds: Double? {
        let seconds = UserDefaults.standard.double(forKey: "BoazUITestToastSeconds")
        return isActive && seconds > 0 ? seconds : nil
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
    /// Downloads folder instead of ~/Downloads: `BOAZ_UITEST_DOWNLOADS_DIR`, else an empty one beside the run's
    /// library, so no test reads or writes the user's Downloads.
    static var downloadsDirectory: URL? {
        path("BOAZ_UITEST_DOWNLOADS_DIR") ?? storeDirectory?.appendingPathComponent("Downloads", isDirectory: true)
    }
    /// `-BoazUITestWindowSize 720x460` opens browser windows at that content size: dragging a window's corner
    /// doesn't resize it on the CI runner.
    static var windowSize: NSSize? {
        guard isActive, let parts = UserDefaults.standard.string(forKey: "BoazUITestWindowSize")?.split(separator: "x"),
              parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]) else { return nil }
        return NSSize(width: width, height: height)
    }
    /// Canned github.com answers for live folders (`BOAZ_GITHUB_FIXTURE`, in `GitHubWeb.Answer`'s format).
    static var githubFixtureURL: URL? { path("BOAZ_GITHUB_FIXTURE") }
}
