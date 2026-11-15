import BoazKit
import Foundation

/// Maps a host to a Space: links to it opened from other apps (`MacModel.openExternal`) use that space's
/// profile in the quick window, and "Open in Boaz" puts the tab there. Mac only, UserDefaults, no sync.
struct SpaceHostRule: Codable, Hashable {
    var host: String
    var spaceID: String

    /// Lowercases and trims; pulls the host out of a pasted URL. Rejects anything without a dot or a space inside.
    static func normalizeHost(_ input: String) -> String? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }
        if value.contains("://") {
            guard let components = URLComponents(string: value),
                  ["http", "https"].contains(components.scheme ?? ""),
                  let host = components.host, !host.isEmpty else { return nil }
            value = host
        } else if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }
        guard !value.isEmpty, !value.contains(" "), value.contains(".") else { return nil }
        return value
    }

    /// Same suffix logic as `SiteEngineRule.matches`: an exact host, or any subdomain of it.
    func matches(host: String) -> Bool {
        let candidate = host.lowercased()
        return candidate == self.host || candidate.hasSuffix("." + self.host)
    }
}

extension MacModel {
    private static let spaceHostRulesKey = "spaceHostRules"

    static func loadSpaceHostRules() -> [SpaceHostRule] {
        guard let data = UserDefaults.standard.data(forKey: spaceHostRulesKey) else { return [] }
        return (try? JSONDecoder().decode([SpaceHostRule].self, from: data)) ?? []
    }

    func persistSpaceHostRules() {
        UserDefaults.standard.set(try? JSONEncoder().encode(spaceHostRules), forKey: Self.spaceHostRulesKey)
    }

    /// The space a rule sends this external URL to, if any. Rules whose space no longer exists are ignored;
    /// the longest matching host wins.
    func ruleSpace(for url: URL) -> Space? {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host()?.lowercased()
        else { return nil }
        return spaceHostRules
            .filter { $0.matches(host: host) }
            .compactMap { rule in space(rule.spaceID).map { (rule.host.count, $0) } }
            .max { $0.0 < $1.0 }?.1
    }
}
