import XCTest

/// Covers the Library popover (sidebar bottom-left button): each pane, search and the Downloads filter menu,
/// in light and dark. Built against fixture downloads (`BOAZ_UITEST_DOWNLOADS_DIR`) so results are deterministic.
final class LibraryPanelUITests: BoazUITestCase {
    private var downloadsDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        downloadsDir = try makeFixtureDownloads()
    }

    override func tearDownWithError() throws {
        if let downloadsDir { try? FileManager.default.removeItem(at: downloadsDir) }
        try super.tearDownWithError()
    }

    func testLibraryPanelLight() throws {
        try runLibraryPanelChecks(appearance: .light)
    }

    func testLibraryPanelDark() throws {
        try runLibraryPanelChecks(appearance: .dark)
    }

    private func runLibraryPanelChecks(appearance: XCUIDevice.Appearance) throws {
        launch(appearance: appearance, environment: ["BOAZ_UITEST_DOWNLOADS_DIR": downloadsDir.path])

        let libraryButton = app.buttons["sidebar.libraryButton"]
        XCTAssertTrue(libraryButton.waitForExistence(timeout: 5))
        libraryButton.click()

        let panel = app.groups["screen.libraryPanel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        assertScreenIntact(panel, name: "library-downloads-\(appearance)")

        // Search narrows the list.
        let search = panel.textFields["control.library.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        search.click()
        search.typeText("boarding")
        XCTAssertTrue(app.staticTexts["control.library.download.boardingcard.pdf"].waitForExistence(timeout: 2))
        assertScreenIntact(panel, name: "library-downloads-search-\(appearance)")
        search.typeText(XCUIKeyboardKey.delete.rawValue)

        // The Filter menu narrows by kind.
        let filter = panel.buttons["control.library.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 2))
        filter.click()
        app.menuItems["PDFs"].click()
        assertScreenIntact(panel, name: "library-downloads-filtered-\(appearance)")

        // Each remaining pane.
        for tab in ["media", "spaces", "archive"] {
            let tabButton = panel.buttons["control.library.tab.\(tab)"]
            XCTAssertTrue(tabButton.waitForExistence(timeout: 2))
            tabButton.click()
            assertScreenIntact(panel, name: "library-\(tab)-\(appearance)")
        }

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(panel.waitForExistence(timeout: 2))
    }

    /// A handful of files resembling real downloads: a PDF, a PNG, a disk image and a zip archive, each with
    /// `kMDItemWhereFroms` set the way WebKit and Chromium write it, so the Downloads pane shows real subtitles.
    private func makeFixtureDownloads() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BoazUITest-Downloads-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        try write(name: "boardingcard.pdf", data: Data("%PDF-1.4\n%fixture\n".utf8), from: "https://airline.example.com/boardingcard.pdf", in: dir)
        try write(name: "screenshot.png", data: pngFixtureData(), from: "https://chat.example.com/screenshot.png", in: dir)
        try write(name: "installer.dmg", data: Data("fixture-dmg".utf8), from: "https://sigmaos.example.com/installer.dmg", in: dir)
        try write(name: "archive.zip", data: Data("fixture-zip".utf8), from: "https://gov.example.com/archive.zip", in: dir)
        return dir
    }

    private func write(name: String, data: Data, from sourceURL: String, in dir: URL) throws {
        let url = dir.appendingPathComponent(name)
        try data.write(to: url)
        let plist = try PropertyListSerialization.data(fromPropertyList: [sourceURL], format: .binary, options: 0)
        _ = plist.withUnsafeBytes { buffer in
            url.withUnsafeFileSystemRepresentation { setxattr($0, "com.apple.metadata:kMDItemWhereFroms", buffer.baseAddress, buffer.count, 0, 0) }
        }
    }

    /// A 1x1 PNG, just enough for `UTType` and `QLThumbnailGenerator` to treat it as a real image.
    private func pngFixtureData() -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
              0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
              0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
              0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
              0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
              0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
              0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
              0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
              0x44, 0xAE, 0x42, 0x60, 0x82])
    }
}
