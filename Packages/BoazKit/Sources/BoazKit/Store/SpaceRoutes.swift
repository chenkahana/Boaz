import CryptoKit
import Foundation
import GRDB

/// A site rule: new tabs for `host` (and its subdomains), optionally only under `pathPrefix`, open in `spaceID`.
/// One ordered list across every profile; the first live match by `position` wins. Synced (Mac only: the iPhone
/// stores them and never routes). The id comes from host and path, so one site has one rule on every device.
public struct SpaceRoute: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public static let databaseTableName = "spaceRoute"

    public let id: String
    /// The target space's profile.
    public var profileID: String
    public var spaceID: String
    public let host: String
    public let pathPrefix: String?
    public var position: Double
    public var modifiedAt: Date
    public var deletedAt: Date?

    /// Validates and normalizes `host` and `pathPrefix` (see `SiteEngineRule.validatedSite`).
    public init(host: String, pathPrefix: String? = nil, spaceID: String, profileID: String, position: Double,
                modifiedAt: Date = .now, deletedAt: Date? = nil) throws {
        let site = try SiteEngineRule.validatedSite(host: host, pathPrefix: pathPrefix)
        guard !spaceID.isEmpty, !profileID.isEmpty else { throw SiteEngineRule.ValidationError.invalidProfile }
        self.id = Self.identifier(host: site.host, pathPrefix: site.pathPrefix)
        self.host = site.host; self.pathPrefix = site.pathPrefix
        self.spaceID = spaceID; self.profileID = profileID; self.position = position
        self.modifiedAt = modifiedAt; self.deletedAt = deletedAt
    }

    /// `host` and `pathPrefix`, each prefixed by its UTF-8 byte count, hashed.
    static func identifier(host: String, pathPrefix: String?) -> String {
        var bytes = Data("SpaceRoute".utf8)
        for field in [host, pathPrefix ?? ""] {
            let encoded = Data(field.utf8)
            withUnsafeBytes(of: UInt64(encoded.count).bigEndian) { bytes.append(contentsOf: $0) }
            bytes.append(encoded)
        }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    /// Whether the stored fields are a rule this build would have made (records come from other devices).
    func validated() throws -> SpaceRoute {
        let site = try SiteEngineRule.validatedSite(host: host, pathPrefix: pathPrefix)
        guard site.host == host, site.pathPrefix == pathPrefix, !spaceID.isEmpty, !profileID.isEmpty,
              id == Self.identifier(host: host, pathPrefix: pathPrefix), position.isFinite
        else { throw SyncMappingError.badRecordName(id) }
        return self
    }

    private enum CodingKeys: String, CodingKey {
        case id, profileID, spaceID, host, pathPrefix, position, modifiedAt, deletedAt
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        profileID = try values.decode(String.self, forKey: .profileID)
        spaceID = try values.decode(String.self, forKey: .spaceID)
        host = try values.decode(String.self, forKey: .host)
        pathPrefix = try values.decodeIfPresent(String.self, forKey: .pathPrefix)
        position = try values.decode(Double.self, forKey: .position)
        modifiedAt = try values.decode(Date.self, forKey: .modifiedAt)
        deletedAt = try values.decodeIfPresent(Date.self, forKey: .deletedAt)
        _ = try validated()
    }

    // MARK: Matching

    /// `host` itself or any subdomain, over http(s); under `pathPrefix` when set.
    public func matches(_ url: URL) -> Bool {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let candidate = url.host()?.lowercased(),
              candidate == host || candidate.hasSuffix("." + host) else { return false }
        guard let pathPrefix else { return true }
        return url.path == pathPrefix || url.path.hasPrefix(pathPrefix + "/")
    }

    /// Whether every link this rule matches, `other` matches too (and they differ): `github.com` covers
    /// `github.com/acme` and `gist.github.com`.
    public func isCovered(by other: SpaceRoute) -> Bool {
        guard other.id != id, host == other.host || host.hasSuffix("." + other.host) else { return false }
        guard let broader = other.pathPrefix else { return true }
        guard let path = pathPrefix else { return false }
        return path == broader || path.hasPrefix(broader + "/")
    }

    /// The first live rule, in list order, that matches `url` and whose space is in `liveSpaceIDs`. Rules for a
    /// deleted space are skipped (the next fitting rule wins), never removed: restoring the space revives them.
    public static func route(for url: URL, in routes: [SpaceRoute], liveSpaceIDs: Set<String>) -> SpaceRoute? {
        routes.filter { $0.deletedAt == nil }.sorted(by: inListOrder).first {
            liveSpaceIDs.contains($0.spaceID) && $0.matches(url)
        }
    }

    public static func inListOrder(_ a: SpaceRoute, _ b: SpaceRoute) -> Bool { (a.position, a.id) < (b.position, b.id) }
}

// MARK: - Store

extension BoazStore {
    /// The live rules in list order, after every commit that changes them.
    public func spaceRouteUpdates() -> AsyncValueObservation<[SpaceRoute]> {
        ValueObservation.tracking(Self.liveRoutes).removeDuplicates().values(in: writer)
    }

    public func spaceRoutes() throws -> [SpaceRoute] { try writer.read(Self.liveRoutes) }

    static func liveRoutes(_ db: Database) throws -> [SpaceRoute] {
        try SpaceRoute.filter(Column("deletedAt") == nil).order(Column("position"), Column("id")).fetchAll(db)
    }

