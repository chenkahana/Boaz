import CryptoKit
import XCTest

/// Extensions in the Chromium build, driven with real clicks and keys: the action's right-click menu, manifest
/// commands, site access requests, the side panel, private windows, and Chrome Web Store installs.
///
/// Runs only against a Chromium build (`BOAZ_UITEST_APP=<path to a staged Chromium .app>`), in an isolated home
/// (`BOAZ_UITEST_HOME`, default under /Volumes/BoazBuild/cef/direct/profiles) with a mock Keychain, and loads
/// `Tools/chromium/fixtures/parity-extension` unpacked.
final class ChromiumExtensionsUITests: BoazUITestCase {
    /// The unpacked fixture's ID: Chromium derives it from the folder's path.
    private var fixtureID = ""
    private static let fixturePath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tools/chromium/fixtures/parity-extension").path

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["BOAZ_UITEST_APP"],
              FileManager.default.fileExists(atPath: path + "/Contents/Frameworks/Chromium Framework.framework") else {
            throw XCTSkip("Set BOAZ_UITEST_APP to a Chromium build of Boaz.")
        }
        fixtureID = Self.extensionID(path: Self.fixturePath)
    }

    // MARK: - Tests

    /// Item 5: right-click on a pinned action shows Chromium's menu, with the extension's own `action` items.
    func testActionContextMenu() throws {
        launchChromium()
        openPage("https://example.com/")
        pinFixture()
        let action = actionButton()
        action.rightClick()
        XCTAssertTrue(app.menuItems["Parity: action item"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.menuItems["Unpin"].exists || app.menuItems.matching(labelContaining: "Unpin").count > 0)
        app.menuItems["Parity: action item"].click()
        XCTAssertFalse(app.menuItems["Parity: action item"].waitForExistence(timeout: 1))
    }

    /// The action's menu closes, without a crash, when its extension goes away while the menu is open.
    func testActionMenuClosesWhenExtensionIsRemoved() throws {
        launchChromium()
        openPage("https://example.com/")
        pinFixture()
        actionButton().click()
        let remove = app.buttons["Remove this extension in 3 seconds"]
        XCTAssertTrue(remove.waitForExistence(timeout: 8), app.debugDescription)
        remove.click()
        actionButton().rightClick()
        let item = app.menuItems["Parity: action item"]
        XCTAssertTrue(item.waitForExistence(timeout: 3), "The action's menu didn't open")
        XCTAssertTrue(item.waitForNonExistence(timeout: 10), "The menu stayed open after its extension was removed")
        XCTAssertTrue(actionButton().waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground, "Boaz quit")
    }

    /// As Chrome's: web and extension popup windows show their page's address, read-only.
    func testPopupWindowsShowTheirAddress() throws {
        launchChromium()
        openPage("https://example.com/")
        pinFixture()
        actionButton().click()
        let web = app.buttons["Open web popup"]
        XCTAssertTrue(web.waitForExistence(timeout: 8), app.debugDescription)
        web.click()
        let location = app.descendants(matching: .any)["control.popupLocation"]
        XCTAssertTrue(location.waitForExistence(timeout: 10), "A web popup has no location field: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'https://example.com'"))
            .firstMatch.waitForExistence(timeout: 10), "The web popup's location isn't its page's address")
        app.windows.firstMatch.buttons["_XCUI:CloseWindow"].click()

        actionButton().click()
        let window = app.buttons["Open popup window"]
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        window.click()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'chrome-extension://'"))
            .firstMatch.waitForExistence(timeout: 10), "windows.create's popup has no location field")
    }

    /// Item 4: ⇧⌘Y runs `_execute_action` (the popup); a click back in the window closes it, as in Chrome.
    /// ⇧⌘U runs the fixture's own command, which opens its side panel.
    func testCommands() throws {
        launchChromium()
        openPage("https://example.com/")
        mainWindow.typeKey("y", modifierFlags: [.command, .shift])
        let popup = app.staticTexts["Parity popup"]
        XCTAssertTrue(popup.waitForExistence(timeout: 8), "⇧⌘Y didn't open the popup")
        mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)).click()
        XCTAssertTrue(popup.waitForNonExistence(timeout: 5), "The popup stayed after a click in the window")

        mainWindow.typeKey("u", modifierFlags: [.command, .shift])
        XCTAssertTrue(sidePanel().waitForExistence(timeout: 8), "⇧⌘U didn't open the side panel")
    }

    /// Item 9: the side panel opens from the popup, resizes from its leading edge and closes from its button;
    /// with openPanelOnActionClick the action opens it.
    func testSidePanel() throws {
        launchChromium()
        openPage("https://example.com/")
        pinFixture()
        actionButton().click()
        let open = app.buttons["Open side panel"]
        XCTAssertTrue(open.waitForExistence(timeout: 8), app.debugDescription)
        open.click()
        let panel = sidePanel()
        XCTAssertTrue(panel.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Parity side panel"].waitForExistence(timeout: 8))

        let before = panel.frame.width
        let edge = panel.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 1, dy: 0))
        edge.press(forDuration: 0.2, thenDragTo: edge.withOffset(CGVector(dx: -120, dy: 0)))
        XCTAssertGreaterThan(panel.frame.width, before + 60, "Dragging the edge didn't widen the panel: \(app.debugDescription)")

        app.buttons["control.extensionSidePanel.close"].click()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "The close button left the panel open")

        // openPanelOnActionClick: the popup's button turns it on; the action then opens the panel instead.
        actionButton().click()
        let toggle = app.buttons["Toggle side panel on action click"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 8))
        toggle.click()
        XCTAssertTrue(app.staticTexts["Parity popup"].waitForNonExistence(timeout: 5))
        actionButton().click()
        XCTAssertTrue(sidePanel().waitForExistence(timeout: 8), "The action didn't open the panel")
        XCTAssertFalse(app.staticTexts["Parity popup"].exists)
        // Back to the popup for the next run.
        app.buttons["control.extensionSidePanel.close"].click()
        actionButton().rightClick()
        let openPanel = app.menuItems.matching(labelContaining: "side panel").firstMatch
        if openPanel.waitForExistence(timeout: 3) { openPanel.click() }
        else { app.typeKey(.escape, modifierFlags: []) }
    }

    /// Item 6: with site access "on click", the request button grants the site (reloading the page when Chromium
    /// asks to), after which the content script runs.
    func testSiteAccessRequest() throws {
        launchChromium()
        openPage("https://example.com/")
        pinFixture()
        actionButton().rightClick()
        let access = app.menuItems["Site Permissions"]
        XCTAssertTrue(access.waitForExistence(timeout: 5), app.debugDescription)
        access.hover()
        app.typeKey(.rightArrow, modifierFlags: [])
        // Chromium's "on click" site access.
        let onClick = app.menuItems["Ask on Every Visit"]
        XCTAssertTrue(onClick.waitForExistence(timeout: 5), app.debugDescription)
        onClick.click()
        dismissExtensionDialog(confirm: true)

        openPage("https://example.com/?access")
        XCTAssertFalse(app.staticTexts["Boaz parity content script ran"].waitForExistence(timeout: 3),
                       "The content script ran without site access")
        let request = app.buttons["control.extensionRequestAccess"]
        XCTAssertTrue(request.waitForExistence(timeout: 8), "No request-access button")
        request.click()
        // Chromium runs the blocked script at once, or asks to reload when the page needs it.
        dismissExtensionDialog(confirm: true)
        XCTAssertTrue(app.staticTexts["Boaz parity content script ran"].waitForExistence(timeout: 10),
                      "The content script didn't run after reloading")
        XCTAssertFalse(request.exists)
    }

    /// Item 11: the extension stays out of private windows until Allow in Incognito is on, then works there.
    func testPrivateWindow() throws {
        launchChromium()
        menu("File", "New Incognito Window")
        let first = app.windows.firstMatch
        openPage("https://example.com/", in: first)
        first.buttons["control.extensions"].click()
        XCTAssertFalse(app.descendants(matching: .any)["control.extensionRow.\(fixtureID)"].waitForExistence(timeout: 3),
                       "The fixture shows in a private window without Allow in Incognito")
        app.typeKey(.escape, modifierFlags: [])
        first.buttons["_XCUI:CloseWindow"].click()

        openPage("chrome://extensions/?id=\(fixtureID)")
        // As in Chrome, an unpacked extension that reloads with Developer mode off is disabled.
        let developerMode = app.switches["Developer mode"]
        XCTAssertTrue(developerMode.waitForExistence(timeout: 10), app.debugDescription)
        if !Self.isOn(developerMode) {
            developerMode.click()
            sleep(1) // The page grows Developer mode's toolbar, moving the rows below.
        }
        let allow = app.switches.matching(labelContaining: "Allow in Incognito").firstMatch
        XCTAssertTrue(allow.waitForExistence(timeout: 10), app.debugDescription)
        allow.click()
        sleep(2) // Chromium reloads the extension with the new setting.
        menu("File", "New Incognito Window")
        let second = app.windows.firstMatch
        openPage("https://example.com/", in: second)
        second.typeKey("y", modifierFlags: [.command, .shift])
        XCTAssertTrue(app.staticTexts["Parity popup"].waitForExistence(timeout: 8),
                      "The fixture's popup didn't open in the private window")
    }

    /// As Chrome's incognito: a profile's private windows share one session, which ends with the last of them.
    func testPrivateWindowsShareOneSession() throws {
        launchChromium()
        let cookie = app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'boazprivate'")).firstMatch
        menu("File", "New Incognito Window")
        let first = app.windows.firstMatch
        openPage("https://httpbin.org/cookies/set?boazprivate=1", in: first)
        XCTAssertTrue(cookie.waitForExistence(timeout: 15), "The first private window didn't get the cookie")

        menu("File", "New Incognito Window")
        let second = app.windows.firstMatch
        openPage("https://httpbin.org/cookies", in: second)
        XCTAssertTrue(cookie.waitForExistence(timeout: 15), "A second private window doesn't share the session")

        second.buttons["_XCUI:CloseWindow"].click()
        app.windows.firstMatch.buttons["_XCUI:CloseWindow"].click()
        XCTAssertEqual(app.windows.count, 1, "The private windows didn't close")
        menu("File", "New Incognito Window")
        let fresh = app.windows.firstMatch
        openPage("https://httpbin.org/cookies", in: fresh)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'cookies'")).firstMatch
            .waitForExistence(timeout: 15), "httpbin didn't answer")
        XCTAssertFalse(cookie.exists, "A new private session kept the last one's cookie")
    }

    /// Item 7 and the store check: installs JSON Formatter and uBlock Origin Lite from the Chrome Web Store with
    /// the store's own button and Boaz's confirmation sheet, checks each works on a page, then removes both.
    func testWebStoreInstalls() throws {
        launchChromium()
        let formatter = "bcjindcccaagfpapjjmafapmmgkkhgoa"
        let ublock = "ddkjiahejlhfcafbddmgiahcphecmpfh"
        install(storeID: formatter, path: "json-formatter")
        openPage("https://api.github.com/")
        XCTAssertTrue(app.descendants(matching: .any).matching(labelContaining: "Parsed").firstMatch
            .waitForExistence(timeout: 15), "JSON Formatter didn't format the page")

        // Without the extensions button on screen, the post-install bubble points at the window's corner.
        mainWindow.buttons["sidebar.left"].click()
        install(storeID: ublock, path: "ublock-origin-lite", sidebarHidden: true)
        app.typeKey("s", modifierFlags: .command)  // the toggle hides with the sidebar
        // uBlock Origin Lite's popup reports on the current page.
        openPage("https://example.com/")
        openExtensionsMenu()
        let row = app.descendants(matching: .any)["control.extensionRow.\(ublock)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "uBlock Origin Lite isn't in the extensions menu")
        row.click()
        XCTAssertTrue(app.descendants(matching: .any).matching(labelContaining: "uBlock").firstMatch
            .waitForExistence(timeout: 8), "uBlock Origin Lite's popup didn't open")
        mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)).click()

        for id in [formatter, ublock] { remove(id) }
        openExtensionsMenu()
        XCTAssertFalse(app.descendants(matching: .any)["control.extensionRow.\(formatter)"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["control.extensionRow.\(ublock)"].exists)
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Helpers

    private func launchChromium() {
        // A fresh home (and so a fresh Chromium profile) every launch: Chromium keeps an unpacked extension's
        // service worker from the last run. The app creates it; the test runner's sandbox may not reach it.
        let base = ProcessInfo.processInfo.environment["BOAZ_UITEST_HOME"]
            ?? "/Volumes/BoazBuild/cef/direct/profiles/lane-a-uitest-home"
        let home = base + "/" + UUID().uuidString
        launch(fixture: "one-space", environment: ["CFFIXED_USER_HOME": home, "HOME": home],
               arguments: ["--use-mock-keychain", "--load-extension=\(Self.fixturePath)", "-onboardingCompleted", "YES"])
        XCTAssertTrue(app.buttons["control.extensions"].waitForExistence(timeout: 20), app.debugDescription)
    }

    /// Goes to `url` in the window's current tab, through the address field (⌘L).
    private func openPage(_ url: String, in window: XCUIElement? = nil) {
        let target = window ?? mainWindow
        target.typeKey("l", modifierFlags: .command)
        app.typeText(url + "\n")
        sleep(3)
    }

    private func openExtensionsMenu() {
        let button = mainWindow.buttons["control.extensions"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.click()
        let menu = app.descendants(matching: .any)["screen.extensions"]
        if !menu.waitForExistence(timeout: 3) { button.click() } // The click only closed the last popover.
        XCTAssertTrue(menu.waitForExistence(timeout: 5), app.debugDescription)
    }

    private func pinFixture() {
        guard !actionButton().exists else { return }
        openExtensionsMenu()
        let pin = app.descendants(matching: .any)["control.extensionPin.\(fixtureID)"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5), app.debugDescription)
        pin.click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(actionButton().waitForExistence(timeout: 5), "Pinning didn't add the toolbar button")
    }

    private func actionButton(_ id: String? = nil) -> XCUIElement {
        app.buttons["control.extensionAction.\(id ?? fixtureID)"].firstMatch
    }

    private func sidePanel() -> XCUIElement {
        app.descendants(matching: .any)["screen.extensionSidePanel"].firstMatch
    }

    /// Chromium's reload or post-install prompt, when one is showing.
    private func dismissExtensionDialog(confirm: Bool) {
        let dialog = app.descendants(matching: .any)["screen.extensionDialog"]
        guard dialog.waitForExistence(timeout: 3) else { return }
        let button = app.buttons[confirm ? "control.extensionDialog.ok" : "control.extensionDialog.cancel"]
        if button.exists { button.click() } else { app.typeKey(.escape, modifierFlags: []) }
    }

    private func install(storeID: String, path: String, sidebarHidden: Bool = false) {
        openPage("https://chromewebstore.google.com/detail/\(path)/\(storeID)")
        // The store lays out wider than the test window's page; zoomed out, its button is on screen.
        mainWindow.typeKey("-", modifierFlags: .command)
        mainWindow.typeKey("-", modifierFlags: .command)
        let add = app.buttons.matching(labelContaining: "Add to Chrome").firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 20), "No Add to Chrome button for \(path)")
        sleep(1)
        add.click()
        let confirm = app.sheets.buttons.matching(labelContaining: "Add extension").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 20), "Boaz's install sheet didn't appear: \(app.debugDescription)")
        confirm.click()
        mainWindow.typeKey("0", modifierFlags: .command)
        // Chromium's post-install bubble at the extension's button: "<name> has been added to Chromium".
        let installed = app.popovers.staticTexts.matching(NSPredicate(format: "value CONTAINS[c] 'added'")).firstMatch
        XCTAssertTrue(installed.waitForExistence(timeout: 30), "No post-install confirmation for \(path)")
        XCTAssertGreaterThan(app.popovers.firstMatch.frame.width, 200, "The post-install bubble is squashed")
        if sidebarHidden {
            XCTAssertGreaterThan(app.popovers.firstMatch.frame.maxX, mainWindow.frame.midX,
                                 "Without the extensions button, the bubble isn't at the window's trailing corner")
        }
        // Like Chrome's, the bubble closes when the window gets a click.
        mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)).click()
        XCTAssertTrue(app.popovers.firstMatch.waitForNonExistence(timeout: 5), "The post-install bubble stayed open")
        if sidebarHidden { return }
        openExtensionsMenu()
        XCTAssertTrue(app.descendants(matching: .any)["control.extensionRow.\(storeID)"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Removes an extension from its action's menu (pinning it first), confirming Boaz's removal sheet.
    private func remove(_ id: String) {
        if !actionButton(id).exists {
            openExtensionsMenu()
            app.descendants(matching: .any)["control.extensionPin.\(id)"].click()
            app.typeKey(.escape, modifierFlags: [])
        }
        let action = actionButton(id)
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.rightClick()
        let item = app.menuItems.matching(labelContaining: "Remove from").firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
        item.click()
        let confirm = app.sheets.buttons.matching(labelContaining: "Remove").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "No removal sheet")
        confirm.click()
        XCTAssertTrue(action.waitForNonExistence(timeout: 10), "\(id) is still in the toolbar")
    }

    private static func isOn(_ toggle: XCUIElement) -> Bool {
        (toggle.value as? String) == "1" || (toggle.value as? Int) == 1 || (toggle.value as? Bool) == true
    }

    /// Chromium's ID for an unpacked extension: the first 128 bits of SHA-256 of its path, as letters a–p.
    private static func extensionID(path: String) -> String {
        SHA256.hash(data: Data(path.utf8)).prefix(16).flatMap { [Int($0 >> 4), Int($0 & 0xF)] }
            .map { String(UnicodeScalar(UInt8(97 + $0))) }.joined()
    }
}

private extension XCUIElementQuery {
    func matching(labelContaining text: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "label CONTAINS[c] %@ OR title CONTAINS[c] %@", text, text))
    }
}
