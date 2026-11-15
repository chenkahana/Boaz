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
        // Set either way: AppKit reads anything but "Dark" as Light, and a Mac set to Dark would otherwise run the
        // Light tests dark.
        launchArguments += ["-AppleInterfaceStyle", appearance == .dark ? "Dark" : "Light"]
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
        let holder = (app.popovers.allElementsBoundByIndex + app.sheets.allElementsBoundByIndex + app.windows.allElementsBoundByIndex)
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
                // SwiftUI's `Text` reaches AppKit accessibility as a static text whose words are its value, not its
                // label; a text field without a label still speaks its placeholder.
                let spoken = [control.label, control.identifier, control.value as? String ?? "", control.placeholderValue ?? ""]
                XCTAssertTrue(spoken.contains { !$0.isEmpty },
                             "A \(Self.typeName(kind)) under \(name) at \(control.frame) has no label, value or identifier",
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

        // Every issue the audit raises is reported with the element it's about (type, identifier, label, value,
        // frame): XCTest's own failure only says "Element has no description" with a screenshot.
        // The audit covers the whole app; only issues about elements on this screen count against it, so a window
        // behind a sheet or the Settings window is checked by its own test, not by every test that opens something.
        let issues = IssueLog()
        let screenFrame = frame
        let containerFrames = (app.windows.allElementsBoundByIndex + app.popovers.allElementsBoundByIndex
            + app.sheets.allElementsBoundByIndex).filter(\.exists).map(\.frame)
        do {
            try app.performAccessibilityAudit(
                // `.textClipped`, `.dynamicType` and `.trait` are iOS/tvOS/watchOS-only; macOS adds `.action`
                // and `.parentChild` in their place.
                for: [.elementDetection, .hitRegion, .contrast, .sufficientElementDescription, .action, .parentChild]
            ) { issue in
                if let issueFrame = issue.element?.frame, !issueFrame.isEmpty,
                   !screenFrame.insetBy(dx: -1, dy: -1).intersects(issueFrame) { return true }
                if Self.auditIssueIsAllowed(issue, containerFrames: containerFrames) { return true }
                issues.lines.append(Self.describe(issue))
                return true
            }
        } catch {
            XCTFail("Accessibility audit failed for \(name): \(error)", file: file, line: line)
        }
        for issue in issues.lines { XCTFail("Accessibility audit, \(name): \(issue)", file: file, line: line) }

        // `element`'s own screenshot, not `app.screenshot()`: on macOS the latter captures the whole physical
        // display (every other window on the machine) rather than just this app, which is both the wrong
        // picture and a privacy problem on a developer's own Mac.
        let screenshot = XCTAttachment(screenshot: element.screenshot())
        screenshot.name = "\(name)-\(appearance.rawValue)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private static func typeName(_ type: XCUIElement.ElementType) -> String {
        switch type {
        case .button: "button"
        case .staticText: "static text"
        case .textField: "text field"
        case .group: "group"
        case .image: "image"
        case .other: "other"
        case .menuButton: "menu button"
        default: "element type \(type.rawValue)"
        }
    }

    private static func describe(_ issue: XCUIAccessibilityAuditIssue) -> String {
        var text = issue.compactDescription
        if let element = issue.element {
            text += " — \(typeName(element.elementType)) id '\(element.identifier)' label '\(element.label)'"
            if let value = element.value as? String, !value.isEmpty { text += " value '\(value.prefix(60))'" }
            text += " at \(element.frame)"
        }
        return text
    }

    /// Known system-control accessibility-audit false positives. Keep tight; justify every entry here. Confirmed
    /// by inspecting each flagged element's identifier/label/elementType/frame (`XCUIAccessibilityAuditIssue`)
    /// before writing the condition below, not by guessing.
    private static func auditIssueIsAllowed(_ issue: XCUIAccessibilityAuditIssue, containerFrames: [CGRect]) -> Bool {
        guard let element = issue.element else { return false }
        // Every window, sheet and popover's root SwiftUI hosting view, and the popover itself, are bridged as an
        // unlabeled element exactly the size of that window: they sit above our own `screen.*`-identified root view,
        // so no modifier we put on our own views can label them. Matched by frame, so an unlabeled group of our own
        // anywhere else still fails.
        if issue.auditType == .sufficientElementDescription, element.identifier.isEmpty, element.label.isEmpty,
           [.group, .popover, .sheet].contains(element.elementType),
           containerFrames.contains(where: { abs($0.minX - element.frame.minX) <= 1 && abs($0.minY - element.frame.minY) <= 1
               && abs($0.width - element.frame.width) <= 1 && abs($0.height - element.frame.height) <= 1 }) {
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
        // The same holds for every `.menuStyle(.button)` menu (the Library's Filter as well as "New"): a menu button's
        // action is AXShowMenu, which it has, and XCUITest itself opens them with a click.
        if issue.auditType == .action, element.elementType == .menuButton, !element.label.isEmpty {
            return true
        }
        return false
    }

    /// Opens Boaz ▸ Settings… and selects the pane titled `tab` ("General", "App Icon", "Privacy", "Sync",
    /// "Passwords", "Accounts", "Sites" or "Shortcuts"), returning that pane (`screen.settings.<pane>`).
    ///
    /// The Settings window is found by its toolbar, not its title: a tabbed Settings scene titles its window after
    /// the selected pane ("General"), never "Settings".
    @discardableResult
    func openSettings(tab: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        menu("Boaz", "Settings…")
        let tabButton = app.toolbars.buttons[tab].firstMatch
        XCTAssertTrue(tabButton.waitForExistence(timeout: 10), "Settings never opened, or has no \(tab) pane",
                      file: file, line: line)
        // The window opens on the last pane; a click while it's still appearing can be lost, so wait for a pane first
        // and click again if the one asked for doesn't come up.
        _ = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'screen.settings.'"))
            .firstMatch.waitForExistence(timeout: 5)
        let id = Self.settingsPaneIDs[tab] ?? tab
        let pane = element("screen.settings.\(id)")
        for _ in 0..<3 where !pane.exists {
            tabButton.click()
            _ = pane.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(pane.exists, "The \(tab) pane never appeared", file: file, line: line)
        return pane
    }

    private static let settingsPaneIDs = ["General": "general", "App Icon": "appIcon", "Privacy": "privacy",
                                          "Sync": "sync", "Passwords": "passwords", "Accounts": "accounts",
                                          "Sites": "sites", "Shortcuts": "shortcuts"]

    /// The first element anywhere in the app with accessibility identifier `id` (the `screen.*` convention).
    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    /// The main window's sidebar (`sidebar.root`).
    var sidebar: XCUIElement { mainWindow.descendants(matching: .any)["sidebar.root"].firstMatch }

    /// Waits for `element` to go away.
    @discardableResult
    func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
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

/// Collects audit issues from the audit's handler, which XCTest calls synchronously during the audit.
private final class IssueLog: @unchecked Sendable {
    var lines: [String] = []
}
