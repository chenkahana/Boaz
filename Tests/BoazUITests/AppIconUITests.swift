import XCTest

/// Settings ▸ App Icon: the pretzel grid renders, and choosing a tile moves the selection ring.
final class AppIconUITests: BoazUITestCase {
    func testPickAppIconLight() throws {
        try runAppIconChecks(appearance: .light)
    }

    func testPickAppIconDark() throws {
        try runAppIconChecks(appearance: .dark)
    }

    private func runAppIconChecks(appearance: BoazUITestCase.Appearance) throws {
        launch(appearance: appearance)
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 10))

        let screen = openSettings(tab: "App Icon")

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
