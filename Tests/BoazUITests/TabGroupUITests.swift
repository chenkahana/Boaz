import XCTest

/// Tab groups (folders in Today): group a Today tab, name it, collapse it, quit and relaunch onto the same library,
/// then ungroup and archive the group, each undone from its toast. The accessibility audit checks the new rows,
/// sheet and toasts along the way; menus and toasts are attached as screenshots.
final class TabGroupUITests: BoazUITestCase {
    /// The library both launches share, in the app's own temporary directory (`UITestMode.storeDirectory`).
    private let storeName = "groups-\(UUID().uuidString)"

    private func launchOnTestLibrary() {
        launch(fixture: "standard", environment: ["BOAZ_UITEST_STORE_DIR": storeName],
               arguments: ["-BoazUITestToastSeconds", "30"])
        XCTAssertTrue(waitForSpace("Work"), "The standard fixture never seeded")
    }

    private var group: XCUIElement { sidebar.buttons["sidebar.group.Reading"].firstMatch }
    private var groupedTab: XCUIElement { sidebar.buttons["Today Tab"].firstMatch }
    private var toast: XCUIElement { element("screen.toast") }

    /// The open context menu, as a screenshot.
    private func attachMenu(_ name: String) {
        let menu = app.menus.firstMatch
        guard menu.waitForExistence(timeout: 3) else { return XCTFail("No menu for \(name)") }
        let screenshot = XCTAttachment(screenshot: menu.screenshot())
        screenshot.name = "\(name)-\(appearance.rawValue)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testCreateCollapseRelaunchUngroupArchive() {
        launchOnTestLibrary()

        // Add to New Group, from the tab's menu: the group takes its slot and the Rename sheet opens with "New Group"
        // selected, so typing replaces it.
        XCTAssertTrue(groupedTab.waitForExistence(timeout: 5))
        groupedTab.rightClick()
        attachMenu("tab-menu-today")
        app.menuItems["Add to New Group"].firstMatch.click()
        let rename = element("screen.renameSheet")
        XCTAssertTrue(rename.waitForExistence(timeout: 5), "Add to New Group didn't open the Rename sheet")
        XCTAssertEqual(rename.textFields.firstMatch.value as? String, "New Group")
        assertScreenIntact(rename, name: "tab-group-rename")
        app.typeText("Reading\r")
        XCTAssertTrue(group.waitForExistence(timeout: 5), "Typing didn't replace the selected \"New Group\"")
        XCTAssertEqual(group.value as? String, "Expanded")
        XCTAssertTrue(group.label.hasPrefix("Reading, group, 1 tab"), "Group label: \(group.label)")
        XCTAssertTrue(groupedTab.exists, "The tab isn't in its group")
        assertScreenIntact(mainWindow, name: "tab-group-expanded")

        // Collapse with the active tab inside: the tab hides, and the group wears the selection.
        groupedTab.click()
        group.click()
        XCTAssertTrue(waitForDisappearance(groupedTab), "Collapsing didn't hide the group's tab")
        XCTAssertEqual(group.value as? String, "Collapsed")
        XCTAssertTrue(group.isSelected, "The collapsed group holding the active tab isn't selected")
        assertScreenIntact(mainWindow, name: "tab-group-collapsed-active")

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

        // Ungroup, then Undo from the toast: the group comes back around its tab.
        group.rightClick()
        attachMenu("group-menu")
        app.menuItems["Ungroup"].firstMatch.click()
        XCTAssertTrue(waitForDisappearance(group), "Ungroup didn't remove the group")
        XCTAssertTrue(groupedTab.exists, "Ungroup lost the tab")
        assertScreenIntact(toast, name: "tab-group-ungrouped-toast")
        toast.buttons["Undo"].click()
        XCTAssertTrue(group.waitForExistence(timeout: 5), "Undo didn't bring the group back")

        // Archive Group: no dialog, the group and its tab go; Undo restores both.
        group.rightClick()
        app.menuItems["Archive Group"].firstMatch.click()
        XCTAssertTrue(waitForDisappearance(group), "Archive Group didn't remove the group")
        XCTAssertFalse(groupedTab.exists, "Archive Group left its tab")
        assertScreenIntact(toast, name: "tab-group-archived-toast")
        toast.buttons["Undo"].click()
        XCTAssertTrue(group.waitForExistence(timeout: 5), "Undo didn't restore the archived group")
        XCTAssertTrue(groupedTab.waitForExistence(timeout: 5), "Undo didn't restore the group's tab")
    }
}
