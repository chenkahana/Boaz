import Foundation
import Testing
@testable import BoazKit

@Suite("BookmarkImporter")
struct BookmarkImporterTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeSpace() throws -> (store: BoazStore, space: Space) {
        let store = try BoazStore.inMemory()
        try store.save([Profile(id: "p1", name: "Personal", isDefault: true, modifiedAt: t0)])
        let space = try store.createSpace(title: "Work", icon: nil, palette: .defaultPalette, profileID: "p1", at: t0)
        return (store, space)
    }

    @Test func chromiumJSONParsesBarAndOtherFolders() throws {
        let json = """
        {"roots": {
          "bookmark_bar": {"type": "folder", "name": "Bookmarks bar", "guid": "bar", "children": [
            {"type": "url", "name": "Example", "url": "https://example.com", "guid": "b1"},
            {"type": "folder", "name": "Dev", "guid": "f1", "children": [
              {"type": "url", "name": "Docs", "url": "https://docs.example.com", "guid": "b2"}
            ]}
          ]},
          "other": {"type": "folder", "name": "Other bookmarks", "guid": "other", "children": [
            {"type": "url", "name": "Loose", "url": "https://loose.example.com", "guid": "b3"}
          ]},
          "synced": {"type": "folder", "name": "Mobile bookmarks", "guid": "synced", "children": []}
        }}
        """
        let importer = try BookmarkImporter.chromium(Data(json.utf8), source: "chrome")
        #expect(importer.removesMissing)
        // The bar's contents come first; Other and Mobile follow as folders.
        #expect(importer.items.map(\.title) == ["Example", "Dev", "Other bookmarks", "Mobile bookmarks"])
        #expect(importer.items[1].children.map(\.title) == ["Docs"])
    }

    @Test func chromiumRejectsNonBookmarkJSON() {
        #expect(throws: BookmarkImportError.self) {
            _ = try BookmarkImporter.chromium(Data("{}".utf8), source: "chrome")
        }
    }

    @Test func netscapeHTMLParsesBarFoldersAndLooseLinks() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <DL><p>
        <DT><H3 PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
        <DL><p>
        <DT><A HREF="https://example.com">Example</A>
        <DT><H3>Dev</H3>
        <DL><p>
        <DT><A HREF="https://dev.example.com">Dev &amp; Ops</A>
        </DL><p>
        </DL><p>
        <DT><A HREF="https://loose.example.com">Loose</A>
        </DL><p>
        """
        let importer = try BookmarkImporter.netscapeHTML(html, source: "safari")
        #expect(!importer.removesMissing)
        #expect(importer.items.map(\.title) == ["Example", "Dev", "Other Bookmarks"])
        #expect(importer.items[1].children.first?.title == "Dev & Ops")
        #expect(importer.items[2].children.first?.title == "Loose")
        // Ids are derived, and stable for the same export.
        let again = try BookmarkImporter.netscapeHTML(html, source: "safari")
        #expect(importer.items.map(\.id) == again.items.map(\.id))
    }

    @Test func netscapeHTMLRejectsOtherFiles() {
        #expect(throws: BookmarkImportError.self) {
            _ = try BookmarkImporter.netscapeHTML("<html><body>not bookmarks</body></html>", source: "safari")
        }
    }

    @Test func importableDropsBookmarkletsAndEmptyFolders() {
        let nodes = [
            BookmarkNode(id: "1", title: "Web", url: URL(string: "https://example.com")),
            BookmarkNode(id: "2", title: "Bookmarklet", url: URL(string: "javascript:alert(1)")),
            BookmarkNode(id: "3", title: "Empty folder", children: []),
            BookmarkNode(id: "4", title: "Folder", children: [
                BookmarkNode(id: "5", title: "Only a bookmarklet", url: URL(string: "javascript:alert(2)")),
            ]),
        ]
        let importable = BookmarkImporter.importable(nodes)
        #expect(importable.map(\.title) == ["Web"])
    }

    @Test func importIntoPlacesBookmarksInThePinnedSection() throws {
        let (store, space) = try makeSpace()
        let importer = BookmarkImporter(source: "safari", items: [
            BookmarkNode(id: "1", title: "Example", url: URL(string: "https://example.com")),
            BookmarkNode(id: "2", title: "Dev", children: [
                BookmarkNode(id: "3", title: "Docs", url: URL(string: "https://docs.example.com")),
            ]),
        ], removesMissing: false)
        let summary = try importer.importInto(store, spaceID: space.id)
        #expect(summary.inserted == 3)
        #expect(summary.folders == 1)
        #expect(summary.bookmarks == 2)
        #expect(summary.skipped == 0)

        let pinned = try #require(store.sidebar().container(.pinned, in: space.id))
        let children = store.sidebar().children(of: pinned.id)
        #expect(children.map(\.title) == ["Example", "Dev"])
        let folder = try #require(children.last)
        #expect(store.sidebar().children(of: folder.id).map(\.title) == ["Docs"])
    }

    @Test func reimportKeepsWhereTheUserMovedThings() throws {
        let (store, space) = try makeSpace()
        let nodes = [BookmarkNode(id: "1", title: "Example", url: URL(string: "https://example.com"))]
        let importer = BookmarkImporter(source: "safari", items: nodes, removesMissing: false)
        _ = try importer.importInto(store, spaceID: space.id)

        // The user expands the row and gives it a new place.
        try store.writer.write { db in
            var item = try #require(try SidebarItem.fetchOne(db, key: "safari-1"))
            item.isExpanded = true
            item.position = 42
            try item.update(db)
        }

        let summary = try importer.importInto(store, spaceID: space.id)
        #expect(summary.unchanged == 1)
        #expect(summary.inserted == 0)
        let item = try store.sidebar().items.first { $0.id == "safari-1" }
        #expect(item?.position == 42)
        #expect(item?.isExpanded == true)
    }

    @Test func removesMissingTombstonesStaleRowsButKeepsFoldersWithUserTabs() throws {
        let (store, space) = try makeSpace()
        let first = BookmarkImporter(source: "chrome", items: [
            BookmarkNode(id: "a", title: "Keep", url: URL(string: "https://keep.example.com")),
            BookmarkNode(id: "f", title: "Folder", children: [
                BookmarkNode(id: "b", title: "Drop", url: URL(string: "https://drop.example.com")),
            ]),
        ], removesMissing: true)
        _ = try first.importInto(store, spaceID: space.id)

        // The user files a tab of their own in the imported folder.
        try store.save([SidebarItem(id: "my-tab", spaceID: space.id, profileID: "p1", parentID: "chrome-f",
                                    kind: .tab, url: URL(string: "https://mine.example.com"),
                                    position: 0, modifiedAt: t0)])

        let second = BookmarkImporter(source: "chrome", items: [
            BookmarkNode(id: "a", title: "Keep", url: URL(string: "https://keep.example.com")),
        ], removesMissing: true)
        let summary = try second.importInto(store, spaceID: space.id)
        #expect(summary.removed == 1) // only chrome-b

        let sidebar = store.sidebar()
        // The folder survives because it holds the user's own tab; the stale bookmark is gone.
        #expect(sidebar.items.contains { $0.id == "chrome-f" })
        #expect(sidebar.items.contains { $0.id == "my-tab" })
        #expect(!sidebar.items.contains { $0.id == "chrome-b" })
    }

    @Test func importIntoAnUnknownSpaceThrows() throws {
        let store = try BoazStore.inMemory()
        let importer = BookmarkImporter(source: "safari", items: [], removesMissing: false)
        #expect(throws: BookmarkImportError.self) {
            _ = try importer.importInto(store, spaceID: "nope")
        }
    }
}
