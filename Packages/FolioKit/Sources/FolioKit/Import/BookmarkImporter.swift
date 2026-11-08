import CryptoKit
import Foundation
import GRDB

/// A bookmark or folder from another browser, before it becomes a Folio pinned tab or folder.
public struct BookmarkNode: Sendable, Equatable {
    /// Stable within its source, so re-importing finds the same row.
    public var id: String
    public var title: String
    /// Nil for folders.
    public var url: URL?
    public var children: [BookmarkNode]

    public init(id: String, title: String, url: URL? = nil, children: [BookmarkNode] = []) {
        self.id = id; self.title = title; self.url = url; self.children = children
    }

    var isFolder: Bool { url == nil }
}

/// Imports another browser's bookmarks into a space's pinned section: the bookmarks bar becomes pinned tabs and
/// folders, everything else pinned folders.
///
/// Like `ArcSidebarImporter`, import is idempotent: Folio ids are `<source>-<source id>`, re-import updates rows in
/// place (keeping where the user moved or expanded them). A live source (a Chromium profile) also tombstones rows it
/// no longer has; a one-off export file only adds and updates, since one export says nothing about another.
public struct BookmarkImporter: Sendable {
    /// Id prefix and owner of the imported rows, e.g. "chrome" or "safari".
    public let source: String
    /// The space's top-level pinned entries, in order.
    public let items: [BookmarkNode]
    /// Whether rows from `source` that are no longer in `items` are removed.
    public let removesMissing: Bool

    public init(source: String, items: [BookmarkNode], removesMissing: Bool) {
        self.source = source; self.items = items; self.removesMissing = removesMissing
    }

    // MARK: Import

    @discardableResult
    public func importInto(_ store: FolioStore, spaceID: String, now: Date = .now) throws -> BookmarkImportSummary {
        let items = Self.importable(items)
        let prefix = source + "-"
        return try store.writer.write { db in
            guard let space = try Space.fetchOne(db, key: spaceID), space.deletedAt == nil else {
                throw BookmarkImportError.noSpace
            }
            let pinned = try SidebarItem
                .filter(Column("spaceID") == spaceID && Column("containerKind") == SidebarItem.ContainerKind.pinned.rawValue
                        && Column("deletedAt") == nil)
                .fetchOne(db)
            guard let pinned else { throw BookmarkImportError.noSpace }

            var summary = BookmarkImportSummary()
            var seen = Set<String>()
            var nextTopPosition = (try Double.fetchOne(db, sql: """
                SELECT MAX(position) FROM sidebarItem WHERE parentID = ? AND deletedAt IS NULL
                """, arguments: [pinned.id]) ?? -1) + 1

            func place(_ nodes: [BookmarkNode], in parentID: String) throws {
                for (index, node) in nodes.enumerated() {
                    let id = prefix + node.id
                    guard seen.insert(id).inserted else { continue }
                    let isTop = parentID == pinned.id
                    var item = SidebarItem(id: id, spaceID: spaceID, profileID: space.profileID, parentID: parentID,
                                           kind: node.isFolder ? .folder : .tab,
                                           title: node.title.isEmpty ? node.url?.host() : node.title,
                                           url: node.url, isExpanded: false, position: Double(index),
                                           createdAt: now, modifiedAt: now)
                    if node.isFolder { summary.folders += 1 } else { summary.bookmarks += 1 }

                    if let existing = try SidebarItem.fetchOne(db, key: id) {
                        // Keep what the user changed in Folio: order, expansion, activity.
                        if existing.parentID == parentID && existing.deletedAt == nil { item.position = existing.position }
                        else if isTop { item.position = nextTopPosition; nextTopPosition += 1 }
                        item.isExpanded = existing.isExpanded
                        item.isUnread = existing.isUnread
                        item.createdAt = existing.createdAt
                        item.lastActiveAt = existing.lastActiveAt
                        item.modifiedAt = existing.modifiedAt
                        // Compare as stored: the database keeps dates at millisecond precision.
                        if try SidebarItem(row: Row(item.databaseDictionary)) == existing {
                            summary.unchanged += 1
                        } else {
                            item.modifiedAt = now
                            try item.update(db); summary.updated += 1
                        }
                    } else {
                        if isTop { item.position = nextTopPosition; nextTopPosition += 1 }
                        try item.insert(db); summary.inserted += 1
                    }
                    if node.isFolder { try place(node.children, in: id) }
                }
            }
            try place(items, in: pinned.id)
            summary.skipped = Self.count(self.items, where: { !$0.isFolder }) - summary.bookmarks

            guard removesMissing else { return summary }
            let stale = try SidebarItem.filter(Column("deletedAt") == nil && Column("id").like(prefix + "%"))
                .fetchAll(db).filter { !seen.contains($0.id) }
            let staleIDs = Set(stale.map(\.id))
            // A folder the user also keeps their own tabs in stays, or those tabs would vanish with it.
            var kept = try Set(stale.filter { $0.kind == .folder }.filter { folder in
                try SidebarItem.filter(Column("parentID") == folder.id && Column("deletedAt") == nil)
                    .fetchAll(db).contains { !staleIDs.contains($0.id) && !$0.id.hasPrefix(prefix) }
            }.map(\.id))
            // …and so do the folders above it.
            let parents = Dictionary(uniqueKeysWithValues: stale.map { ($0.id, $0.parentID) })
            for id in Array(kept) {
                var next = parents[id] ?? nil
                while let parent = next, staleIDs.contains(parent), kept.insert(parent).inserted {
                    next = parents[parent] ?? nil
                }
            }
            for var item in stale where !kept.contains(item.id) {
                item.deletedAt = now; item.modifiedAt = now
                try item.update(db); summary.removed += 1
            }
            return summary
        }
    }

