import XCTest

/// Base class for Boaz's UI test suite.
///
/// Launches the app with `-BoazUITest YES` (`UITestMode` in the Mac target): a fresh, local-only store seeded from
/// a JSON fixture in `Fixtures/`, no CloudKit sync, no onboarding unless asked for, no network on launch. Tests
/// never touch the developer's real library.
///
/// Set `BOAZ_UITEST_APP` to the path of a built `.app` (for example a staged Chromium dev build) to run the same
/// suite against it instead of the one this scheme just built.
class BoazUITestCase: XCTestCase {
    enum Appearance: String { case light, dark }

    var app: XCUIApplication!
    private(set) var appearance: Appearance = .light

    /// The app's first window: what most actions target.
    var mainWindow: XCUIElement { app.windows.firstMatch }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    /// Launches the app for a test. `fixture` names a JSON file in `Fixtures/` (without its extension), copied
    /// into the test bundle's resources. `arguments`/`environment` are merged in on top of the test-mode defaults.
    func launch(fixture: String = "standard", appearance: Appearance = .light,
               environment: [String: String] = [:], arguments: [String] = []) {
        self.appearance = appearance

        let application: XCUIApplication
        if let appPath = ProcessInfo.processInfo.environment["BOAZ_UITEST_APP"] {
            application = XCUIApplication(url: URL(fileURLWithPath: appPath))
        } else {
            application = XCUIApplication()
        }
        app = application

        let bundle = Bundle(for: Self.self)
        guard let fixtureURL = bundle.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: fixture, withExtension: "json") else {
            XCTFail("Missing fixture '\(fixture)'; add Tests/BoazUITests/Fixtures/\(fixture).json")
            return
        }

        // `-ApplePersistenceIgnoreState YES`: AppKit's own window-restoration system otherwise tries to reopen
        // whatever this bundle id's windows looked like when IT last quit (a separate mechanism from our own
        // `MacModel.SavedWindow`, which `UITestMode.resetDefaultsIfNeeded()` clears instead).
        var launchArguments = ["-BoazUITest", "YES", "-ApplePersistenceIgnoreState", "YES"]
        // Absence of the key reads as Light; CI runners boot Light by default.
        if appearance == .dark { launchArguments += ["-AppleInterfaceStyle", "Dark"] }
        launchArguments += arguments

        var launchEnvironment = environment
        launchEnvironment["BOAZ_UITEST_FIXTURES"] = fixtureURL.path

