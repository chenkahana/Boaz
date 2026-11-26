import XCTest

/// Tab groups (folders in Today): group a Today tab, name it, collapse it, quit and relaunch onto the same library,
/// then ungroup. Every new row and menu item is checked by the accessibility audit along the way.
final class TabGroupUITests: BoazUITestCase {
    /// The library both launches share, in the app's own temporary directory (`UITestMode.storeDirectory`).
    private let storeName = "groups-\(UUID().uuidString)"

    private func launchOnTestLibrary() {
        launch(fixture: "standard", environment: ["BOAZ_UITEST_STORE_DIR": storeName])
        XCTAssertTrue(waitForSpace("Work"), "The standard fixture never seeded")
    }

    private var group: XCUIElement { sidebar.buttons["sidebar.group.Reading"].firstMatch }
    private var groupedTab: XCUIElement { sidebar.buttons["Today Tab"].firstMatch }

    func testCreateCollapseRelaunchUngroup() {
        launchOnTestLibrary()

        // Add to New Group, from the tab's menu: the group takes its slot and the Rename sheet opens on "New Group".
        XCTAssertTrue(groupedTab.waitForExistence(timeout: 5))
        groupedTab.rightClick()
        app.menuItems["Add to New Group"].firstMatch.click()
        let rename = element("screen.renameSheet")
        XCTAssertTrue(rename.waitForExistence(timeout: 5), "Add to New Group didn't open the Rename sheet")
        let name = rename.textFields.firstMatch
        XCTAssertEqual(name.value as? String, "New Group")
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Reading\r")
        XCTAssertTrue(group.waitForExistence(timeout: 5), "The group wasn't named")
        XCTAssertEqual(group.value as? String, "Expanded")
        XCTAssertTrue(group.label.hasPrefix("Reading, group, 1 tab"), "Group label: \(group.label)")
        XCTAssertTrue(groupedTab.exists, "The tab isn't in its group")
        assertScreenIntact(mainWindow, name: "tab-group-expanded")

        // Collapse: the tab hides, the row says so.
        group.click()
        XCTAssertTrue(waitForDisappearance(groupedTab), "Collapsing didn't hide the group's tab")
        XCTAssertEqual(group.value as? String, "Collapsed")
        assertScreenIntact(mainWindow, name: "tab-group-collapsed")

        // Quit and relaunch onto the same library: the group, its name, its tab and its collapse come back.
        Thread.sleep(forTimeInterval: 1)
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 15), "Boaz didn't quit")
        launchOnTestLibrary()
        XCTAssertTrue(group.waitForExistence(timeout: 10), "The group didn't survive a relaunch")
        XCTAssertEqual(group.value as? String, "Collapsed")
        XCTAssertFalse(groupedTab.exists, "The collapsed group's tab is showing")
        group.click()
        XCTAssertTrue(groupedTab.waitForExistence(timeout: 5), "The group lost its tab")

        // Ungroup: the tab stays in Today, the group goes.
        group.rightClick()
        app.menuItems["Ungroup"].firstMatch.click()
        XCTAssertTrue(waitForDisappearance(group), "Ungroup didn't remove the group")
        XCTAssertTrue(groupedTab.exists, "Ungroup lost the tab")
    }
}
