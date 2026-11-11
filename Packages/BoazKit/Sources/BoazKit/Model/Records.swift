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
    /// The `Device` a Today tab was opened on: each device's Today lists only its own tabs. Nil for pinned and
    /// favorite items, and for tabs from before devices were recorded, which show on every device. An iPhone's
    /// tabs are its mobile stack, in no space (`isMobileTab`).
    public var deviceID: String?

    public static let databaseTableName = "sidebarItem"

    /// Whether this is a tab in an iPhone's mobile stack: its device's, in no space and under no container
    /// (`Sidebar.mobileTabs(onDevice:)`). Being in no space, deleting, renaming or reordering spaces on the Mac
    /// leaves it be, and the Mac, which lists tabs by their containers, never shows it.
    public var isMobileTab: Bool { kind == .tab && spaceID == nil && parentID == nil && deviceID != nil }

    /// A tab for an iPhone's mobile stack, opened now (so it is on top), with `profileID`'s website data.
    public static func mobileTab(url: URL, title: String?, profileID: String, deviceID: String,
                                 at date: Date = .now) -> SidebarItem {
        SidebarItem(id: UUID().uuidString, spaceID: nil, profileID: profileID, parentID: nil, kind: .tab,
                    title: title ?? url.host(), url: url, position: 0, createdAt: date, lastActiveAt: date,
                    modifiedAt: date, deviceID: deviceID)
    }

    public init(id: String, spaceID: String?, profileID: String, parentID: String?, kind: Kind,
                containerKind: ContainerKind? = nil, title: String? = nil, url: URL? = nil,
                isUnread: Bool = false, isExpanded: Bool = true, position: Double,
                createdAt: Date = .now, lastActiveAt: Date? = nil, modifiedAt: Date = .now, deletedAt: Date? = nil,
                deviceID: String? = nil) {
        self.id = id; self.spaceID = spaceID; self.profileID = profileID; self.parentID = parentID
        self.kind = kind; self.containerKind = containerKind; self.title = title; self.url = url
        self.isUnread = isUnread; self.isExpanded = isExpanded; self.position = position
        self.createdAt = createdAt; self.lastActiveAt = lastActiveAt; self.modifiedAt = modifiedAt; self.deletedAt = deletedAt
        self.deviceID = deviceID
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

/// An iPhone or Mac using this library, so the others can name it ("Chen's MacBook Pro").
public struct Device: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    public enum Platform: String, Codable, Sendable { case iOS, macOS }

    public var id: String
    public var name: String
    public var platform: Platform
    /// Refreshed at launch and on returning to the foreground, not continuously.
    public var lastSeenAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public static let databaseTableName = "device"

    public init(id: String, name: String, platform: Platform, lastSeenAt: Date,
                modifiedAt: Date = .now, deletedAt: Date? = nil) {
        self.id = id; self.name = name; self.platform = platform; self.lastSeenAt = lastSeenAt
        self.modifiedAt = modifiedAt; self.deletedAt = deletedAt
    }
}
