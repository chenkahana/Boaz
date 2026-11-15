import CryptoKit
import Foundation
import GRDB

/// What fills a live folder, synced with the folder (`SidebarItem.liveSource`). Only the user's choices live here;
/// how the last refresh went changes every minute, so it stays on the device (`LiveFolderState`).
///
/// Every field is a plain string so a record from a newer build, with a provider or filter this one doesn't know,
/// still decodes: an unknown provider shows as an ordinary folder, unknown filters are kept and ignored.
public struct LiveSource: Codable, Hashable, Sendable {
    /// GitHub pull requests (`GitHubPullFilter`).
    public static let githubPulls = "github.pulls"

    public var provider: String
    /// Enabled filters' raw values, sorted, so the same choice always encodes the same (sync compares JSON).
    public private(set) var filters: [String]
    /// "owner/name" of the only repositories to list; empty lists every repository.
    public private(set) var repositories: [String]

    public init(provider: String, filters: [String] = [], repositories: [String] = []) {
        self.provider = provider
        self.filters = Array(Set(filters)).sorted()
        self.repositories = Array(Set(repositories)).sorted()
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(provider: try c.decodeIfPresent(String.self, forKey: .provider) ?? "",
                  filters: try c.decodeIfPresent([String].self, forKey: .filters) ?? [],
                  repositories: try c.decodeIfPresent([String].self, forKey: .repositories) ?? [])
    }

    public func has(_ filter: String) -> Bool { filters.contains(filter) }

    public mutating func set(_ filter: String, enabled: Bool) {
        var set = Set(filters)
        if enabled { set.insert(filter) } else { set.remove(filter) }
        filters = set.sorted()
    }

    /// Lists only `repositories`, or every repository when empty.
    public mutating func setRepositories(_ repositories: [String]) {
        self.repositories = Array(Set(repositories)).sorted()
    }
}

/// The filters of a `LiveSource.githubPulls` folder: the searches it lists the open pull requests of.
public enum GitHubPullFilter: String, CaseIterable, Sendable {
    case createdByMe, reviewRequests, teamReviewRequests, assignedToMe, mentioned

    public var title: String {
        switch self {
        case .createdByMe: "Created by Me"
        case .reviewRequests: "Review Requests"
        case .teamReviewRequests: "Team Review Requests"
        case .assignedToMe: "Assigned to Me"
        case .mentioned: "Mentioned"
        }
    }

    /// What a new Pull Requests folder lists.
    public static let defaults: [GitHubPullFilter] = [.createdByMe, .reviewRequests]
}

extension SidebarItem {
    /// The id of the tab a live folder keeps for `url`: the same on every device (a name-based UUID, version 5), so
    /// two Macs refreshing the same folder write the same rows instead of a copy each.
    public static func liveChildID(folderID: String, url: URL) -> String {
        uuidV5(namespace: liveChildNamespace, name: folderID + "\n" + url.absoluteString).uuidString
    }

    /// Whether this tab is one its live folder made (and may remove), not one the user put there.
    public func isLiveChild(of folder: SidebarItem) -> Bool {
        guard kind == .tab, parentID == folder.id, let url else { return false }
        return id == Self.liveChildID(folderID: folder.id, url: url)
    }

    static let liveChildNamespace = UUID(uuidString: "6B1D7E8A-2F4C-4E1B-9C3A-5D7F0B2A9E41")!

    /// RFC 4122 §4.3.
    static func uuidV5(namespace: UUID, name: String) -> UUID {
        var bytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        bytes += Array(name.utf8)
        var hash = Array(Insecure.SHA1.hash(data: bytes).prefix(16))
        hash[6] = (hash[6] & 0x0F) | 0x50
        hash[8] = (hash[8] & 0x3F) | 0x80
        return hash.withUnsafeBufferPointer { NSUUID(uuidBytes: $0.baseAddress) as UUID }
    }
}

/// How a live folder's last refresh went on this device, and the badges of its tabs. Never synced: it changes on
/// every refresh, and each device refreshes on its own.
public struct LiveFolderState: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    /// One listed item's status, for its row's badge.
    public struct ItemStatus: Codable, Hashable, Sendable {
        public enum Checks: String, Codable, Sendable { case success, failure, pending }
        /// Nil when the item has no checks.
        public var checks: Checks?
        /// GitHub's review decision ("APPROVED", "CHANGES_REQUESTED", "REVIEW_REQUIRED"), if any.
        public var review: String?
        public var isDraft: Bool
        /// "owner/name #123", for the row's tooltip.
        public var detail: String?

        public init(checks: Checks? = nil, review: String? = nil, isDraft: Bool = false, detail: String? = nil) {
            self.checks = checks; self.review = review; self.isDraft = isDraft; self.detail = detail
        }
    }

    /// An organization whose results GitHub held back until the user authorizes single sign-on for it.
    public struct SingleSignOn: Codable, Hashable, Sendable {
        public var organization: String
        public var url: URL
        public init(organization: String, url: URL) { self.organization = organization; self.url = url }
    }

    public var folderID: String
    public var lastRefreshAt: Date?
    /// Why the last refresh failed; nil after one that worked.
    public var lastError: String?
    /// Keyed by child tab id.
    public var items: [String: ItemStatus]
    /// Repositories seen in results, for the Repositories menu.
    public var repositories: [String]
    public var singleSignOn: [SingleSignOn]

    public static let databaseTableName = "liveFolderState"

    public init(folderID: String, lastRefreshAt: Date? = nil, lastError: String? = nil,
                items: [String: ItemStatus] = [:], repositories: [String] = [], singleSignOn: [SingleSignOn] = []) {
        self.folderID = folderID; self.lastRefreshAt = lastRefreshAt; self.lastError = lastError
        self.items = items; self.repositories = repositories; self.singleSignOn = singleSignOn
    }
}

extension BoazStore {
    /// Every live folder's last refresh on this device, by folder id.
    public func liveFolderStates() async throws -> [String: LiveFolderState] {
        try await writer.read { db in
            Dictionary(try LiveFolderState.fetchAll(db).map { ($0.folderID, $0) }, uniquingKeysWith: { $1 })
        }
    }

    /// Saves (or, with `nil`, forgets) a live folder's refresh state without waiting for the database.
    public func setLiveFolderState(_ state: LiveFolderState?, folderID: String) {
        writeInBackground { db in
            if let state { try state.save(db) } else { _ = try LiveFolderState.deleteOne(db, key: folderID) }
        }
    }
}