    /// Adds a rule, or re-points the existing rule for the same site and path (which keeps its place). A new rule
    /// goes to the end of the list, or directly above the first broader rule it overlaps (`github.com/acme` lands
    /// above `github.com`), so it is never dead on arrival.
    @discardableResult
    public func addSpaceRoute(host: String, pathPrefix: String? = nil, spaceID: String, profileID: String,
                              at date: Date = .now) throws -> SpaceRoute {
        let candidate = try SpaceRoute(host: host, pathPrefix: pathPrefix, spaceID: spaceID, profileID: profileID,
                                       position: 0, modifiedAt: date)
        return try writer.write { db in
            if var existing = try SpaceRoute.fetchOne(db, key: candidate.id), existing.deletedAt == nil {
                guard existing.spaceID != spaceID || existing.profileID != profileID else { return existing }
                existing.spaceID = spaceID; existing.profileID = profileID; existing.modifiedAt = date
                try existing.update(db)
                return existing
            }
            let routes = try Self.liveRoutes(db)
            var route = candidate
            if let index = routes.firstIndex(where: { candidate.isCovered(by: $0) }) {
                let next = routes[index].position
                let previous = index > 0 ? routes[index - 1].position : next - 1
                route.position = (previous + next) / 2
            } else {
                route.position = (routes.last?.position ?? -1) + 1
            }
            try route.save(db)
            _ = try Self.rebalanceRoutes(force: false, at: date, in: db)
            return try SpaceRoute.fetchOne(db, key: route.id) ?? route
        }
    }

    /// Points a rule at another space, keeping its place.
    public func setSpaceRoute(id: String, spaceID: String, profileID: String, at date: Date = .now) throws {
        try writer.write { db in
            guard var route = try SpaceRoute.fetchOne(db, key: id), route.deletedAt == nil,
                  route.spaceID != spaceID || route.profileID != profileID else { return }
            route.spaceID = spaceID; route.profileID = profileID; route.modifiedAt = date
            try route.update(db)
        }
    }

    /// Moves a rule directly above `beforeID`, or to the end of the list when nil.
    public func moveSpaceRoute(id: String, before beforeID: String?, at date: Date = .now) throws {
        try writer.write { db in
            let routes = try Self.liveRoutes(db)
            guard var route = routes.first(where: { $0.id == id }), beforeID != id else { return }
            let others = routes.filter { $0.id != id }
            let index = beforeID.flatMap { before in others.firstIndex { $0.id == before } } ?? others.endIndex
            let previous = index > 0 ? others[index - 1].position : nil
            let next = index < others.endIndex ? others[index].position : nil
            route.position = switch (previous, next) {
            case let (p?, n?): (p + n) / 2
            case let (p?, nil): p + 1
            case let (nil, n?): n - 1
            case (nil, nil): 0
            }
            route.modifiedAt = date
            try route.update(db)
            _ = try Self.rebalanceRoutes(force: false, at: date, in: db)
        }
    }

    /// Tombstones a rule (synced like any deletion).
    public func removeSpaceRoute(id: String, at date: Date = .now) throws {
        try writer.write { db in
            guard var route = try SpaceRoute.fetchOne(db, key: id), route.deletedAt == nil else { return }
            route.deletedAt = date; route.modifiedAt = date
            try route.update(db)
        }
    }

    /// Copies the Mac's pre-sync site rules (#98: host → space, longest host won) into the list, longest host first so
    /// today's winner stays the winner. A site that already has a rule (another Mac migrated it, or the user removed
    /// it there) is left alone; a rule whose space is unknown here was already ignored and is dropped. Returns the
    /// number copied. Throws before anything is written if a host is invalid, so the caller keeps the old rules.
    @discardableResult
    public func importSpaceHostRules(_ rules: [(host: String, spaceID: String)], at date: Date = .now) throws -> Int {
        let ordered = rules.enumerated().sorted {
            ($0.element.host.count, $1.offset) > ($1.element.host.count, $0.offset)
        }.map(\.element)
        return try writer.write { db in
            var position = (try Double.fetchOne(db, sql: "SELECT MAX(position) FROM spaceRoute WHERE deletedAt IS NULL") ?? -1) + 1
            var count = 0
            for rule in ordered {
                guard let profileID = try String.fetchOne(db, sql: "SELECT profileID FROM space WHERE id = ?",
                                                          arguments: [rule.spaceID]) else { continue }
                let route = try SpaceRoute(host: rule.host, spaceID: rule.spaceID, profileID: profileID,
                                           position: position, modifiedAt: date)
                guard try SpaceRoute.fetchOne(db, key: route.id) == nil else { continue }
                try route.insert(db)
                position += 1
                count += 1
            }
            return count
        }
    }

    static func rebalanceRoutes(force: Bool, at date: Date, in db: Database) throws -> Bool {
        let routes = try liveRoutes(db)
        guard let positions = evenPositions(routes.map(\.position), force: force) else { return false }
        for (var route, position) in zip(routes, positions) where route.position != position {
            route.position = position
            route.modifiedAt = date
            try route.update(db)
        }
        return true
    }

    // MARK: Per-tab override (this Mac only, never synced)

    /// Tabs the user moved to another space (or sent back from a routed space): never routed again.
    public func tabSpaceOverrides() throws -> Set<String> {
        try writer.read { db in Set(try String.fetchAll(db, sql: "SELECT tabID FROM tabSpaceOverride")) }
    }

    public func setTabSpaceOverride(tabID: String, profileID: String) throws {
        try writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO tabSpaceOverride(tabID, profileID) VALUES (?, ?)",
                           arguments: [tabID, profileID])
        }
    }

    /// Forgets overrides of tabs that are gone (closed, archived).
    public func pruneTabSpaceOverrides() throws {
        try writer.write { db in
            try db.execute(sql: """
                DELETE FROM tabSpaceOverride
                WHERE tabID NOT IN (SELECT id FROM sidebarItem WHERE deletedAt IS NULL)
                """)
        }
    }
}
