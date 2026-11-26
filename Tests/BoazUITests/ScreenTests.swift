import AppKit
import XCTest

/// Every screen the Mac app can show, each opened the way a user opens it, checked with `assertScreenIntact`, and
/// closed again. The standard fixture's pages are `data:` URLs; Playground's peek link goes to a closed port on this
/// Mac's loopback address (127.0.0.1:47), so nothing here touches the network.
final class ScreenTests: BoazUITestCase {
    // MARK: Windows

    func testMainWindowLight() { runMainWindow(.light) }
    func testMainWindowDark() { runMainWindow(.dark) }

    private func runMainWindow(_ appearance: Appearance) {
        launch(appearance: appearance)
        XCTAssertTrue(waitForSpace("Work"))
        assertScreenIntact(element("screen.browser"), name: "browser-empty")
        openSidebarTab("Today Tab")
        assertScreenIntact(element("screen.browser"), name: "browser-page")
    }

    func testMainWindowAtMinimumSize() {
        // The minimum size (720 × 460); dragging the window's corner doesn't resize it on the CI runner.
        launch(arguments: ["-BoazUITestWindowSize", "720x460"])
        openSidebarTab("Today Tab")
        let deadline = Date.now.addingTimeInterval(5)
        while mainWindow.frame.width >= 800, Date.now < deadline { RunLoop.current.run(until: .now + 0.2) }
        let size = mainWindow.frame.size
        XCTAssertLessThan(size.width, 800, "The window didn't open at its minimum size (\(size))")
        XCTAssertGreaterThanOrEqual(size.width, 719)
        XCTAssertGreaterThanOrEqual(size.height, 459)
        assertScreenIntact(element("screen.browser"), name: "browser-minimum-size")
    }

