import XCTest

/// Settings ▸ App Icon: the pretzel grid renders, and choosing a tile moves the selection ring.
final class AppIconUITests: BoazUITestCase {
    func testPickAppIconLight() throws {
        try runAppIconChecks(appearance: .light)
    }

    func testPickAppIconDark() throws {
        try runAppIconChecks(appearance: .dark)
    }

    private func runAppIconChecks(appearance: XCUIDevice.Appearance) throws {
        launch(appearance: appearance)
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10))

        app.typeKey(",", modifierFlags: .command)
        let tab = app.toolbars.buttons["App Icon"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.click()

        let screen = app.descendants(matching: .any)["screen.settings.appIcon"].firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 5))

        for id in ["neon", "salted"] {
            let tile = screen.buttons["control.appIcon.\(id)"]
            XCTAssertTrue(tile.waitForExistence(timeout: 2))
            tile.click()
            XCTAssertTrue(tile.isSelected, "\(id) should be the selected icon")
            assertScreenIntact(screen, name: "app-icon-\(id)-\(appearance)")
        }

        // Leave the default icon in place for the next test.
        screen.buttons["control.appIcon.classic"].click()
    }
}