    /// Drops links Folio can't open (bookmarklets, `chrome://` pages) and folders left empty.
    static func importable(_ nodes: [BookmarkNode]) -> [BookmarkNode] {
        nodes.compactMap { node in
            if node.isFolder {
                let children = importable(node.children)
                return children.isEmpty ? nil : BookmarkNode(id: node.id, title: node.title, children: children)
            }
            return ["http", "https"].contains(node.url?.scheme?.lowercased() ?? "") ? node : nil
        }
    }

    static func count(_ nodes: [BookmarkNode], where predicate: (BookmarkNode) -> Bool) -> Int {
        nodes.reduce(0) { $0 + (predicate($1) ? 1 : 0) + count($1.children, where: predicate) }
    }
}

public struct BookmarkImportSummary: Sendable, Equatable {
    public var folders = 0, bookmarks = 0
    /// Links Folio can't open, e.g. `javascript:` bookmarklets.
    public var skipped = 0
    public var inserted = 0, updated = 0, unchanged = 0, removed = 0
}

public enum BookmarkImportError: Error, LocalizedError, Equatable {
    case missingFile
    case unsupportedFormat
    case noSpace

    public var errorDescription: String? {
        switch self {
        case .missingFile: "That folder has no bookmarks file. Choose the browser's folder in Library › Application Support."
        case .unsupportedFormat: "That file isn't a bookmarks file Folio understands."
        case .noSpace: "There's no space to import into."
        }
    }
}

// MARK: - Chromium

extension BookmarkImporter {
    /// The `Bookmarks` file to read in a Chromium data folder (`~/Library/Application Support/Google/Chrome`):
    /// the most recently changed profile's, or the file in the folder itself when a profile folder was chosen.
    public static func chromiumBookmarksFile(in folder: URL) -> URL? {
        let fm = FileManager.default
        let direct = folder.appending(path: "Bookmarks")
        if fm.fileExists(atPath: direct.path) { return direct }
        let profiles = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        return profiles
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .map { folder.appending(path: $0).appending(path: "Bookmarks") }
            .compactMap { url in
                (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date).map { (url, $0) }
            }
            .max { $0.1 < $1.1 }?.0
    }

    /// Chromium's `Bookmarks` JSON (Chrome, Brave, Edge…): the bar's contents, then "Other" and "Mobile" bookmarks as folders.
    public static func chromium(_ data: Data, source: String) throws -> BookmarkImporter {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = root["roots"] as? [String: Any] else { throw BookmarkImportError.unsupportedFormat }

        func node(_ json: [String: Any]) -> BookmarkNode? {
            guard let id = json["guid"] as? String ?? json["id"] as? String else { return nil }
            let title = json["name"] as? String ?? ""
            switch json["type"] as? String {
            case "url":
                guard let url = (json["url"] as? String).flatMap(URL.init(string:)) else { return nil }
                return BookmarkNode(id: id, title: title, url: url)
            case "folder":
                let children = (json["children"] as? [Any] ?? []).compactMap { ($0 as? [String: Any]).flatMap(node) }
                return BookmarkNode(id: id, title: title, children: children)
            default:
                return nil
            }
        }
        var items = (roots["bookmark_bar"] as? [String: Any]).flatMap(node)?.children ?? []
        for key in ["other", "synced"] {
            if let folder = (roots[key] as? [String: Any]).flatMap(node) { items.append(folder) }
        }
        return BookmarkImporter(source: source, items: items, removesMissing: true)
    }
}

// MARK: - Netscape bookmarks HTML

