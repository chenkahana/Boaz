import Foundation
import GRDB

/// What a new library starts with: one "Personal" space, plus a few favorites when nothing was imported or synced.
/// Ids are fixed, so two devices that each start fresh merge into one library when they sync.
public enum StarterLibrary {
    public static let spaceID = "personal"
    static let profileID = "default"
    static let favoriteURLs = ["https://www.wikipedia.org", "https://www.youtube.com", "https://maps.apple.com"]
    /// Starter records are stamped as old as possible, so in sync's last-writer-wins merge any real edit or
    /// deletion from another device beats them.
    static let starterStamp = Date(timeIntervalSince1970: 0)

    /// Creates the Personal space when the library has no spaces. Returns whether it did.
    @discardableResult
    public static func seedIfEmpty(_ store: FolioStore, now: Date = .now) throws -> Bool {
        try store.writer.write { db in
            guard try Space.filter(Column("deletedAt") == nil).fetchCount(db) == 0 else { return false }
            let profile = try defaultProfile(db) ?? {
                let profile = Profile(id: profileID, name: "Default", isDefault: true, modifiedAt: starterStamp)
                try profile.save(db)
                return profile
            }()
            let records: [any PersistableRecord] = [
                Space(id: spaceID, title: "Personal", icon: "🏡", themeJSON: Data(theme.utf8),
                      profileID: profile.id, position: 0, modifiedAt: starterStamp),
                SidebarItem(id: "\(spaceID)-pinned", spaceID: spaceID, profileID: profile.id, parentID: nil,
                            kind: .container, containerKind: .pinned, position: 0, createdAt: now, modifiedAt: starterStamp),
                SidebarItem(id: "\(spaceID)-today", spaceID: spaceID, profileID: profile.id, parentID: nil,
                            kind: .container, containerKind: .unpinned, position: 1, createdAt: now, modifiedAt: starterStamp),
            ]
            for record in records { try record.save(db) }
            return true
        }
    }

    /// Ends first-run setup: removes the Personal space if other spaces arrived from an import and it is still
    /// empty, and adds the starter favorites if the library has no tabs at all.
    ///
    /// With sync on, Personal stays and no favorites are added: this device can't yet tell an empty library from one
    /// whose contents haven't arrived, and either change would reach every device.
    public static func finishSetup(_ store: FolioStore, syncing: Bool, now: Date = .now) throws {
        try store.writer.write { db in
            let live = Column("deletedAt") == nil
            let tabs = try SidebarItem.filter(live && Column("kind") == SidebarItem.Kind.tab.rawValue).fetchCount(db)
            if var space = try Space.filter(live && Column("id") == spaceID).fetchOne(db),
               !syncing, try Space.filter(live).fetchCount(db) > 1 {
                let containers = try SidebarItem.filter(live && Column("spaceID") == spaceID && Column("kind") == "container").fetchAll(db)
                let contents = try SidebarItem.filter(live && containers.map(\.id).contains(Column("parentID"))).fetchCount(db)
                if contents == 0 {
                    for var container in containers { container.deletedAt = now; container.modifiedAt = now; try container.update(db) }
                    space.deletedAt = now; space.modifiedAt = now
                    try space.update(db)
                }
            }
            guard tabs == 0, !syncing, let profile = try defaultProfile(db) else { return }
            let container = try SidebarItem.filter(live && Column("containerKind") == SidebarItem.ContainerKind.favorites.rawValue
                                                   && Column("profileID") == profile.id).fetchOne(db)
                ?? SidebarItem(id: "starter-favorites", spaceID: nil, profileID: profile.id, parentID: nil,
                               kind: .container, containerKind: .favorites, position: 0, createdAt: now, modifiedAt: starterStamp)
            try container.save(db)
            for (index, address) in favoriteURLs.enumerated() {
                let id = "starter-favorite-\(index)"
                // Never revive one the user removed (here or, via sync, elsewhere).
                guard try SidebarItem.fetchOne(db, key: id) == nil else { continue }
                let url = URL(string: address)!
                try SidebarItem(id: id, spaceID: nil, profileID: profile.id, parentID: container.id,
                                kind: .tab, title: url.host(), url: url, position: Double(index), createdAt: now, modifiedAt: starterStamp)
                    .save(db)
            }
        }
    }

    /// Whether the library holds spaces or tabs of the user's own, beyond these starter records and the sample
    /// library development builds used to seed (`fav-N`, `space-N…`).
    public static func hasUserContent(_ store: FolioStore) throws -> Bool {
        try store.writer.read { db in
            try String.fetchAll(db, sql: """
                SELECT id FROM space WHERE deletedAt IS NULL
                UNION ALL SELECT id FROM sidebarItem WHERE deletedAt IS NULL AND kind = 'tab'
                """).contains { !isSeeded($0) }
        }
    }

    static func isSeeded(_ id: String) -> Bool {
        if id == spaceID || id.hasPrefix("starter-") { return true }
        let parts = id.split(separator: "-")
        return parts.count >= 2 && ["fav", "space"].contains(parts[0]) && Int(parts[1]) != nil
    }

    private static func defaultProfile(_ db: Database) throws -> Profile? {
        try Profile.filter(Column("deletedAt") == nil).order(Column("isDefault").desc, Column("id")).fetchOne(db)
    }

    /// A soft periwinkle `windowTheme` in Arc's schema.
    private static let theme: String = {
        func color(_ r: Double, _ g: Double, _ b: Double) -> String {
            #"{"colorSpace":"extendedSRGB","red":\#(r),"green":\#(g),"blue":\#(b),"alpha":1}"#
        }
        return #"""
        {"semanticColorPalette":{"appearanceBased":{
          "light":{"background":\#(color(0.81, 0.81, 0.97)),"foregroundPrimary":\#(color(0, 0, 0)),"title":\#(color(0, 0, 0))},
          "dark":{"background":\#(color(0.2, 0.2, 0.29)),"foregroundPrimary":\#(color(1, 1, 1)),"title":\#(color(1, 1, 1))}}},
         "primaryColorPalette":{"midTone":\#(color(0.57, 0.57, 0.87))}}
        """#
    }()
}
