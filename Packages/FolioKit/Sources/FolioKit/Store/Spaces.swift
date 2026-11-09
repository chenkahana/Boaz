import Foundation
import GRDB

/// A curated space color: a light background, a deep dark-mode background and an accent. Written in Arc's
/// `windowTheme` shape, so imported Arc themes and Folio's own read the same way everywhere.
public struct SpacePalette: Identifiable, Hashable, Sendable {
    public typealias RGB = (red: Double, green: Double, blue: Double)

    public let id: String
    public let name: String
    let light: [Double]
    let dark: [Double]
    let accent: [Double]

    init(_ id: String, _ name: String, light: [Double], dark: [Double], accent: [Double]) {
        self.id = id; self.name = name; self.light = light; self.dark = dark; self.accent = accent
    }

    public var lightRGB: RGB { (light[0], light[1], light[2]) }
    public var accentRGB: RGB { (accent[0], accent[1], accent[2]) }

    public static let all: [SpacePalette] = [
        SpacePalette("lavender", "Lavender", light: [0.82, 0.81, 0.97], dark: [0.15, 0.13, 0.30], accent: [0.42, 0.36, 0.92]),
        SpacePalette("sky", "Sky", light: [0.80, 0.90, 0.99], dark: [0.09, 0.17, 0.30], accent: [0.16, 0.50, 0.93]),
        SpacePalette("mint", "Mint", light: [0.81, 0.95, 0.88], dark: [0.07, 0.22, 0.17], accent: [0.11, 0.62, 0.45]),
        SpacePalette("lime", "Lime", light: [0.90, 0.96, 0.78], dark: [0.15, 0.22, 0.07], accent: [0.42, 0.62, 0.08]),
        SpacePalette("sand", "Sand", light: [0.97, 0.93, 0.82], dark: [0.25, 0.20, 0.10], accent: [0.76, 0.55, 0.13]),
        SpacePalette("peach", "Peach", light: [0.99, 0.87, 0.80], dark: [0.29, 0.14, 0.10], accent: [0.93, 0.44, 0.27]),
        SpacePalette("rose", "Rose", light: [0.99, 0.84, 0.88], dark: [0.29, 0.10, 0.16], accent: [0.89, 0.27, 0.45]),
        SpacePalette("orchid", "Orchid", light: [0.94, 0.84, 0.97], dark: [0.24, 0.11, 0.29], accent: [0.69, 0.33, 0.84]),
        SpacePalette("teal", "Teal", light: [0.79, 0.93, 0.94], dark: [0.06, 0.20, 0.23], accent: [0.07, 0.56, 0.62]),
        SpacePalette("slate", "Slate", light: [0.88, 0.90, 0.93], dark: [0.13, 0.15, 0.19], accent: [0.38, 0.44, 0.55]),
        SpacePalette("graphite", "Graphite", light: [0.92, 0.92, 0.92], dark: [0.11, 0.11, 0.12], accent: [0.30, 0.30, 0.32]),
        SpacePalette("midnight", "Midnight", light: [0.78, 0.80, 0.93], dark: [0.05, 0.06, 0.16], accent: [0.25, 0.30, 0.78]),
    ]

    public static let defaultPalette = all[0]

    /// The palette a theme was made from, if it was one of these (compared by accent).
    public static func matching(_ themeJSON: Data?) -> SpacePalette? {
        guard let theme = themeJSON.flatMap({ try? WindowTheme.decode($0) }),
              let accent = theme.primaryColorPalette?["midTone"] else { return nil }
        return all.first { abs($0.accent[0] - accent.red) + abs($0.accent[1] - accent.green) + abs($0.accent[2] - accent.blue) < 0.02 }
    }

