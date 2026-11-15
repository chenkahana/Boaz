import XCTest

/// Minimal check that the UI test contract actually works: the app launches in test mode, seeds the standard
/// fixture, and shows an intact main window. `ScreenTests.swift` covers the rest of the app.
final class SmokeTests: BoazUITestCase {
    func testMainWindowIntact() {
        launch(fixture: "standard")
        // The fixture must reach the sidebar: an empty library would otherwise pass as an "intact" window.
        XCTAssertTrue(mainWindow.staticTexts["Work"].waitForExistence(timeout: 10), "The standard fixture never seeded")
        assertScreenIntact(mainWindow, name: "browser")
    }

    /// One pass through the everyday flow: a new tab from the command bar, pin it, make and rename a folder,
    /// archive a tab and bring it back from the Archive, then switch spaces.
    func testEverydayFlow() {
        launch(fixture: "standard")
        XCTAssertTrue(sidebar.staticTexts["Work"].waitForExistence(timeout: 10), "The standard fixture never seeded")

        // New tab from the command bar, with a data: URL.
        openCommandBar()
        XCTAssertTrue(element("screen.commandBar").waitForExistence(timeout: 5))
        app.typeText("data:text/html,<title>Typed</title><h1>Typed</h1>\r")
        let typed = sidebar.buttons["Typed"].firstMatch
        XCTAssertTrue(typed.waitForExistence(timeout: 10), "The typed address didn't open as a tab")
        XCTAssertTrue(mainWindow.webViews.staticTexts["Typed"].waitForExistence(timeout: 10), "The typed page didn't load")

        // Pin it.
        menu("Tabs", "Pin Tab")
        app.menuBars.menuBarItems["Tabs"].click()
        XCTAssertTrue(app.menuItems["Unpin Tab"].waitForExistence(timeout: 3), "Pin Tab didn't pin the tab")
        app.typeKey(.escape, modifierFlags: [])

        // A folder, renamed.
        sidebar.staticTexts["Work"].firstMatch.rightClick()
        app.menuItems["New Folder"].firstMatch.click()
        let newFolder = sidebar.buttons["sidebar.folder.New Folder"]
        XCTAssertTrue(newFolder.waitForExistence(timeout: 5), "New Folder didn't add a folder")
        newFolder.rightClick()
        app.menuItems["Rename Folder…"].firstMatch.click()
        let rename = element("screen.renameSheet")
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        let name = rename.textFields.firstMatch
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Smoke Folder\r")
        XCTAssertTrue(sidebar.buttons["sidebar.folder.Smoke Folder"].waitForExistence(timeout: 5), "Rename didn't rename the folder")

        // Archive a Today tab (⌘W on it), then restore it from the Archive window.
        sidebar.buttons["Today Tab"].firstMatch.click()
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForDisappearance(sidebar.buttons["Today Tab"].firstMatch), "⌘W didn't archive the Today tab")
        app.typeKey("a", modifierFlags: [.command, .option])
        let archive = app.windows["Archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        let archived = archive.staticTexts["Today Tab"].firstMatch
        XCTAssertTrue(archived.waitForExistence(timeout: 5), "The archived tab isn't in the Archive")
        archived.rightClick()
        app.menuItems["Restore"].firstMatch.click()
        XCTAssertTrue(sidebar.buttons["Today Tab"].waitForExistence(timeout: 5), "Restore didn't bring the tab back")
        if archive.exists { archive.typeKey("w", modifierFlags: .command) }

        // Switch spaces from the sidebar's space dots.
        sidebar.buttons["Personal"].firstMatch.click()
        XCTAssertTrue(sidebar.staticTexts["Personal"].waitForExistence(timeout: 5), "Didn't switch to Personal")
        XCTAssertFalse(sidebar.buttons["Smoke Folder"].exists, "Work's folder is still showing")
        assertScreenIntact(mainWindow, name: "everyday-flow-personal")
    }
}
