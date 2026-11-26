import XCTest

/// Site rules (PLAN-08): a link from another app to a ruled site opens in the rule's space, in the same window,
/// with no Quick Window; the toast's "Open in Personal" puts it back.
final class SpaceRoutingUITests: BoazUITestCase {
    private func openRoutedLink() {
        launch(fixture: "routing", arguments: ["-BoazUITestToastSeconds", "30"])
        XCTAssertTrue(waitForSpace("Personal"), "The routing fixture never seeded")
        app.open(URL(string: "https://example.test/a")!)
    }

    /// The window as it looks now, kept in the result bundle as evidence of the flow.
    private func snapshot(_ name: String) {
        let screenshot = XCTAttachment(screenshot: mainWindow.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testExternalOpenFollowsTheRule() {
        openRoutedLink()
        XCTAssertTrue(waitForSpace("Work"), "The ruled link didn't switch the window to Work")
        XCTAssertTrue(sidebar.buttons["example.test"].firstMatch.waitForExistence(timeout: 10),
                      "The routed tab isn't in Work")
        XCTAssertEqual(app.windows.count, 1, "A routed link must not open a second window")
        XCTAssertFalse(app.descendants(matching: .any)["screen.quickWindow"].exists, "A routed link opened a Quick Window")
        let toast = element("screen.toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "No toast after routing")
        XCTAssertTrue(toast.staticTexts["Opened in Work"].exists)
        snapshot("routing-1-opened-in-work")
    }

    func testOpenInPreviousSpaceOverridesTheRule() {
        openRoutedLink()
        XCTAssertTrue(waitForSpace("Work"))
        let action = element("screen.toast").buttons["Open in Personal"]
        XCTAssertTrue(action.waitForExistence(timeout: 5), "The toast has no Open in Personal")
        snapshot("override-1-toast-in-work")
        action.click()
        XCTAssertTrue(waitForSpace("Personal"), "Open in Personal didn't switch back")
        XCTAssertTrue(sidebar.buttons["example.test"].firstMatch.waitForExistence(timeout: 5),
                      "The tab didn't move to Personal")
        XCTAssertEqual(app.windows.count, 1)
        snapshot("override-2-back-in-personal")
    }
}