    /// Arc's `windowTheme` JSON for this palette.
    public var themeJSON: Data {
        func color(_ c: [Double]) -> [String: Any] {
            ["colorSpace": "extendedSRGB", "red": c[0], "green": c[1], "blue": c[2], "alpha": 1.0]
        }
        let root: [String: Any] = [
            "semanticColorPalette": ["appearanceBased": ["light": ["background": color(light)],
                                                         "dark": ["background": color(dark)]]],
            "primaryColorPalette": ["midTone": color(accent)],
        ]
        return (try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])) ?? Data()
    }

    public static func == (a: SpacePalette, b: SpacePalette) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Space management shared by both apps: every write is an ordinary local edit, so sync carries it to other devices.
extension FolioStore {
    /// Adds a space at the end of the profile's list, with its Pinned and Today sections.
    @discardableResult
    public func createSpace(title: String, icon: String?, palette: SpacePalette, profileID: String,
                            at date: Date = .now) throws -> Space {
        try writer.write { db in
            let last = try Double.fetchOne(db, sql: "SELECT MAX(position) FROM space WHERE profileID = ? AND deletedAt IS NULL",
                                           arguments: [profileID])
            let space = Space(id: UUID().uuidString, title: title, icon: icon, themeJSON: palette.themeJSON,
                              profileID: profileID, position: (last ?? -1) + 1, modifiedAt: date)
            try space.insert(db)
            for (position, kind) in [SidebarItem.ContainerKind.pinned, .unpinned].enumerated() {
                try SidebarItem(id: UUID().uuidString, spaceID: space.id, profileID: profileID, parentID: nil,
                                kind: .container, containerKind: kind, position: Double(position), createdAt: date, modifiedAt: date)
                    .insert(db)
            }
            return space
        }
    }

    /// Renames a space and changes its icon and color. A nil palette keeps the current theme (e.g. one imported from Arc).
    public func updateSpace(_ id: String, title: String, icon: String?, palette: SpacePalette?, at date: Date = .now) throws {
        try writer.write { db in
            guard var space = try Space.fetchOne(db, key: id), space.deletedAt == nil else { return }
            space.title = title
            space.icon = icon
            if let palette { space.themeJSON = palette.themeJSON }
            space.modifiedAt = date
            try space.update(db)
        }
    }

    /// Moves a space to `index` among the profile's live spaces.
    public func moveSpace(_ id: String, to index: Int, at date: Date = .now) throws {
        try writer.write { db in
            guard let moving = try Space.fetchOne(db, key: id) else { return }
            var spaces = try Space.filter(Column("profileID") == moving.profileID && Column("deletedAt") == nil)
                .order(Column("position"), Column("id")).fetchAll(db)
            guard let from = spaces.firstIndex(where: { $0.id == id }) else { return }
            let space = spaces.remove(at: from)
            spaces.insert(space, at: min(max(index, 0), spaces.count))
            for (position, var space) in spaces.enumerated() where space.position != Double(position) {
                space.position = Double(position)
                space.modifiedAt = date
                try space.update(db)
            }
        }
    }

    /// Deletes a space. Its tabs (pinned, in folders and in Today) go to the Archive, so nothing is lost.
    /// Returns how many tabs were archived. The last space of a profile can't be deleted.
    @discardableResult
    public func deleteSpace(_ id: String, at date: Date = .now) throws -> Int {
        try writer.write { db in
            guard var space = try Space.fetchOne(db, key: id), space.deletedAt == nil else { return 0 }
            let live = Column("deletedAt") == nil
            guard try Space.filter(Column("profileID") == space.profileID && live).fetchCount(db) > 1 else { return 0 }
            let items = try SidebarItem.filter(Column("spaceID") == id && live).fetchAll(db)
            var archived = 0
            for tab in items where tab.kind == .tab {
                if try Self.archive(tab, reason: "spaceDeleted", at: date, in: db) != nil { archived += 1 }
            }
            for var item in items where item.kind != .tab {
                item.deletedAt = date
                item.modifiedAt = date
                try item.update(db)
            }
            space.deletedAt = date
            space.modifiedAt = date
            try space.update(db)
            return archived
        }
    }
}