    func testIncognitoWindow() {
        launch()
        app.typeKey("n", modifierFlags: [.command, .shift])
        let incognito = element("screen.incognito")
        XCTAssertTrue(incognito.waitForExistence(timeout: 5), "No incognito window")
        assertScreenIntact(incognito, name: "incognito")
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForDisappearance(incognito))
    }

    func testQuickWindow() {
        launch()
        menu("File", "New Quick Window")
        let quick = element("screen.quickWindow")
        XCTAssertTrue(quick.waitForExistence(timeout: 5), "No Quick Window")
        assertScreenIntact(quick, name: "quick-window")
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForDisappearance(quick))
    }

    func testArchiveWindowAndClearConfirmation() {
        launch()
        app.typeKey("a", modifierFlags: [.command, .option])
        let window = app.windows["Archive"]
        XCTAssertTrue(window.waitForExistence(timeout: 5), "No Archive window")
        XCTAssertTrue(window.staticTexts["Archived Page"].waitForExistence(timeout: 5), "The fixture's archived tab isn't listed")
        assertScreenIntact(window, name: "archive")

        window.buttons["Clear Archive"].firstMatch.click()
        assertConfirmationThenCancel(in: window, name: "clear-archive", destructive: "Clear Archive")
        XCTAssertTrue(window.staticTexts["Archived Page"].exists, "Cancel cleared the archive")
        window.typeKey("w", modifierFlags: .command)
    }

    func testHistoryWindowAndClearConfirmation() {
        launch()
        app.typeKey("y", modifierFlags: .command)
        let window = app.windows["History"]
        XCTAssertTrue(window.waitForExistence(timeout: 5), "No History window")
        XCTAssertTrue(window.staticTexts["History Page"].waitForExistence(timeout: 5), "The fixture's visit isn't listed")
        assertScreenIntact(window, name: "history")

        window.buttons["Clear History"].firstMatch.click()
        assertConfirmationThenCancel(in: window, name: "clear-history", destructive: "Clear History")
        XCTAssertTrue(window.staticTexts["History Page"].exists, "Cancel cleared history")
        window.typeKey("w", modifierFlags: .command)
    }

    // MARK: Sidebar

    func testSidebarHiddenAndPeeking() {
        launch()
        openSidebarTab("Today Tab")
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(waitForDisappearance(sidebar), "⌘S didn't hide the sidebar")
        assertScreenIntact(element("screen.browser"), name: "sidebar-hidden")

        // Hovering the window's left edge slides the sidebar out over the page.
        mainWindow.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 3, dy: 0)).hover()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5), "The sidebar didn't peek")
        assertScreenIntact(sidebar, name: "sidebar-peeking")

        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
    }

    // MARK: Overlays

    func testCommandBarNewTabLight() { runCommandBarNewTab(.light) }
    func testCommandBarNewTabDark() { runCommandBarNewTab(.dark) }

    private func runCommandBarNewTab(_ appearance: Appearance) {
        launch(appearance: appearance)
        openCommandBar()
        let bar = element("screen.commandBar")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "⌘T didn't open the command bar")
        assertScreenIntact(bar, name: "command-bar-new-tab")
        // Typing lists matching tabs.
        app.typeText("Article")
        XCTAssertTrue(bar.buttons.matching(NSPredicate(format: "label CONTAINS 'Article One'")).firstMatch.waitForExistence(timeout: 5),
                      "Typing didn't suggest the matching tab")
        assertScreenIntact(bar, name: "command-bar-suggestions")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForDisappearance(bar))
    }

    func testCommandBarCurrentTab() {
        launch()
        openSidebarTab("Today Tab")
        app.typeKey("l", modifierFlags: .command)
        let bar = element("screen.commandBar")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "⌘L didn't open the command bar")
        let field = bar.textFields["control.commandBar.field"]
        XCTAssertTrue((field.value as? String ?? "").hasPrefix("data:text/html"), "⌘L should start from the tab's address")
        assertScreenIntact(bar, name: "command-bar-current-tab")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForDisappearance(bar))
    }

    func testFindBar() {
        launch()
        openSidebarTab("Today Tab")
        app.typeKey("f", modifierFlags: .command)
        let field = mainWindow.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "⌘F didn't show the find bar")
        app.typeText("Today")
        assertScreenIntact(element("screen.browser"), name: "find-bar")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForDisappearance(field))
    }

    func testPeekOverlay() {
        launch()
        let page = openSidebarTab("Playground")
        let link = page.links["Peek link"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10), "The Playground page never loaded")
        link.click()
        let peek = element("screen.peek")
        XCTAssertTrue(peek.waitForExistence(timeout: 5), "A pinned tab's new-window link didn't peek")
        assertScreenIntact(peek, name: "peek")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForDisappearance(peek))
    }

    func testPagePopupSheet() {
        launch()
        let page = openSidebarTab("Playground")
        let button = page.buttons["Open popup"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "The Playground page never loaded")
        button.click()
        let popup = element("screen.popup")
        XCTAssertTrue(popup.waitForExistence(timeout: 5), "window.open with a size didn't open the pop-up sheet")
        assertScreenIntact(popup, name: "page-popup")
        popup.buttons["Close"].firstMatch.click()
        XCTAssertTrue(waitForDisappearance(popup))
    }

    /// A window a script opens keeps `window.opener` even without pop-up features: the child posts back and the
    /// opener hears it. Checkout flows (PayPal, a bank's 3-D Secure step) live on that channel.
    func testScriptWindowKeepsItsOpener() {
        launch(fixture: "opener")
        let page = openSidebarTab("Opener Playground")
        let pay = page.buttons["Pay"].firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 10), "The Opener Playground page never loaded")
        pay.click()
        XCTAssertTrue(page.staticTexts["heard:done"].waitForExistence(timeout: 10),
                      "The script window's postMessage never reached its opener")
    }

    /// The pop-up host reaches into WebPage's internals. After a script window has opened and talked back, Settings ▸
    /// About must still report no WebKit problems; on a WebKit update that breaks the reflection this goes red.
    func testWebKitInternalsStillWorkAfterAScriptWindow() {
        launch(fixture: "opener")
        let page = openSidebarTab("Opener Playground")
        let pay = page.buttons["Pay"].firstMatch
        XCTAssertTrue(pay.waitForExistence(timeout: 10), "The Opener Playground page never loaded")
        pay.click()
        XCTAssertTrue(page.staticTexts["heard:done"].waitForExistence(timeout: 10),
                      "The script window's postMessage never reached its opener")
        _ = openSettings(tab: "General")
        let line = element("settings.webkitDiagnostics")
        XCTAssertTrue(line.waitForExistence(timeout: 10), "Settings ▸ About has no WebKit internals line")
        XCTAssertFalse(line.label.contains("Degraded"), "WebKit internals fell back: \(line.label)")
    }

    func testSplitView() {
        launch()
        openSidebarTab("Today Tab")
        app.typeKey("=", modifierFlags: [.control, .shift])
        let bar = element("screen.commandBar")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "⌃⇧= didn't ask what to split with")
        app.typeText("data:text/html,<title>Split</title><h1>Split</h1>\r")
        XCTAssertTrue(waitForDisappearance(bar))
        let panes = mainWindow.webViews
        XCTAssertTrue(panes.element(boundBy: 1).waitForExistence(timeout: 10), "Split view didn't show two pages")
        assertScreenIntact(element("screen.browser"), name: "split-view")
        app.typeKey("=", modifierFlags: [.control, .shift])
        XCTAssertTrue(waitForDisappearance(panes.element(boundBy: 1)), "⌃⇧= again didn't close the split")
    }

    func testToast() {
        // The audit takes longer than a toast's five seconds, so the toast stays up until Undo takes it down.
        launch(arguments: ["-BoazUITestToastSeconds", "120"])
        openSidebarTab("Today Tab")
        // Closing a Today tab archives it and offers Undo.
        app.typeKey("w", modifierFlags: .command)
        let toast = element("screen.toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 3), "Closing a Today tab didn't show a toast")
        XCTAssertTrue(toast.buttons["Undo"].exists, "The archive toast has no Undo")
        assertScreenIntact(toast, name: "toast")
        toast.buttons["Undo"].click()
        XCTAssertTrue(waitForDisappearance(toast, timeout: 3), "Undo didn't take the toast down")
        XCTAssertTrue(sidebar.buttons["Today Tab"].firstMatch.waitForExistence(timeout: 3), "Undo didn't bring the tab back")
    }

    // MARK: Sheets

    func testNewSpaceEditorLight() { runNewSpaceEditor(.light) }
    func testNewSpaceEditorDark() { runNewSpaceEditor(.dark) }

    private func runNewSpaceEditor(_ appearance: Appearance) {
        launch(appearance: appearance)
        menu("Spaces", "New Space")
        let editor = element("screen.spaceEditor")
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "Spaces › New Space didn't open the editor")
        assertScreenIntact(editor, name: "space-editor-new")
        editor.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(waitForDisappearance(editor))
    }

    func testCustomizeSpaceEditor() {
        launch()
        XCTAssertTrue(waitForSpace("Work"))
        menu("View", "Customize Space…")
        let editor = element("screen.spaceEditor")
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "View › Customize Space… didn't open the editor")
        assertScreenIntact(editor, name: "space-editor-customize")
        editor.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(waitForDisappearance(editor))
    }

    func testRenameSheet() {
        launch()
        spaceMenu("Work", "Rename Space…")
        let sheet = element("screen.renameSheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Rename Space… didn't open the rename sheet")
        assertScreenIntact(sheet, name: "rename")
        sheet.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(waitForDisappearance(sheet))
    }

    func testArcImportSheet() {
        launch()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
        menu("File", "Import from Arc…")
        let sheet = element("screen.arcImport")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "File › Import from Arc… didn't open the import sheet")
        assertScreenIntact(sheet, name: "arc-import")
        sheet.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(waitForDisappearance(sheet))
    }

    /// The first-run flow, every step, without signing in, importing or changing the default browser.
    func testOnboardingEveryStep() {
        launch(arguments: ["-BoazResetOnboarding", "YES"])
        let onboarding = element("screen.onboarding")
        XCTAssertTrue(onboarding.waitForExistence(timeout: 10), "-BoazResetOnboarding didn't show onboarding")
        assertScreenIntact(onboarding, name: "onboarding-welcome")

        let withoutSync = onboarding.buttons["Continue Without Syncing"].firstMatch
        (withoutSync.exists ? withoutSync : onboarding.buttons["Continue"].firstMatch).click()
        let skip = onboarding.buttons["Skip"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 5), "No browsers step")
        assertScreenIntact(onboarding, name: "onboarding-browsers")

        skip.click()
        let notNow = onboarding.buttons["Not Now"].firstMatch
        XCTAssertTrue(notNow.waitForExistence(timeout: 5), "No default browser step")
        assertScreenIntact(onboarding, name: "onboarding-default-browser")

        notNow.click()
        let start = onboarding.buttons["Start Browsing"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 5), "No last step")
        assertScreenIntact(onboarding, name: "onboarding-done")
        start.click()
        XCTAssertTrue(waitForDisappearance(onboarding))
    }

    func testAISheet() throws {
        launch()
        openSidebarTab("Today Tab")
        let summarize = app.menuBars.menuBarItems["View"].menuItems["Summarize Page"]
        guard summarize.waitForExistence(timeout: 2) else {
            throw XCTSkip("Apple Intelligence isn't available on this Mac, so Boaz hides its AI entry points")
        }
        menu("View", "Summarize Page")
        let sheet = element("screen.ai")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Summarize Page didn't open the AI sheet")
        assertScreenIntact(sheet, name: "ai-summary")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForDisappearance(sheet))
    }

    func testQRCodeSheet() throws {
        // `QRCodeSheet` is presented only from the Chromium engine's page context menu (ChromiumApplication.swift);
        // the WebKit build this scheme tests has no way to open it.
        throw XCTSkip("The QR code sheet is reachable only in the Chromium build's page context menu")
    }

    // MARK: Develop

    func testViewPageSource() {
        launch()
        openSidebarTab("Today Tab")
        app.typeKey("u", modifierFlags: [.command, .option])
        let sheet = element("screen.pageSource")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "⌥⌘U didn't show the source")
        assertScreenIntact(sheet, name: "page-source")
        sheet.buttons["Done"].firstMatch.click()
        XCTAssertTrue(waitForDisappearance(sheet))
    }

    func testStorageSheet() {
        launch()
        openSidebarTab("Today Tab")
        menu("Develop", "Show Storage…")
        let sheet = element("screen.storage")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Develop › Show Storage… didn't open")
        assertScreenIntact(sheet, name: "storage")
        sheet.buttons["Done"].firstMatch.click()
        XCTAssertTrue(waitForDisappearance(sheet))
    }

    func testUserAgentSheet() {
        launch()
        openSidebarTab("Today Tab")
        menu("Develop", "User Agent", "Other…")
        let sheet = element("screen.userAgent")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "Develop › User Agent › Other… didn't open")
        assertScreenIntact(sheet, name: "user-agent")
        sheet.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(waitForDisappearance(sheet))
    }

    func testResponsiveDesignBar() {
        launch()
        openSidebarTab("Today Tab")
        app.typeKey("r", modifierFlags: [.command, .option])
        let bar = element("screen.responsiveBar")
        XCTAssertTrue(bar.waitForExistence(timeout: 5), "⌥⌘R didn't enter Responsive Design Mode")
        assertScreenIntact(element("screen.browser"), name: "responsive-design")
        app.typeKey("r", modifierFlags: [.command, .option])
        XCTAssertTrue(waitForDisappearance(bar))
    }

    func testJavaScriptConsole() {
        launch()
        openSidebarTab("Today Tab")
        app.typeKey("c", modifierFlags: [.command, .option])
        let console = element("screen.jsConsole")
        XCTAssertTrue(console.waitForExistence(timeout: 5), "⌥⌘C didn't show the console")
        assertScreenIntact(element("screen.browser"), name: "javascript-console")
        app.typeKey("c", modifierFlags: [.command, .option])
        XCTAssertTrue(waitForDisappearance(console))
    }

    // MARK: Confirmation dialogs (each cancelled)

    func testDeleteSpaceConfirmation() {
        launch()
        spaceMenu("Work", "Delete Space…")
        assertConfirmationThenCancel(in: mainWindow, name: "delete-space", destructive: "Delete Space")
        XCTAssertTrue(waitForSpace("Work", timeout: 2), "Cancel deleted the space")
    }

    /// A middle-click on a pinned tab with nothing loaded removes it from Pinned, after a warning; nothing else opens
    /// that warning. XCUITest has no middle-click, and the window server drops a synthesized one unless the test
    /// runner is trusted for Accessibility (System Settings › Privacy & Security), so without that this skips.
    func testRemovePinnedTabConfirmation() throws {
        guard AXIsProcessTrusted() else {
            throw XCTSkip("Needs a middle-click, which the test runner can send only when trusted for Accessibility")
        }
        launch()
        let docs = sidebar.buttons["Docs"].firstMatch
        XCTAssertTrue(docs.waitForExistence(timeout: 10))
        try middleClick(docs)
        assertConfirmationThenCancel(in: mainWindow, name: "remove-pinned", destructive: "Remove")
        XCTAssertTrue(sidebar.buttons["Docs"].exists, "Cancel removed the pinned tab")
    }

    func testResetShortcutsConfirmation() {
        // Reset is offered only with an override in place: ⌘T for New Tab, Arc's default, stored as Boaz stores it.
        let override = Data(#"{"newTab":{"key":"t","modifiers":1048576}}"#.utf8)
        launch(arguments: ["-keyBindingOverrides", "<" + override.map { String(format: "%02x", $0) }.joined() + ">"])
        let pane = openSettings(tab: "Shortcuts")
        pane.buttons["Reset to Defaults"].firstMatch.click()
        let window = app.windows.containing(.any, identifier: "screen.settings.shortcuts").firstMatch
        assertConfirmationThenCancel(in: window, name: "reset-shortcuts", destructive: "Reset to Defaults")
    }

    // MARK: Settings

    func testSettingsGeneralLight() { runSettings("General", appearance: .light) }
    func testSettingsGeneralDark() { runSettings("General", appearance: .dark) }
    func testSettingsTheme() { runSettings("Theme") }
    func testSettingsPrivacy() { runSettings("Privacy") }
    func testSettingsPasswords() { runSettings("Passwords") }
    func testSettingsAccountsAndSync() { runSettings("Accounts & Sync") }
    func testSettingsSites() { runSettings("Sites") }
    func testSettingsShortcutsLight() { runSettings("Shortcuts", appearance: .light) }
    func testSettingsShortcutsDark() { runSettings("Shortcuts", appearance: .dark) }

    private func runSettings(_ tab: String, appearance: Appearance = .light) {
        launch(appearance: appearance)
        let pane = openSettings(tab: tab)
        assertScreenIntact(pane, name: "settings-\(tab.lowercased().replacingOccurrences(of: " ", with: "-"))")
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(waitForDisappearance(pane))
    }

    // MARK: Helpers

    /// Clicks the sidebar row titled `title` and returns the page it shows.
    @discardableResult
    private func openSidebarTab(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let row = sidebar.buttons[title].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "No \(title) row in the sidebar", file: file, line: line)
        row.click()
        let page = mainWindow.webViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10), "\(title) didn't open a page", file: file, line: line)
        return page
    }

    /// Right-clicks the space's title in the sidebar and chooses `item` from its menu.
    private func spaceMenu(_ space: String, _ item: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(waitForSpace(space), "No \(space) space in the sidebar", file: file, line: line)
        spaceHeader.rightClick()
        let menuItem = app.menuItems[item].firstMatch
        XCTAssertTrue(menuItem.waitForExistence(timeout: 3), "No \(item) in the space menu", file: file, line: line)
        menuItem.click()
    }

    /// A confirmation dialog (shown as a sheet on `window`) is intact and offers `destructive` and Cancel; Cancel closes it.
    private func assertConfirmationThenCancel(in window: XCUIElement, name: String, destructive: String,
                                              file: StaticString = #filePath, line: UInt = #line) {
        let dialog = window.sheets.firstMatch
        XCTAssertTrue(dialog.waitForExistence(timeout: 5), "No \(name) confirmation", file: file, line: line)
        XCTAssertTrue(dialog.buttons[destructive].exists, "The \(name) confirmation has no \(destructive) button",
                      file: file, line: line)
        assertScreenIntact(dialog, name: name, file: file, line: line)
        dialog.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(waitForDisappearance(dialog), "Cancel didn't close the \(name) confirmation", file: file, line: line)
    }

    /// A middle-click where XCUITest's own hover left the pointer; only while the app is in front with `element`
    /// hittable, so it can't land on another app. (Posted to the app's process instead, AppKit never delivers it.)
    private func middleClick(_ element: XCUIElement) throws {
        element.hover()
        guard app.state == .runningForeground, element.isHittable else {
            throw XCTSkip("The row isn't in front to middle-click")
        }
        let point = CGPoint(x: element.frame.midX, y: element.frame.midY)
        for type in [CGEventType.otherMouseDown, .otherMouseUp] {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .center)
            event?.setIntegerValueField(.mouseEventButtonNumber, value: 2)
            event?.post(tap: .cghidEventTap)
        }
    }
}
