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
        let urls = (ProcessInfo.processInfo.environment["BOAZ_ACCEPTANCE_URLS"] ?? "").split(separator: ",")
        guard !urls.isEmpty else { throw XCTSkip("Set BOAZ_ACCEPTANCE_URLS to the addresses to open.") }
        let window = app.windows.firstMatch
        for url in urls {
            window.typeKey("t", modifierFlags: .command)
            sleep(1)
            app.typeText(url + "\n")
            sleep(3)
        }
    }

    /// Switches to the space named `BOAZ_ACCEPTANCE_SPACE` from the Spaces menu.
    func testSwitchSpace() throws {
        let name = try required("BOAZ_ACCEPTANCE_SPACE")
        app.menuBars.menuBarItems["Spaces"].click()
        let item = app.menuBars.menuItems[name]
        XCTAssertTrue(item.waitForExistence(timeout: 10), "No \(name) in the Spaces menu")
        item.click()
        sleep(3)
    }

    /// Row 3, part B: loads each folder in `BOAZ_ACCEPTANCE_UNPACKED` (comma-separated) with chrome://extensions →
    /// Developer mode → Load unpacked, in the current space's profile.
    func testLoadUnpacked() throws {
        let folders = try required("BOAZ_ACCEPTANCE_UNPACKED").split(separator: ",").map(String.init)
        let window = app.windows.firstMatch
        window.typeKey("l", modifierFlags: .command)
        app.typeText("chrome://extensions\n")
        let developer = app.descendants(matching: .any).matching(labelContaining: "Developer mode").firstMatch
        XCTAssertTrue(developer.waitForExistence(timeout: 20), "chrome://extensions didn't open")
        let load = app.buttons.matching(labelContaining: "Load unpacked").firstMatch
        if !load.exists { developer.click() }
        for folder in folders {
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

    /// Row 3, part A: each extension in `BOAZ_ACCEPTANCE_EXTENSIONS` (comma-separated IDs) installs from its live
    /// Chrome Web Store page with the store's own button and Boaz's sheet, lands in the toolbar and opens its popup.
    /// A consent, CAPTCHA or missing-listing page is never clicked through: after 3 tries the result is
    /// "inconclusive: store unreachable", which a re-run settles.
    func testWebStoreInstall() throws {
        let ids = (ProcessInfo.processInfo.environment["BOAZ_ACCEPTANCE_EXTENSIONS"] ?? "")
            .split(separator: ",").map(String.init)
        guard !ids.isEmpty else { throw XCTSkip("Set BOAZ_ACCEPTANCE_EXTENSIONS to the extension IDs to install.") }
        let window = app.windows.firstMatch
        for id in ids {
            var reached = false
            for _ in 1...3 where !reached {
                window.typeKey("l", modifierFlags: .command)
                app.typeText("https://chromewebstore.google.com/detail/\(id)\n")
                // The store lays out wider than a small window; zoomed out, its button is on screen.
                window.typeKey("-", modifierFlags: .command)
                window.typeKey("-", modifierFlags: .command)
                let add = app.buttons.matching(labelContaining: "Add to Chrome").firstMatch
                reached = add.waitForExistence(timeout: 30)
                if reached {
                    sleep(1)
                    add.click()
                }
                window.typeKey("0", modifierFlags: .command)
            }
            guard reached else {
                record("inconclusive: store unreachable for \(id)")
                XCTFail("inconclusive: store unreachable for \(id)")
                continue
            }
            let confirm = app.sheets.buttons.matching(labelContaining: "Add extension").firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 30), "Boaz's install sheet didn't appear for \(id)")
            confirm.click()
            let installed = app.popovers.staticTexts.matching(NSPredicate(format: "value CONTAINS[c] 'added'")).firstMatch
            XCTAssertTrue(installed.waitForExistence(timeout: 60), "No post-install confirmation for \(id)")
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.6)).click()

            let extensions = window.buttons["control.extensions"]
            XCTAssertTrue(extensions.waitForExistence(timeout: 10), "No extensions button")
            extensions.click()
            let pin = app.descendants(matching: .any)["control.extensionPin.\(id)"]
            XCTAssertTrue(pin.waitForExistence(timeout: 10), "\(id) isn't in the extensions menu")
            pin.click()
            app.typeKey(.escape, modifierFlags: [])
            let action = app.buttons["control.extensionAction.\(id)"].firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 10), "Pinning \(id) didn't add its toolbar button")
            let before = app.popovers.count + app.windows.count
            action.click()
            XCTAssertTrue(waitUntil(15) { self.app.popovers.count + self.app.windows.count > before },
                          "\(id)'s popup didn't open")
            app.typeKey(.escape, modifierFlags: [])
            record("installed \(id)")
        }
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
