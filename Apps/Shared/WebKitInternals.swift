import Foundation

/// What Boaz has seen go wrong with the WebKit internals it reaches into (the view behind `WebPage`, its UI delegate).
/// Those fall back quietly by design, so a WebKit update that breaks one would otherwise show up only as a log line.
/// Settings ▸ About shows `summary`; docs/architecture.md lists what to check when the SDK changes.
@MainActor
enum WebKitInternals {
    /// Feature name to the reason it fell back, for this launch.
    private(set) static var problems: [String: String] = [:]

    static func record(feature: String, reason: String) {
        problems[feature] = reason
    }

    /// "No problems seen" until a feature has fallen back; then the features that did.
    static var summary: String {
        problems.isEmpty ? "No problems seen" : "Degraded: " + problems.keys.sorted().joined(separator: ", ")
    }
}
