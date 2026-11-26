import XCTest

/// Native-UI steps of the runtime acceptance run (`Tools/acceptance/runtime.py`) against an installed production Boaz.
/// Runs only with `BOAZ_ACCEPTANCE_APP` set to that app's path, and against /Applications/Boaz.app only on a CI
/// runner. It attaches to the running app as it is, with no test mode, fixture or relaunch.
final class BoazAcceptanceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["BOAZ_ACCEPTANCE_APP"], !path.isEmpty else {
            throw XCTSkip("Set BOAZ_ACCEPTANCE_APP to an installed Boaz to run the acceptance steps.")
        }
        // /Applications/Boaz.app on a person's Mac is their real Boaz and library (must-have #13).
        guard URL(fileURLWithPath: path).resolvingSymlinksInPath().path != "/Applications/Boaz.app"
                || environment["CI"] == "true" else {
            throw XCTSkip("BoazAcceptanceUITests drives /Applications/Boaz.app only on a CI runner (CI=true).")
        }
        continueAfterFailure = true
        app = XCUIApplication(url: URL(fileURLWithPath: path))
        app.activate()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30), "Boaz shows a window")
    }

    /// Must-have #1: no menu names WebKit or a browser engine (the search engine is a setting, not an engine).
    func testMenusNameNoEngine() {
        let bar = app.menuBars.firstMatch
        var titles: [String] = []
        for index in 0..<bar.menuBarItems.count {
            let item = bar.menuBarItems.element(boundBy: index)
            guard item.isHittable else { continue }
            item.click()
            titles.append(item.title)
            titles += item.menus.firstMatch.menuItems.allElementsBoundByIndex.map { $0.title }
            app.typeKey(.escape, modifierFlags: [])
        }
        let attachment = XCTAttachment(string: titles.joined(separator: "\n"))
        attachment.name = "menu-titles"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(titles.count, 20, "read the menus")
        let named = titles.filter {
            $0.range(of: "webkit", options: .caseInsensitive) != nil ||
                $0.range(of: #"(?<!search )\bengine\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        }
        XCTAssertEqual(named, [], "menus name an engine")
    }

    /// Row 4: opens each address in `BOAZ_ACCEPTANCE_URLS` (comma-separated) as a new tab, as a person does with
    /// ⌘T. (A link another app opens goes to a Quick Window instead, which isn't kept.)
    func testOpenTabs() throws {
        try openTabs(in: app.windows.firstMatch)
    }

    /// Row 2: a new private window (⌘⇧N, titled after its page, not "Private") with each address in
    /// `BOAZ_ACCEPTANCE_URLS` as a tab.
    func testOpenPrivateTabs() throws {
        let windows = app.windows.count
        app.windows.firstMatch.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertTrue(waitUntil(15) { self.app.windows.count > windows }, "⌘⇧N didn't open a private window")
        guard app.windows.count > windows else { return }
        sleep(2)
        try openTabs(in: app.windows.firstMatch)
    }

    /// Row 2: closes the front window (the private one just used) with its close button; never the last window.
    func testCloseFrontWindow() {
        let windows = app.windows.count
        XCTAssertGreaterThan(windows, 1, "Only one window is open")
        guard windows > 1 else { return }
        app.windows.firstMatch.buttons[XCUIIdentifierCloseWindow].click()
        XCTAssertTrue(waitUntil(10) { self.app.windows.count < windows }, "The front window didn't close")
    }

    /// Row 2's password probe: signs in on the fixture's /login page (open in the front tab) with
    /// `BOAZ_ACCEPTANCE_LOGIN`'s run-generated test credentials ("user:password"), then reports whether Boaz offered
    /// to save them. The offer is always declined; saving needs the person's own authentication (manual P3). With
    /// `BOAZ_ACCEPTANCE_EXPECT_PROMPT=0` (a private window) an offer fails the test, with `1` its absence does.
    func testPasswordPrompt() throws {
        let login = try required("BOAZ_ACCEPTANCE_LOGIN").split(separator: ":", maxSplits: 1).map(String.init)
        let user = app.textFields.matching(labelContaining: "Username").firstMatch
        XCTAssertTrue(user.waitForExistence(timeout: 15), "No username field on the login page")
        user.click()
        app.typeText(login[0])
        let password = app.secureTextFields.matching(labelContaining: "Password").firstMatch
        XCTAssertTrue(password.waitForExistence(timeout: 5), "No password field on the login page")
        password.click()
        app.typeText(login[1] + "\n")
        let offer = app.sheets.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Save Password' OR label CONTAINS 'Save Password'")).firstMatch
        let shown = offer.waitForExistence(timeout: 15)
        record(shown ? "password prompt shown" : "password prompt not shown")
        if shown {
            app.sheets.buttons["Not Now"].firstMatch.click()
        }
        switch ProcessInfo.processInfo.environment["BOAZ_ACCEPTANCE_EXPECT_PROMPT"] {
        case "0": XCTAssertFalse(shown, "Boaz offered to save a password typed in a private window")
        case "1": XCTAssertTrue(shown, "No save offer")
        default: break
        }
    }

    private func openTabs(in window: XCUIElement) throws {
        let urls = try required("BOAZ_ACCEPTANCE_URLS").split(separator: ",")
        for url in urls {
            window.typeKey("t", modifierFlags: .command)
            sleep(1)
            app.typeText(url + "\n")
            sleep(3)
        }
    }

    /// Switches to the space named `BOAZ_ACCEPTANCE_SPACE` from the Spaces menu, where it's listed after its icon.
    func testSwitchSpace() throws {
        let name = try required("BOAZ_ACCEPTANCE_SPACE")
        app.menuBars.menuBarItems["Spaces"].click()
        let item = app.menuBars.menuItems.matching(NSPredicate(format: "title == %@ OR title ENDSWITH %@",
                                                               name, " " + name)).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), "No \(name) in the Spaces menu")
        item.click()
        sleep(3)
    }

    /// Row 3, part B: loads each folder in `BOAZ_ACCEPTANCE_UNPACKED` (comma-separated) with chrome://extensions →
    /// Developer mode → Load unpacked, in the current space's profile.
    func testLoadUnpacked() throws {
        let folders = try required("BOAZ_ACCEPTANCE_UNPACKED").split(separator: ",").map(String.init)
        let developer = app.descendants(matching: .any).matching(labelContaining: "Developer mode").firstMatch
        let load = app.buttons.matching(labelContaining: "Load unpacked").firstMatch
        for folder in folders {
            // An extension can open its own welcome tab or window on install (1Password does), so each folder
            // starts from chrome://extensions in the front window again.
            app.windows.firstMatch.typeKey("l", modifierFlags: .command)
            app.typeText("chrome://extensions\n")
            XCTAssertTrue(developer.waitForExistence(timeout: 20), "chrome://extensions didn't open")
            if !load.waitForExistence(timeout: 3) { developer.click() }
            XCTAssertTrue(load.waitForExistence(timeout: 10), "No Load unpacked button")
            load.click()
            sleep(2)
            app.typeKey("g", modifierFlags: [.command, .shift])
            sleep(1)
            app.typeText(folder + "\n")
            sleep(1)
            let select = app.buttons.matching(NSPredicate(format: "title IN %@ OR label IN %@",
                                                          ["Select", "Open"], ["Select", "Open"])).firstMatch
            XCTAssertTrue(select.waitForExistence(timeout: 10), "No folder chooser for \(folder)")
            select.click()
            sleep(3)
            record("loaded \(folder)")
        }
    }

    /// Row 3, part B: for each ID in `BOAZ_ACCEPTANCE_EXTENSIONS`, pin it, open its popup from the toolbar, unpin
    /// it. With `BOAZ_ACCEPTANCE_FIXTURE` (the parity fixture's ID), also its shortcut and side panel.
    func testExtensionControls() throws {
        let ids = try required("BOAZ_ACCEPTANCE_EXTENSIONS").split(separator: ",").map(String.init)
        let window = app.windows.firstMatch
        for id in ids {
            setPinned(id, true)
            let action = app.buttons["control.extensionAction.\(id)"].firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 10), "Pinning \(id) didn't add its toolbar button")
            let before = app.popovers.count + app.windows.count
            action.click()
            XCTAssertTrue(waitUntil(15) { self.app.popovers.count + self.app.windows.count > before },
                          "\(id)'s popup didn't open")
            app.typeKey(.escape, modifierFlags: [])
            sleep(1)
            setPinned(id, false)
            XCTAssertTrue(action.waitForNonExistence(timeout: 10), "Unpinning \(id) left its toolbar button")
            record("controls \(id)")
        }
        if let fixture = ProcessInfo.processInfo.environment["BOAZ_ACCEPTANCE_FIXTURE"], !fixture.isEmpty {
            window.typeKey("y", modifierFlags: [.command, .shift])  // _execute_action
            XCTAssertTrue(app.descendants(matching: .any).matching(labelContaining: "Parity popup").firstMatch
                .waitForExistence(timeout: 10), "The fixture's ⌘⇧Y shortcut didn't open its popup")
            app.typeKey(.escape, modifierFlags: [])
            sleep(1)
            window.typeKey("u", modifierFlags: [.command, .shift])  // open-panel
            let panel = app.descendants(matching: .any)["screen.extensionSidePanel"].firstMatch
            XCTAssertTrue(panel.waitForExistence(timeout: 10), "The fixture's ⌘⇧U shortcut didn't open its side panel")
            window.typeKey("u", modifierFlags: [.command, .shift])
            XCTAssertTrue(panel.waitForNonExistence(timeout: 10), "The side panel didn't close")
            record("fixture shortcut and side panel")
        }
    }

    private func setPinned(_ id: String, _ pinned: Bool) {
        let action = app.buttons["control.extensionAction.\(id)"].firstMatch
        guard action.exists != pinned else { return }
        let button = app.windows.firstMatch.buttons["control.extensions"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "No extensions button")
        button.click()
        let pin = app.descendants(matching: .any)["control.extensionPin.\(id)"]
        XCTAssertTrue(pin.waitForExistence(timeout: 10), "\(id) isn't in the extensions menu")
        pin.click()
        app.typeKey(.escape, modifierFlags: [])
    }

    private func required(_ name: String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
            throw XCTSkip("Set \(name).")
        }
        return value
    }

    /// Row 3, part A, after runtime.py clicked the live Chrome Web Store's own button through Local Automation (a
    /// trusted click there: the store's button is often clipped or covered for an accessibility click): Boaz's
    /// install sheet for the extension in `BOAZ_ACCEPTANCE_EXTENSIONS`, its confirmation, its pin and its popup.
    func testWebStoreInstallSheet() throws {
        let id = try required("BOAZ_ACCEPTANCE_EXTENSIONS")
        let confirm = app.sheets.buttons.matching(labelContaining: "Add extension").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 30), "Boaz's install sheet didn't appear for \(id)")
        confirm.click()
        let installed = app.popovers.staticTexts.matching(NSPredicate(format: "value CONTAINS[c] 'added'")).firstMatch
        XCTAssertTrue(installed.waitForExistence(timeout: 60), "No post-install confirmation for \(id)")
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)).click()
        setPinned(id, true)
        let action = app.buttons["control.extensionAction.\(id)"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 10), "Pinning \(id) didn't add its toolbar button")
        let before = app.popovers.count + app.windows.count
        action.click()
        XCTAssertTrue(waitUntil(15) { self.app.popovers.count + self.app.windows.count > before },
                      "\(id)'s popup didn't open")
        app.typeKey(.escape, modifierFlags: [])
        record("installed \(id)")
    }

    private func record(_ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = text
        attachment.lifetime = .keepAlways
        add(attachment)
        print("BoazAcceptance: \(text)")
    }

    private func waitUntil(_ seconds: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        return false
    }
}

private extension XCUIElementQuery {
    func matching(labelContaining text: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "label CONTAINS[c] %@ OR title CONTAINS[c] %@", text, text))
    }
}
