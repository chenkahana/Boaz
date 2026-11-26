import XCTest

/// Native-UI steps of the runtime acceptance run (`Tools/acceptance/runtime.py`) against an installed production Boaz.
/// Runs only on a throwaway Mac with `BOAZ_ACCEPTANCE_APP` set to that app's path; it attaches to the running app
/// as it is, with no test mode, fixture or relaunch.
final class BoazAcceptanceUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["BOAZ_ACCEPTANCE_APP"], !path.isEmpty else {
            throw XCTSkip("Set BOAZ_ACCEPTANCE_APP to an installed Boaz to run the acceptance steps.")
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
