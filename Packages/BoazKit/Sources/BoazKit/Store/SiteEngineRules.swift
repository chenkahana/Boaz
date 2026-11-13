import Foundation
import GRDB

public enum StoredBrowserEngine: String, Codable, Sendable {
    case chromium, webkit
}

/// Persistent routing preferences; private browsing never writes these rules.
public struct SiteEngineRule: Codable, Equatable, Sendable {
    public enum Reason: String, Codable, Sendable { case user, protectedMedia }
    public enum ValidationError: Error { case invalidProfile, invalidHost, invalidPath }
    public let profileID: String
    public let host: String
    public let pathPrefix: String?
    public let engine: StoredBrowserEngine
    public let reason: Reason
    public let createdAt: Date

    public init(profileID: String, host: String, pathPrefix: String? = nil,
                engine: StoredBrowserEngine, reason: Reason, createdAt: Date = .now) throws {
        guard !profileID.isEmpty, !profileID.contains("\0") else { throw ValidationError.invalidProfile }
        let normalized = host.lowercased()
        let labels = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard normalized.utf8.count <= 253, !labels.isEmpty,
              labels.allSatisfy({ label in
                  !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
                  label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
              }) else { throw ValidationError.invalidHost }
        // IP literals are not site suffix rules. Callers must use a DNS hostname.
        guard !labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { throw ValidationError.invalidHost }
        var path = pathPrefix
        if var value = path {
            guard value.hasPrefix("/"), !value.contains("?"), !value.contains("#"),
                  !value.contains("\\"), !value.contains("%"),
                  !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),
                  !value.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." })
            else { throw ValidationError.invalidPath }
            while value.count > 1 && value.hasSuffix("/") { value.removeLast() }
            path = value == "/" ? nil : value
        }
        self.profileID = profileID; self.host = normalized; self.pathPrefix = path
        self.engine = engine; self.reason = reason; self.createdAt = createdAt
    }

    public func matches(_ url: URL) -> Bool {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let candidate = url.host()?.lowercased(),
              candidate == host || candidate.hasSuffix("." + host) else { return false }
        guard let pathPrefix else { return true }
        return url.path == pathPrefix || url.path.hasPrefix(pathPrefix + "/")
    }

    public static func matchingRule(for url: URL, profileID: String, rules: [Self]) -> Self? {
        rules.filter { $0.profileID == profileID && $0.matches(url) }.sorted {
            if $0.reason != $1.reason { return $0.reason == .user }
            if $0.host.count != $1.host.count { return $0.host.count > $1.host.count }
            if ($0.pathPrefix?.count ?? 0) != ($1.pathPrefix?.count ?? 0) {
                return ($0.pathPrefix?.count ?? 0) > ($1.pathPrefix?.count ?? 0)
            }
            if $0.host != $1.host { return $0.host < $1.host }
            return ($0.pathPrefix ?? "") < ($1.pathPrefix ?? "")
        }.first
    }
}

extension BoazStore {
    static let protectedMediaSeedSites: [(String, String?)] = [
            ("netflix.com", nil), ("disneyplus.com", nil), ("max.com", nil),
            ("primevideo.com", nil), ("amazon.com", "/gp/video"), ("tv.apple.com", nil),
            ("open.spotify.com", nil), ("hulu.com", nil), ("peacocktv.com", nil),
            ("paramountplus.com", nil),
    ]

    /// Seed defaults never overwrite synced choices or deletion tombstones.
    public func seedProtectedMediaRules(profileID: String) throws {
        let created = Date.now
        let rules = try Self.protectedMediaSeedSites.map { host, path in
            try SiteEngineRule(profileID: profileID, host: host, pathPrefix: path,
                engine: .webkit, reason: .protectedMedia, createdAt: created)
        }
        try writer.write { db in
            let completed = try Bool.fetchOne(db,
                sql: "SELECT EXISTS(SELECT 1 FROM protectedEngineSeed WHERE profileID = ?)", arguments: [profileID])
            if completed == true { return }
            for rule in rules {
                let record = SiteEngineRuleRecord(rule: rule, modifiedAt: Date(timeIntervalSince1970: 0))
                if try SiteEngineRuleRecord.fetchOne(db, key: record.id) == nil {
                    try record.insert(db)
                }
            }
            try db.execute(sql: "INSERT INTO protectedEngineSeed (profileID, completedAt) VALUES (?, ?)",
                           arguments: [profileID, created])
        }
    }

    public func tabEngine(tabID: String, profileID: String) throws -> StoredBrowserEngine? {
        try writer.read { db in
            try String.fetchOne(db, sql: "SELECT engine FROM tabEngineChoice WHERE profileID = ? AND tabID = ?",
                arguments: [profileID, tabID]).flatMap(StoredBrowserEngine.init(rawValue:))
        }
    }

    public func setTabEngine(_ engine: StoredBrowserEngine?, tabID: String, profileID: String) throws {
        try writer.write { db in
            if let engine {
                try db.execute(sql: "INSERT OR REPLACE INTO tabEngineChoice (profileID, tabID, engine) VALUES (?, ?, ?)",
                    arguments: [profileID, tabID, engine.rawValue])
            } else {
                try db.execute(sql: "DELETE FROM tabEngineChoice WHERE profileID = ? AND tabID = ?",
                    arguments: [profileID, tabID])
            }
        }
    }

    public func siteEngineRules(profileID: String) throws -> [SiteEngineRule] {
        try writer.read { db in
            try SiteEngineRuleRecord.fetchAll(db,
                sql: "SELECT * FROM siteEngineRuleRecord WHERE profileID = ? AND deletedAt IS NULL ORDER BY host, pathPrefix, reason",
                arguments: [profileID]).map { try $0.rule() }
        }
    }

    public func siteEngineRuleUpdates() -> AsyncValueObservation<[SiteEngineRuleRecord]> {
        ValueObservation.tracking { db in
            try SiteEngineRuleRecord.fetchAll(db, sql: "SELECT * FROM siteEngineRuleRecord ORDER BY id")
        }.removeDuplicates().values(in: writer)
    }

    public func upsertSiteEngineRule(_ rule: SiteEngineRule) throws {
        let valid = try SiteEngineRule(profileID: rule.profileID, host: rule.host, pathPrefix: rule.pathPrefix,
            engine: rule.engine, reason: rule.reason, createdAt: rule.createdAt)
        try writer.write { db in
            try SiteEngineRuleRecord(rule: valid, modifiedAt: .now).save(db)
        }
    }

    public func removeSiteEngineRule(_ rule: SiteEngineRule) throws {
        let valid = try SiteEngineRule(profileID: rule.profileID, host: rule.host, pathPrefix: rule.pathPrefix,
            engine: rule.engine, reason: rule.reason, createdAt: rule.createdAt)
        let now = Date.now
        try writer.write { db in
            try SiteEngineRuleRecord(rule: valid, modifiedAt: now, deletedAt: now).save(db)
        }
    }
}
