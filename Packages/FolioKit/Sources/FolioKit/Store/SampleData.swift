#if DEBUG
import Foundation
import GRDB

/// Synthetic sidebar in Arc's shape, for development builds with an empty store.
public enum SampleData {
    public static func seed(_ store: FolioStore) throws {
        let profile = Profile(id: "default", name: "Default", isDefault: true)
        var records: [any PersistableRecord] = [profile]

        let favorites = SidebarItem(id: "fav", spaceID: nil, profileID: profile.id, parentID: nil,
                                    kind: .container, containerKind: .favorites, position: 0)
        records.append(favorites)
        for (i, site) in ["https://www.apple.com", "https://github.com", "https://news.ycombinator.com"].enumerated() {
            records.append(tab("fav-\(i)", space: nil, parent: favorites.id, profile: profile.id, url: site, at: i))
        }

        let spaces: [(String, String, String, [String], [String])] = [
            ("Personal", "🏡", theme(r: 0.81, g: 0.81, b: 0.97),
             ["https://en.wikipedia.org/wiki/Hinge", "https://www.youtube.com"],
             ["https://www.apple.com/iphone/"]),
            ("Work", "💼", theme(r: 0.98, g: 0.84, b: 0.78),
             ["https://developer.apple.com/documentation/swiftui"],
             ["https://github.com/groue/GRDB.swift", "https://developer.apple.com/documentation/cloudkit"]),
        ]
        for (s, (title, icon, themeJSON, pinned, today)) in spaces.enumerated() {
            let space = Space(id: "space-\(s)", title: title, icon: icon, themeJSON: Data(themeJSON.utf8),
                              profileID: profile.id, position: Double(s))
            let pinnedBox = SidebarItem(id: "\(space.id)-pinned", spaceID: space.id, profileID: profile.id,
                                        parentID: nil, kind: .container, containerKind: .pinned, position: 0)
            let todayBox = SidebarItem(id: "\(space.id)-today", spaceID: space.id, profileID: profile.id,
                                       parentID: nil, kind: .container, containerKind: .unpinned, position: 1)
            let folder = SidebarItem(id: "\(space.id)-folder", spaceID: space.id, profileID: profile.id,
                                     parentID: pinnedBox.id, kind: .folder, title: "Reading", position: Double(pinned.count))
            records += [space, pinnedBox, todayBox, folder]
            for (i, url) in pinned.enumerated() {
                records.append(tab("\(space.id)-p\(i)", space: space.id, parent: pinnedBox.id, profile: profile.id, url: url, at: i))
            }
            records.append(tab("\(space.id)-f0", space: space.id, parent: folder.id, profile: profile.id,
                               url: "https://www.swift.org/blog/", at: 0))
            for (i, url) in today.enumerated() {
                records.append(tab("\(space.id)-t\(i)", space: space.id, parent: todayBox.id, profile: profile.id, url: url, at: i))
            }
        }
        try store.save(records)
    }

    private static func tab(_ id: String, space: String?, parent: String, profile: String, url: String, at i: Int) -> SidebarItem {
        let url = URL(string: url)!
        return SidebarItem(id: id, spaceID: space, profileID: profile, parentID: parent, kind: .tab,
                           title: url.host(), url: url, position: Double(i), lastActiveAt: .now)
    }

    /// Minimal windowTheme in Arc's schema.
    private static func theme(r: Double, g: Double, b: Double) -> String {
        func c(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> String {
            #"{"colorSpace":"extendedSRGB","red":\#(r),"green":\#(g),"blue":\#(b),"alpha":\#(a)}"#
        }
        return #"""
        {"semanticColorPalette":{"appearanceBased":{
          "light":{"background":\#(c(r, g, b)),"foregroundPrimary":\#(c(0, 0, 0)),"title":\#(c(0, 0, 0))},
          "dark":{"background":\#(c(r * 0.25, g * 0.25, b * 0.3)),"foregroundPrimary":\#(c(1, 1, 1)),"title":\#(c(1, 1, 1))}}},
         "primaryColorPalette":{"midTone":\#(c(r * 0.7, g * 0.7, b * 0.9))}}
        """#
    }
}
#endif
