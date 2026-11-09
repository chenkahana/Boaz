import CryptoKit
import Foundation
import GRDB
import Security

/// Imports Arc desktop's sidebar (`StorableSidebar.json`) into the Boaz store.
///
/// Arc keeps the sidebar in `sidebar.containers[1]`: `spaces` and `items` are flat arrays that alternate
/// `id, object, id, object`. Items form a tree through `parentID` / `childrenIds` (the order source).
/// Root items are containers: `spaceItems` (a space's pinned or unpinned section, told apart by the
/// space's `containerIDs`) and `topApps` (favorites, one per profile and Mac).
/// Folder expansion lives in `StorableWindows.json` (`expandedItems`); profile names in `User Data/Local State`.
///
/// Import is idempotent: every Boaz id is derived from the Arc id (`arc-<id>`), re-import updates rows in
/// place, unchanged rows are not rewritten, and Arc-derived rows that vanished from Arc are tombstoned.
/// Rows created in Boaz (ids without the `arc-` prefix) are never touched.
public struct ArcSidebarImporter: Sendable {
    public static let idPrefix = "arc-"

    public let sidebarJSON: Data
    public let windowsJSON: Data?
    public let localStateJSON: Data?
    /// Arc's data folder, when read from disk; needed for `cachedFavicons(for:)`.
    public let arcFolder: URL?

    public init(sidebarJSON: Data, windowsJSON: Data? = nil, localStateJSON: Data? = nil, arcFolder: URL? = nil) {
        self.sidebarJSON = sidebarJSON; self.windowsJSON = windowsJSON; self.localStateJSON = localStateJSON
        self.arcFolder = arcFolder
    }

    /// Reads the files from Arc's data folder (`~/Library/Application Support/Arc`).
    public init(arcFolder: URL) throws {
        let sidebar = arcFolder.appendingPathComponent("StorableSidebar.json")
        guard let data = try? Data(contentsOf: sidebar) else { throw ArcImportError.missingFile(sidebar.lastPathComponent) }
        self.init(sidebarJSON: data,
                  windowsJSON: try? Data(contentsOf: arcFolder.appendingPathComponent("StorableWindows.json")),
                  localStateJSON: try? Data(contentsOf: arcFolder.appendingPathComponent("User Data/Local State")),
                  arcFolder: arcFolder)
    }

    public static func boazID(_ arcID: String) -> String { idPrefix + arcID }

    /// Boaz profile id for an Arc profile directory ("Default", "Profile 1", …). The same on every Mac, so a
    /// space keeps its profile whichever Mac imports it.
    public static func profileID(directory: String) -> String {
        idPrefix + "profile-" + directory.lowercased().replacingOccurrences(of: " ", with: "-")
    }

    // MARK: Parse