        application.launchArguments = launchArguments
        application.launchEnvironment = launchEnvironment
        application.launch()
        _ = mainWindow.waitForExistence(timeout: 10)
    }

    /// Asserts `element` (named `name` in failures and the attached screenshot) actually renders correctly:
    /// hittable, laid out inside its window, every visible control labeled, no overlapping buttons, and clean
    /// under the system accessibility audit.
    func assertScreenIntact(_ element: XCUIElement, name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "\(name) never appeared", file: file, line: line)
        XCTAssertTrue(element.isHittable, "\(name) is not hittable", file: file, line: line)

        let frame = element.frame
        XCTAssertFalse(frame.isEmpty, "\(name) has an empty frame", file: file, line: line)
        // Popovers (the Library panel, the icon picker) are windows of their own that may extend past the main
        // window; measure against whichever popover or window holds the element.
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let holder = (app.popovers.allElementsBoundByIndex + app.windows.allElementsBoundByIndex)
            .first { $0.exists && $0.frame.contains(center) && $0.frame.contains(frame.insetBy(dx: 1, dy: 1)) }
        let containerFrame = (holder ?? mainWindow).frame
        let windowFrame = containerFrame.insetBy(dx: -1, dy: -1)
        XCTAssertTrue(windowFrame.contains(frame),
                      "\(name)'s frame \(frame) falls outside its window \(containerFrame)", file: file, line: line)

        // A scroll view's own content routinely extends past its visible viewport (that's the point of scrolling);
        // XCUITest still reports that off-screen content as `isHittable`, so a row below the fold isn't a real
        // layout bug the way the same frame would be outside a non-scrolling screen. Only requiring these controls
        // to be labeled, not fully on screen, keeps the check meaningful for scrollable content. `XCUIElement`
        // isn't usefully `Hashable`, so membership is keyed by label/identifier/frame instead of the element itself.
        func scrollKey(_ control: XCUIElement) -> String { "\(control.label)|\(control.identifier)|\(control.frame)" }
        let scrolledControls = Set(element.descendants(matching: .scrollView).allElementsBoundByIndex
            .flatMap { scrollView in [XCUIElement.ElementType.button, .staticText, .textField].flatMap { scrollView.descendants(matching: $0).allElementsBoundByIndex } }
            .map(scrollKey))

        var hittableButtons: [XCUIElement] = []
        for kind in [XCUIElement.ElementType.button, .staticText, .textField] {
            for control in element.descendants(matching: kind).allElementsBoundByIndex where control.exists && control.isHittable {
                let hasLabel = !control.label.isEmpty || !control.identifier.isEmpty
                XCTAssertTrue(hasLabel, "A \(kind.rawValue) under \(name) has no label or identifier",
                             file: file, line: line)
                if !scrolledControls.contains(scrollKey(control)) {
                    XCTAssertTrue(windowFrame.contains(control.frame),
                                 "A \(kind.rawValue) under \(name) (\(control.label)) falls outside its window",
                                 file: file, line: line)
                }
                if kind == .button { hittableButtons.append(control) }
            }
        }
        for i in 0..<hittableButtons.count {
            for j in (i + 1)..<hittableButtons.count {
                let a = hittableButtons[i].frame
                let b = hittableButtons[j].frame
                let overlap = a.intersection(b)
                guard !overlap.isEmpty else { continue }
                let smaller = min(a.width * a.height, b.width * b.height)
                guard smaller > 0 else { continue }
                let ratio = (overlap.width * overlap.height) / smaller
                XCTAssertLessThanOrEqual(ratio, 0.5,
                    "Two buttons under \(name) overlap by \(Int(ratio * 100))% (\(hittableButtons[i].label) / \(hittableButtons[j].label))",
                    file: file, line: line)
            }
        }

        do {
            try app.performAccessibilityAudit(
                // `.textClipped`, `.dynamicType` and `.trait` are iOS/tvOS/watchOS-only; macOS adds `.action`
                // and `.parentChild` in their place.
                for: [.elementDetection, .hitRegion, .contrast, .sufficientElementDescription, .action, .parentChild]
            ) { issue in Self.auditIssueIsAllowed(issue) }
        } catch {
            XCTFail("Accessibility audit failed for \(name): \(error)", file: file, line: line)
        }

        // `element`'s own screenshot, not `app.screenshot()`: on macOS the latter captures the whole physical
        // display (every other window on the machine) rather than just this app, which is both the wrong
        // picture and a privacy problem on a developer's own Mac.
        let screenshot = XCTAttachment(screenshot: element.screenshot())
        screenshot.name = "\(name)-\(appearance.rawValue)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    /// Known system-control accessibility-audit false positives. Keep tight; justify every entry here. Confirmed
    /// by inspecting each flagged element's identifier/label/elementType/frame (`XCUIAccessibilityAuditIssue`)
    /// before writing the condition below, not by guessing.
    private static func auditIssueIsAllowed(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        guard let element = issue.element else { return false }
        // Every window's root SwiftUI hosting view is bridged as one unlabeled `.group` the size of the whole
        // window's content: it sits above our own `screen.*`-identified root view, so no modifier we put on our
        // own views can label it. Scoped to the content-sized case so a real, mistakenly unlabeled large group
        // elsewhere in the UI isn't silently allowed.
        if issue.auditType == .sufficientElementDescription, element.elementType == .group,
           element.identifier.isEmpty, element.label.isEmpty,
           element.frame.width > 500, element.frame.height > 400 {
            return true
        }
        // The hidden-titlebar window's traffic-light button cluster is bridged as a small unlabeled `.group`
        // near the top-left corner; the real close/minimize/zoom buttons beneath it (which the window chrome
        // labels) are what VoiceOver actually reaches.
        if issue.auditType == .parentChild, element.elementType == .group,
           element.identifier.isEmpty, element.label.isEmpty,
           element.frame.width <= 20, element.frame.height <= 20 {
            return true
        }
        // The sidebar's "New" menu (Sidebar.swift, `Menu` + `.menuStyle(.button)`) carries an explicit
        // `.accessibilityLabel("New")` and an identifier in source, but on this macOS/Xcode version
        // `.menuStyle(.button)` doesn't bridge the identifier (it inherits its container's) or the missing-action
        // check to AppKit's audited AX node — confirmed by trying the label on the Menu itself, on its label
        // view, and `.accessibilityElement(children: .ignore)` with `.accessibilityAddTraits(.isButton)`, none of
        // which changed what the audit sees. Matched by its (working) label since its identifier isn't its own.
        if issue.auditType == .action, element.elementType == .menuButton, element.label == "New" {
            return true
        }
        return false
    }

    /// Opens Boaz ▸ Settings… and selects the pane titled `tab` ("General", "Privacy", "Sync", "Passwords",
    /// "Sites" or "Shortcuts").
    func openSettings(tab: String) {
        menu("Boaz", "Settings…")
        let settingsWindow = app.windows["Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 10), "Settings never opened")
        let tabButton = settingsWindow.buttons[tab].firstMatch
        XCTAssertTrue(tabButton.waitForExistence(timeout: 5), "No \(tab) tab in Settings")
        tabButton.click()
    }

    /// Clicks a path of menu bar items, e.g. `menu("Tabs", "Pin Tab")`.
    func menu(_ path: String...) {
        guard let first = path.first else { return }
        var element = app.menuBars.menuBarItems[first]
        _ = element.waitForExistence(timeout: 5)
        element.click()
        for item in path.dropFirst() {
            element = app.menuItems[item]
            element.click()
        }
    }

    /// Opens the command bar (⌘T) on the frontmost window.
    func openCommandBar() {
        app.typeKey("t", modifierFlags: .command)
    }
}
