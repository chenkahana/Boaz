import Foundation
import GRDB

// Records mirror Arc's sidebar model (StorableSidebar.json): profiles own spaces, spaces own
// containers (pinned / unpinned), containers hold folders and tabs. Favorites ("top apps") are a
// per-profile container with no space.
//
// Every record carries `modifiedAt` and a `deletedAt` tombstone so CloudKit sync (Phase 2) can
// merge per record. Ordering uses a fractional `position` so concurrent inserts don't conflict.
// There are no foreign keys: sync may deliver a child before its parent.

public struct Profile: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public var id: String
    public var name: String
    /// Identifier for this profile's `WKWebsiteDataStore(forIdentifier:)`.
    public var dataStoreID: UUID
    public var isDefault: Bool
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(id: String, name: String, dataStoreID: UUID = UUID(), isDefault: Bool,
                modifiedAt: Date = .now, deletedAt: Date? = nil) {
        self.id = id; self.name = name; self.dataStoreID = dataStoreID; self.isDefault = isDefault
        self.modifiedAt = modifiedAt; self.deletedAt = deletedAt
    }
}

public struct Space: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public var id: String
    public var title: String
    /// Emoji or SF Symbol name.
    public var icon: String?
    /// Arc `windowTheme` JSON, stored verbatim so imported themes render exactly. See `WindowTheme`.
    public var themeJSON: Data?
    public var profileID: String
    public var position: Double
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(id: String, title: String, icon: String? = nil, themeJSON: Data? = nil, profileID: String,
                position: Double, modifiedAt: Date = .now, deletedAt: Date? = nil) {
        self.id = id; self.title = title; self.icon = icon; self.themeJSON = themeJSON
        self.profileID = profileID; self.position = position; self.modifiedAt = modifiedAt; self.deletedAt = deletedAt
    }

    public var theme: WindowTheme? { themeJSON.flatMap { try? WindowTheme.decode($0) } }
}

public struct SidebarItem: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public enum Kind: String, Codable, Sendable { case container, folder, tab }
    public enum ContainerKind: String, Codable, Sendable { case pinned, unpinned, favorites }

    public var id: String
    /// Nil for the per-profile favorites container and its children.
    public var spaceID: String?
    public var profileID: String
    public var parentID: String?
    public var kind: Kind
    public var containerKind: ContainerKind?
    public var title: String?
    public var url: URL?
    public var isUnread: Bool
    public var isExpanded: Bool
    public var position: Double
    public var createdAt: Date
    public var lastActiveAt: Date?
    public var modifiedAt: Date
    public var deletedAt: Date?

    public static let databaseTableName = "sidebarItem"

    public init(id: String, spaceID: String?, profileID: String, parentID: String?, kind: Kind,
                containerKind: ContainerKind? = nil, title: String? = nil, url: URL? = nil,
                isUnread: Bool = false, isExpanded: Bool = true, position: Double,
                createdAt: Date = .now, lastActiveAt: Date? = nil, modifiedAt: Date = .now, deletedAt: Date? = nil) {
        self.id = id; self.spaceID = spaceID; self.profileID = profileID; self.parentID = parentID
        self.kind = kind; self.containerKind = containerKind; self.title = title; self.url = url
        self.isUnread = isUnread; self.isExpanded = isExpanded; self.position = position
        self.createdAt = createdAt; self.lastActiveAt = lastActiveAt; self.modifiedAt = modifiedAt; self.deletedAt = deletedAt
    }
}

public struct ArchiveItem: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public var id: String
    public var profileID: String
    public var spaceID: String?
    public var title: String?
    public var url: URL
    public var archivedAt: Date
    /// e.g. "autoArchived", "closed".
    public var reason: String
    public var modifiedAt: Date
    public var deletedAt: Date?

    public static let databaseTableName = "archiveItem"

    public init(id: String, profileID: String, spaceID: String?, title: String?, url: URL, archivedAt: Date,
                reason: String, modifiedAt: Date = .now, deletedAt: Date? = nil) {
        self.id = id; self.profileID = profileID; self.spaceID = spaceID; self.title = title; self.url = url
        self.archivedAt = archivedAt; self.reason = reason; self.modifiedAt = modifiedAt; self.deletedAt = deletedAt
    }
}