    public func parse() throws -> ArcSnapshot {
        guard let root = try JSONSerialization.jsonObject(with: sidebarJSON) as? [String: Any],
              let containers = (root["sidebar"] as? [String: Any])?["containers"] as? [Any],
              let body = containers.lazy.compactMap({ $0 as? [String: Any] }).first(where: { $0["items"] != nil }),
              let rawItems = body["items"] as? [Any], let rawSpaces = body["spaces"] as? [Any]
        else { throw ArcImportError.unsupportedFormat("StorableSidebar.json has no sidebar.containers[].items") }

        let arcItems = rawItems.compactMap { $0 as? [String: Any] }
        var byID: [String: [String: Any]] = [:]
        for item in arcItems { if let id = item["id"] as? String { byID[id] = item } }
        let arcSpaces = rawSpaces.compactMap { $0 as? [String: Any] }

        let names = profileNames()
        let expanded = expandedFolderIDs()

        // Profiles: referenced by spaces; the Mac those references point at is "this" Mac.
        let spaceProfiles = arcSpaces.map { ArcProfileRef($0["profile"]) }
        let localMachine = Dictionary(grouping: spaceProfiles.compactMap(\.machineID), by: { $0 })
            .max { $0.value.count < $1.value.count }?.key

        // Favorites: one topApps container per profile and Mac. Prefer this Mac's (or the machine-less
        // default profile's), then the fullest. Arc only shows a profile's favorites in that profile's spaces,
        // so a profile without spaces (often the unused "Default") stays behind.
        let spaceDirectories = Set(spaceProfiles.map(\.directory))
        var candidates: [String: [(item: [String: Any], ref: ArcProfileRef, local: Bool)]] = [:]
        for item in arcItems where item["parentID"] as? String == nil {
            guard let topApps = Self.topAppsProfile(item) else { continue }
            let ref = ArcProfileRef(topApps)
            guard spaceDirectories.isEmpty || spaceDirectories.contains(ref.directory) else { continue }
            candidates[ref.directory, default: []].append((item, ref, ref.machineID == nil || ref.machineID == localMachine))
        }
        let favoritesByProfile = candidates.compactMapValues { list in
            list.max { a, b in
                a.local != b.local ? !a.local : Self.children(a.item).count < Self.children(b.item).count
            }?.item
        }
        // Other machines' favorites containers that showed up as losing candidates: never tombstone these
        // (this Mac didn't look at that machine's own data this run, so it can't tell they're still live there).
        var foreignFavoritesIDs = Set<String>()
        for (item, _, local) in candidates.values.flatMap({ $0 }) where !local {
            if let id = item["id"] as? String { foreignFavoritesIDs.formUnion(Self.descendantIDs(of: id, byID: byID).map(Self.boazID)) }
        }

        var snapshot = ArcSnapshot()
        snapshot.foreignFavoritesIDs = foreignFavoritesIDs
        snapshot.localProfileDirectories = Set(spaceProfiles.filter { $0.machineID == nil || $0.machineID == localMachine }.map(\.directory))
            .union(candidates.filter { $0.value.contains(where: \.local) }.keys)
        func resolvedProfileID(_ directory: String) -> String { Self.profileID(directory: directory) }
        var directories = spaceProfiles.map(\.directory)
        directories += favoritesByProfile.keys.sorted()
        for directory in directories where snapshot.profileDirectories[resolvedProfileID(directory)] == nil {
            let id = resolvedProfileID(directory)
            snapshot.profileDirectories[id] = directory
            snapshot.profiles.append(Profile(id: id, name: names[directory] ?? directory, isDefault: directory == "Default"))
        }

        // Walk a container's subtree in Arc's child order. A split view's tabs become siblings in its place.
        // Each Arc item is taken once, at its first place in that order: a damaged file can list an item twice,
        // under two parents, or inside itself, which would duplicate rows or recurse forever. Nesting deeper than
        // `maxDepth` (Arc nests a few levels) is skipped rather than overflowing the stack.
        var visited = Set<String>()
        func walk(_ parent: [String: Any], boazParent: String, spaceID: String?, profileID: String, section: SidebarItem.ContainerKind,
                  position: inout Int, depth: Int = 0) {
            guard depth < Self.maxDepth else { snapshot.skippedItems += Self.children(parent).count; return }
            for childID in Self.children(parent) {
                guard let child = byID[childID], let data = child["data"] as? [String: Any],
                      visited.insert(childID).inserted else { continue }
                let createdAt = Self.date(child["createdAt"]) ?? .now
                let isUnread = child["isUnread"] as? Bool ?? false
                // `title` is the name the user gave the item in Arc; `savedTitle` is the page's own title.
                let customTitle = (child["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let index = position
                if let tab = data["tab"] as? [String: Any] {
                    guard let string = tab["savedURL"] as? String, let url = URL(string: string),
                          ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { snapshot.skippedTabs += 1; continue }
                    position += 1
                    snapshot.items.append(SidebarItem(
                        id: Self.boazID(childID), spaceID: spaceID, profileID: profileID, parentID: boazParent,
                        kind: .tab, title: customTitle ?? tab["savedTitle"] as? String, url: url, isUnread: isUnread,
                        position: Double(index), createdAt: createdAt,
                        lastActiveAt: Self.date(tab["timeLastActiveAt"])))
                    snapshot.tabCounts[section, default: 0] += 1
                } else if data["list"] != nil {
                    let folderID = Self.boazID(childID)
                    snapshot.items.append(SidebarItem(
                        id: folderID, spaceID: spaceID, profileID: profileID, parentID: boazParent, kind: .folder,
                        title: customTitle, isUnread: isUnread, isExpanded: expanded?.contains(childID) ?? true,
                        position: Double(index), createdAt: createdAt))
                    snapshot.folders += 1
                    position += 1
                    var inner = 0
                    walk(child, boazParent: folderID, spaceID: spaceID, profileID: profileID, section: section, position: &inner,
                         depth: depth + 1)
                } else if data["splitView"] != nil || !Self.children(child).isEmpty {
                    snapshot.splitViews += 1
                    walk(child, boazParent: boazParent, spaceID: spaceID, profileID: profileID, section: section,
                         position: &position, depth: depth + 1)
                } else {
                    snapshot.skippedItems += 1  // easels, notes and other Arc-only items
                }
            }
        }

        for (index, space) in arcSpaces.enumerated() {
            guard let arcID = space["id"] as? String, !snapshot.spaces.contains(where: { $0.id == Self.boazID(arcID) })
            else { continue }
            let spaceID = Self.boazID(arcID)
            let profileID = resolvedProfileID(spaceProfiles[index].directory)
            let info = space["customInfo"] as? [String: Any]
            snapshot.spaces.append(Space(id: spaceID, title: space["title"] as? String ?? "Space",
                                         icon: Self.icon(info?["iconType"]), themeJSON: Self.verbatimJSON(info?["windowTheme"]),
                                         profileID: profileID, position: Double(index)))
            for (kind, containerID) in Self.sections(of: space) {
                guard let container = byID[containerID], visited.insert(containerID).inserted else { continue }
                let boazContainer = Self.boazID(containerID)
                snapshot.items.append(SidebarItem(
                    id: boazContainer, spaceID: spaceID, profileID: profileID, parentID: nil, kind: .container,
                    containerKind: kind, position: kind == .pinned ? 0 : 1,
                    createdAt: Self.date(container["createdAt"]) ?? .now))
                var position = 0
                walk(container, boazParent: boazContainer, spaceID: spaceID, profileID: profileID, section: kind, position: &position)
            }
        }

        for (directory, container) in favoritesByProfile.sorted(by: { $0.key < $1.key }) {
            guard let containerID = container["id"] as? String, visited.insert(containerID).inserted else { continue }
            let profileID = resolvedProfileID(directory)
            let boazContainer = Self.boazID(containerID)
            snapshot.items.append(SidebarItem(
                id: boazContainer, spaceID: nil, profileID: profileID, parentID: nil, kind: .container,
                containerKind: .favorites, position: 0,
                createdAt: Self.date(container["createdAt"]) ?? .now))
            var position = 0
            walk(container, boazParent: boazContainer, spaceID: nil, profileID: profileID, section: .favorites, position: &position)
        }
        return snapshot
    }

    // MARK: Favicons

    /// Arc's own favicons for the snapshot's tabs, keyed by page URL. Arc caches one PNG per sidebar item in
    /// `SidebarItemsFaviconCache`, named by the MD5 of the item id.
    public func cachedFavicons(for snapshot: ArcSnapshot) -> [URL: Data] {
        guard let cache = arcFolder?.appendingPathComponent("SidebarItemsFaviconCache", isDirectory: true) else { return [:] }
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        var icons: [URL: Data] = [:]
        for item in snapshot.items where item.kind == .tab {
            guard let url = item.url, icons[url] == nil else { continue }
            let name = Insecure.MD5.hash(data: Data(item.id.dropFirst(Self.idPrefix.count).utf8))
                .map { String(format: "%02x", $0) }.joined()
            let file = cache.appendingPathComponent(name)
            guard let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size < 512 * 1024,
                  let data = try? Data(contentsOf: file), data.starts(with: png) else { continue }
            icons[url] = data
        }
        return icons
    }

    // MARK: Import

    /// Merges `snapshot` (or Arc's data, parsed now) into `store` in one transaction.
    @discardableResult
    public func importInto(_ store: BoazStore, snapshot: ArcSnapshot? = nil, now: Date = .now) throws -> ArcImportSummary {
        let snapshot = try snapshot ?? parse()
        return try store.writer.write { db in try Self.merge(snapshot, into: db, now: now) }
    }

    static func merge(_ snapshot: ArcSnapshot, into db: Database, now: Date) throws -> ArcImportSummary {
        var summary = ArcImportSummary(snapshot)

        func upsert<R: FetchableRecord & PersistableRecord & Equatable & ArcMergeable>(_ record: R, existing: R?) throws {
            var record = record
            guard let existing else {
                record.modifiedAt = now
                try record.insert(db); summary.inserted += 1; return
            }
            // The user removed this row in Boaz; don't resurrect it from Arc.
            guard existing.deletedAt == nil else { summary.removed += 1; return }
            record.adopt(existing)
            record.modifiedAt = existing.modifiedAt
            // Compare as stored: the database keeps dates at millisecond precision.
            if try R(row: Row(record.databaseDictionary)) == existing { summary.unchanged += 1; return }
            record.modifiedAt = now
            try record.update(db); summary.updated += 1
        }

        for profile in snapshot.profiles { try upsert(profile, existing: try Profile.fetchOne(db, key: profile.id)) }
        for space in snapshot.spaces { try upsert(space, existing: try Space.fetchOne(db, key: space.id)) }
        for item in snapshot.items { try upsert(item, existing: try SidebarItem.fetchOne(db, key: item.id)) }

        // Tombstone Arc-derived rows of the imported profiles that Arc no longer has. Another machine's
        // favorites, present in this parse only as a losing candidate, are never stale here (see
        // `ArcSnapshot.foreignFavoritesIDs`).
        let profileIDs = Array(snapshot.profileDirectories.keys)
        let liveItems = Set(snapshot.items.map(\.id)), liveSpaces = Set(snapshot.spaces.map(\.id))
        let staleItems = try SidebarItem
            .filter(Column("deletedAt") == nil && profileIDs.contains(Column("profileID")) && Column("id").like(idPrefix + "%"))
            .fetchAll(db).filter { !liveItems.contains($0.id) && !snapshot.foreignFavoritesIDs.contains($0.id) }

        // Before tombstoning, move any live Boaz-made child (not re-imported from Arc, so not itself stale)
        // out from under its about-to-be-tombstoned parent, so it doesn't become invisible. Every row already
        // carries its own spaceID/profileID, so this works at any depth without walking the tree.
        let staleIDs = Set(staleItems.map(\.id))
        if !staleIDs.isEmpty {
            let orphans = try SidebarItem
                .filter(Column("deletedAt") == nil && staleIDs.contains(Column("parentID")))
                .fetchAll(db).filter { !staleIDs.contains($0.id) }
            var containerBySection: [String: String?] = [:]
            var favoritesByOrphanProfile: [String: String?] = [:]
            for var orphan in orphans {
                let destination: String?
                if let spaceID = orphan.spaceID {
                    // Stay in the same section: a pinned row moved into Today would be auto-archived.
                    var section = SidebarItem.ContainerKind.unpinned
                    var ancestorID = orphan.parentID, seen = Set<String>()
                    while let id = ancestorID, seen.insert(id).inserted, let ancestor = try SidebarItem.fetchOne(db, key: id) {
                        if ancestor.kind == .container { section = ancestor.containerKind ?? .unpinned; break }
                        ancestorID = ancestor.parentID
                    }
                    let key = spaceID + "/" + section.rawValue
                    if let cached = containerBySection[key] { destination = cached }
                    else {
                        let found = try SidebarItem
                            .filter(Column("spaceID") == spaceID && Column("kind") == SidebarItem.Kind.container.rawValue
                                    && Column("containerKind") == section.rawValue
                                    && Column("deletedAt") == nil)
                            .fetchAll(db).first { !staleIDs.contains($0.id) }?.id
                        containerBySection[key] = found; destination = found
                    }
                } else if let cached = favoritesByOrphanProfile[orphan.profileID] {
                    destination = cached
                } else {
                    let found = try SidebarItem
                        .filter(Column("profileID") == orphan.profileID && Column("kind") == SidebarItem.Kind.container.rawValue
                                && Column("containerKind") == SidebarItem.ContainerKind.favorites.rawValue
                                && Column("deletedAt") == nil)
                        .fetchAll(db).first { !staleIDs.contains($0.id) }?.id
                    favoritesByOrphanProfile[orphan.profileID] = found; destination = found
                }
                guard let destination else { continue }  // no live container to move it to; leave as is
                orphan.parentID = destination
                orphan.modifiedAt = now
                try orphan.update(db)
            }
        }

        for var item in staleItems {
            item.deletedAt = now; item.modifiedAt = now
            try item.update(db); summary.removed += 1
        }
        let staleSpaces = try Space
            .filter(Column("deletedAt") == nil && profileIDs.contains(Column("profileID")) && Column("id").like(idPrefix + "%"))
            .fetchAll(db).filter { !liveSpaces.contains($0.id) }
        for var space in staleSpaces {
            space.deletedAt = now; space.modifiedAt = now
            try space.update(db); summary.removed += 1
        }
        return summary
    }

    // MARK: Arc format helpers

    static func children(_ item: [String: Any]) -> [String] { item["childrenIds"] as? [String] ?? [] }

    /// An Arc timestamp (seconds since 2001), or nil when it is missing or outside years 1–9999: the store keeps
    /// dates as text in that range, and a row it can't read back breaks every read of its table.
    static func date(_ value: Any?) -> Date? {
        guard let seconds = value as? Double else { return nil }
        let date = Date(timeIntervalSinceReferenceDate: seconds)
        return (-62_135_596_800...253_402_300_799).contains(date.timeIntervalSince1970) ? date : nil
    }

    /// Deepest folder nesting imported. Arc nests a few levels; this only stops damaged files.
    static let maxDepth = 64

    /// `id` and every id nested beneath it, following `childrenIds` (cycles included, each id once).
    static func descendantIDs(of id: String, byID: [String: [String: Any]]) -> Set<String> {
        var result: Set<String> = [id], stack = [id]
        while let next = stack.popLast() {
            for child in byID[next].map(children) ?? [] where result.insert(child).inserted { stack.append(child) }
        }
        return result
    }

    static func topAppsProfile(_ item: [String: Any]) -> Any? {
        ((((item["data"] as? [String: Any])?["itemContainer"] as? [String: Any])?["containerType"] as? [String: Any])?["topApps"]
            as? [String: Any])?["_0"]
    }

    /// `containerIDs` alternates a section name and a container id: `["pinned", id, "unpinned", id]`.
    /// Newer files also carry `newContainerIDs`, where the name is an object key (`{"unpinned": {...}}`).
    static func sections(of space: [String: Any]) -> [(SidebarItem.ContainerKind, String)] {
        func pairs(_ list: [Any]?) -> [(SidebarItem.ContainerKind, String)] {
            guard let list else { return [] }
            return stride(from: 0, to: list.count - 1, by: 2).compactMap { i in
                let name = list[i] as? String ?? (list[i] as? [String: Any])?.keys.first
                guard let id = list[i + 1] as? String else { return nil }
                switch name {
                case "pinned": return (.pinned, id)
                case "unpinned": return (.unpinned, id)
                default: return nil
                }
            }
        }
        let result = pairs(space["containerIDs"] as? [Any])
        return (result.isEmpty ? pairs(space["newContainerIDs"] as? [Any]) : result)
            .sorted { ($0.0 == .pinned ? 0 : 1) < ($1.0 == .pinned ? 0 : 1) }
    }

    /// `{"emoji_v2": "😊", "emoji": 128522}` or `{"icon": "<SF Symbol>"}`.
    static func icon(_ value: Any?) -> String? {
        guard let info = value as? [String: Any] else { return nil }
        if let emoji = info["emoji_v2"] as? String, !emoji.isEmpty { return emoji }
        if let code = info["emoji"] as? Int, let scalar = Unicode.Scalar(code) { return String(Character(scalar)) }
        if let icon = info["icon"] as? String { return icon }
        return nil
    }

    /// Re-serializes Arc's theme object unchanged (sorted keys, so re-imports compare equal).
    static func verbatimJSON(_ value: Any?) -> Data? {
        guard let value = value as? [String: Any], !value.isEmpty else { return nil }
        return try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    /// Arc profile directory → display name, from Chromium's `Local State` (`profile.info_cache`).
    func profileNames() -> [String: String] {
        guard let localStateJSON,
              let state = try? JSONSerialization.jsonObject(with: localStateJSON) as? [String: Any],
              let cache = (state["profile"] as? [String: Any])?["info_cache"] as? [String: Any] else { return [:] }
        return cache.compactMapValues { ($0 as? [String: Any])?["name"] as? String }
    }

    /// Folders Arc shows expanded in its first window. Nil when the windows file is unavailable.
    func expandedFolderIDs() -> Set<String>? {
        guard let windowsJSON,
              let root = try? JSONSerialization.jsonObject(with: windowsJSON) as? [String: Any],
              let window = (root["windows"] as? [Any])?.lazy.compactMap({ $0 as? [String: Any] }).first,
              let list = window["expandedItems"] as? [Any] else { return nil }
        var ids = Set<String>()
        for i in stride(from: 0, to: list.count - 1, by: 2) {
            if let id = list[i] as? String, (list[i + 1] as? [String: Any])?["expanded"] != nil { ids.insert(id) }
        }
        return ids
    }
}

/// Records the importer merges; `adopt` keeps local-only state across re-imports.
protocol ArcMergeable {
    var modifiedAt: Date { get set }
    var deletedAt: Date? { get }
    mutating func adopt(_ existing: Self)
}

extension Profile: ArcMergeable {
    /// Keeps the profile's website data store (cookies, storage) stable.
    mutating func adopt(_ existing: Profile) { dataStoreID = existing.dataStoreID }
}

extension Space: ArcMergeable {
    mutating func adopt(_ existing: Space) {}
}

extension SidebarItem: ArcMergeable {
    /// An Arc item's creation date never changes; keeping the stored one also keeps re-import idempotent when
    /// Arc's file has none (the parse then falls back to now).
    mutating func adopt(_ existing: SidebarItem) { createdAt = existing.createdAt }
}

/// Arc's profile reference: `{"default": true}` or `{"custom": {"_0": {"directoryBasename": "Profile 1", "machineID": …}}}`.
struct ArcProfileRef {
    var directory = "Default"
    var machineID: String?

    init(_ value: Any?) {
        if let custom = ((value as? [String: Any])?["custom"] as? [String: Any])?["_0"] as? [String: Any] {
            directory = custom["directoryBasename"] as? String ?? "Default"
            machineID = custom["machineID"] as? String
        }
    }
}

/// What Arc's files map to in Boaz, before merging into the store.
public struct ArcSnapshot: Sendable {
    public var profiles: [Profile] = []
    /// Boaz profile id → Arc profile directory under `User Data` ("Default", "Profile 1", …).
    public var profileDirectories: [String: String] = [:]
    /// Arc profile directories that belong to this Mac. A space synced from another Mac may name "Profile 1"
    /// for a different profile than this Mac's "Profile 1", so credentials are only read from these.
    public var localProfileDirectories: Set<String> = []
    /// Boaz ids of another Mac's favorites container(s) and their contents, seen in this parse but not
    /// imported (this Mac's own favorites container for that profile won instead). Excluded from the
    /// tombstone pass: this Mac never looked at that machine's own data, so it can't tell they're still live.
    var foreignFavoritesIDs: Set<String> = []
    public var spaces: [Space] = []
    /// Containers, folders and tabs; children in Arc's order with positions 0, 1, 2, …
    public var items: [SidebarItem] = []
    public var folders = 0
    public var tabCounts: [SidebarItem.ContainerKind: Int] = [:]
    /// Tabs whose URL Boaz can't open (e.g. `arc://`).
    public var skippedTabs = 0
    /// Items with no Boaz equivalent (easels, notes).
    public var skippedItems = 0
    /// Split views, whose tabs were imported side by side as ordinary tabs.
    public var splitViews = 0
}

public struct ArcImportSummary: Sendable, Equatable {
    public var profiles = 0, spaces = 0, containers = 0, folders = 0
    public var favoriteTabs = 0, pinnedTabs = 0, unpinnedTabs = 0
    public var skippedTabs = 0, skippedItems = 0, splitViews = 0
    /// Row-level merge result.
    public var inserted = 0, updated = 0, unchanged = 0, removed = 0
    /// Boaz profile id → Arc profile directory, for the cookie and password importers.
    public var profileDirectories: [String: String] = [:]
    /// See `ArcSnapshot.localProfileDirectories`.
    public var localProfileDirectories: Set<String> = []

    public var tabs: Int { favoriteTabs + pinnedTabs + unpinnedTabs }

    init(_ snapshot: ArcSnapshot) {
        profiles = snapshot.profiles.count
        spaces = snapshot.spaces.count
        containers = snapshot.items.filter { $0.kind == .container }.count
        folders = snapshot.folders
        favoriteTabs = snapshot.tabCounts[.favorites] ?? 0
        pinnedTabs = snapshot.tabCounts[.pinned] ?? 0
        unpinnedTabs = snapshot.tabCounts[.unpinned] ?? 0
        skippedTabs = snapshot.skippedTabs
        skippedItems = snapshot.skippedItems
        splitViews = snapshot.splitViews
        profileDirectories = snapshot.profileDirectories
        localProfileDirectories = snapshot.localProfileDirectories
    }
}

public enum ArcImportError: Error, LocalizedError, Equatable {
    case missingFile(String)
    case unsupportedFormat(String)
    case keychain(OSStatus)
    case decryption(String)

    public var errorDescription: String? {
        switch self {
        case .missingFile(let name): "Couldn't read \(name). Choose Arc's data folder (~/Library/Application Support/Arc)."
        case .unsupportedFormat(let detail): "Arc's data is in an unexpected format: \(detail)."
        case .keychain(let status):
            "Couldn't read Arc's encryption key from the Keychain (\(SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"))."
        case .decryption(let detail): "Couldn't decrypt Arc's data: \(detail)."
        }
    }
}
