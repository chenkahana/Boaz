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
}
