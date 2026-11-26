import AppKit
import XCTest

/// Site rules (PLAN-08): a link from another app to a ruled site opens in the rule's space, in the same window,
/// with no Quick Window; the toast's "Open in Personal" puts it back.
final class SpaceRoutingUITests: BoazUITestCase {
    private func openRoutedLink() {
        launch(fixture: "routing", arguments: ["-BoazUITestToastSeconds", "30"])
        XCTAssertTrue(waitForSpace("Personal"), "The routing fixture never seeded")
        openFromAnotherApp(URL(string: "https://example.test/a")!)
    }

    /// What Mail does with a link: Launch Services hands it to this build of Boaz (by path, so it never reaches
    /// another installed Boaz or the default browser).
    private func openFromAnotherApp(_ url: URL) {
        let products = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()  // PlugIns
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()  // Products dir
        let appURL = ProcessInfo.processInfo.environment["BOAZ_UITEST_APP"].map(URL.init(fileURLWithPath:))
            ?? products.appendingPathComponent("Boaz.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: appURL.path), "No app at \(appURL.path)")
        let opened = expectation(description: "open")
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            XCTAssertNil(error)
            opened.fulfill()
        }
        wait(for: [opened], timeout: 10)
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
    }

    func testOpenInPreviousSpaceOverridesTheRule() {
        openRoutedLink()
        XCTAssertTrue(waitForSpace("Work"))
        let action = element("screen.toast").buttons["Open in Personal"]
        XCTAssertTrue(action.waitForExistence(timeout: 5), "The toast has no Open in Personal")
        action.click()
        XCTAssertTrue(waitForSpace("Personal"), "Open in Personal didn't switch back")
        XCTAssertTrue(sidebar.buttons["example.test"].firstMatch.waitForExistence(timeout: 5),
                      "The tab didn't move to Personal")
        XCTAssertEqual(app.windows.count, 1)
    }
}