extension BookmarkImporter {
    /// The Netscape bookmarks file Safari, Firefox and Chromium export: the favorites/toolbar folder's contents, then
    /// the other folders. Loose top-level links join the bar when there is none, else an "Other Bookmarks" folder.
    public static func netscapeHTML(_ html: String, source: String) throws -> BookmarkImporter {
        guard html.range(of: "<DL", options: .caseInsensitive) != nil else { throw BookmarkImportError.unsupportedFormat }
        let pattern = #"<DL\b[^>]*>|</DL\s*>|<H3\b([^>]*)>(.*?)</H3\s*>|<A\b([^>]*)>(.*?)</A\s*>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        let text = html as NSString

        // Each open <DL> is a folder being filled; an <H3> names the folder whose <DL> comes next.
        // Safari's export has no list around its top-level folders, other browsers' do.
        struct Open { var title: String; var isBar = false; var children: [BookmarkNode] = [] }
        var stack = [Open(title: "")]
        var pending: Open?
        var sawList = false
        var barIndex: Int?

        func add(_ node: BookmarkNode) { stack[stack.count - 1].children.append(node) }
        func close(_ folder: Open) {
            if stack.count == 1, folder.isBar, barIndex == nil { barIndex = stack[0].children.count }
            add(BookmarkNode(id: "", title: folder.title, children: folder.children))
        }
        func flushPending() { if let folder = pending { pending = nil; close(folder) } }

        for match in regex.matches(in: html, range: NSRange(location: 0, length: text.length)) {
            let token = text.substring(with: match.range)
            func group(_ i: Int) -> String? {
                match.range(at: i).location == NSNotFound ? nil : text.substring(with: match.range(at: i))
            }
            if token.hasPrefix("</") {
                flushPending()
                if stack.count > 1 { close(stack.removeLast()) }
            } else if token.uppercased().hasPrefix("<DL") {
                if let folder = pending { pending = nil; stack.append(folder) }
                else if sawList { stack.append(Open(title: "")) }
                sawList = true
            } else if let attributes = group(1), let title = group(2) {
                flushPending()
                let title = decodeEntities(stripTags(title))
                pending = Open(title: title, isBar: isBar(parseAttributes(attributes), title: title))
            } else if let attributes = group(3), let title = group(4) {
                flushPending()
                let href = decodeEntities(parseAttributes(attributes)["href"] ?? "")
                if let url = URL(string: href.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    add(BookmarkNode(id: "", title: decodeEntities(stripTags(title)), url: url))
                }
            }
        }
        flushPending()
        while stack.count > 1 { close(stack.removeLast()) }

        var top = stack[0].children
        var items = barIndex.map { top.remove(at: $0).children } ?? []
        let loose = top.filter { !$0.isFolder }
        if barIndex == nil { items += loose }
        items += top.filter(\.isFolder)
        if barIndex != nil, !loose.isEmpty { items.append(BookmarkNode(id: "", title: "Other Bookmarks", children: loose)) }
        return BookmarkImporter(source: source, items: assignIDs(items, path: ""), removesMissing: false)
    }

    /// Exports carry no ids, so each node's id hashes its folder path and title or address
    /// (plus a counter for repeats), which is stable when the same bookmarks are exported again.
    static func assignIDs(_ nodes: [BookmarkNode], path: String) -> [BookmarkNode] {
        var repeats: [String: Int] = [:]
        return nodes.map { node in
            var key = path + "/" + (node.url?.absoluteString ?? "folder:" + node.title)
            let n = repeats[key, default: 0]
            repeats[key] = n + 1
            if n > 0 { key += "#\(n)" }
            let digest = SHA256.hash(data: Data(key.utf8)).prefix(10).map { String(format: "%02x", $0) }.joined()
            var node = node
            node.id = digest
            node.children = assignIDs(node.children, path: key)
            return node
        }
    }

    /// Firefox and Chromium mark their toolbar folder; Safari's is just called Favorites.
    static func isBar(_ attributes: [String: String], title: String) -> Bool {
        attributes["personal_toolbar_folder"]?.lowercased() == "true"
            || ["favorites", "favourites", "favorites bar", "bookmarks bar", "bookmarks toolbar"].contains(title.lowercased())
    }

    static func parseAttributes(_ text: String) -> [String: String] {
        let regex = try! NSRegularExpression(pattern: #"([A-Za-z_:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#)
        let ns = text as NSString
        var result: [String: String] = [:]
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let value = (2...4).lazy.map { match.range(at: $0) }.first { $0.location != NSNotFound }.map(ns.substring) ?? ""
            result[ns.substring(with: match.range(at: 1)).lowercased()] = value
        }
        return result
    }

    static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"]
        var result = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            result += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.prefix(10).firstIndex(of: ";") {
                let name = after[..<semi]
                let scalar: String? = if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
                } else if name.hasPrefix("#") {
                    UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
                } else {
                    named[name.lowercased()]
                }
                if let scalar {
                    result += scalar
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            result += "&"
            rest = after
        }
        return result + rest
    }
}
