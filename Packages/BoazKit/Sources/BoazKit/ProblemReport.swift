import Foundation

/// Report a Problem: a GitHub bug report (`.github/ISSUE_TEMPLATE/bug_report.yml`) prefilled with the build, device
/// and OS. It holds nothing the user browsed: no URLs, titles, spaces, profiles, history or logs.
public struct ProblemReport: Equatable, Sendable {
    public enum App: String, Sendable {
        case mac = "Mac"
        case iPhone
    }

    public static let crashReportHelp = "https://github.com/chenkahana/Boaz/blob/master/SUPPORT.md#sending-a-crash-report"

    public var app: App
    /// `CFBundleShortVersionString` and `CFBundleVersion`.
    public var version: String
    public var build: String
    /// `BoazDistributionChannel` from Info.plist; App Store builds have none.
    public var channel: String?
    /// `BoazCommit` from Info.plist, written at build time.
    public var commit: String?
    /// "Chromium 157.0.8103.51" on the DMG, "WebKit" in the App Store builds.
    public var engine: String
    /// `hw.model` or the iPhone's machine identifier, such as "Mac15,3".
    public var model: String
    /// Such as "macOS 26.1".
    public var system: String
    public var dark: Bool

    public init(app: App, version: String, build: String, channel: String?, commit: String?, engine: String,
                model: String, system: String, dark: Bool) {
        self.app = app
        self.version = version
        self.build = build
        self.channel = channel
        self.commit = commit
        self.engine = engine
        self.model = model
        self.system = system
        self.dark = dark
    }

    public var channelName: String {
        switch channel {
        case nil, "": "App Store"
        case "production": "DMG"
        case "development": "Development"
        case let other?: other
        }
    }

    /// The template's field ids and what goes in each. Steps and expected stay empty for the user.
    public var fields: [(id: String, value: String)] {
        let commit = commit.flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        return [
            ("app", app.rawValue),
            ("version", "\(version) (\(build)), \(channelName), commit \(commit), \(engine)"),
            ("device", "\(model), \(system)"),
            ("extra", "Appearance: \(dark ? "Dark" : "Light")\n\nTo add a crash report, see \(Self.crashReportHelp)"),
        ]
    }

    public var url: URL {
        // RFC 3986 unreserved characters only: GitHub reads "+" in a query as a space.
        let unreserved = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/chenkahana/Boaz/issues/new"
        components.percentEncodedQueryItems = ([("template", "bug_report.yml")] + fields).map { field in
            URLQueryItem(name: field.0, value: field.1.addingPercentEncoding(withAllowedCharacters: unreserved))
        }
        return components.url!
    }
}
