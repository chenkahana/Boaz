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
        // `UITestMode.applyAppearanceIfNeeded()`: either appearance on any Mac, a Dark one included.
        launchArguments += ["-BoazUITestAppearance", appearance.rawValue]
        launchArguments += arguments

        var launchEnvironment = environment
        launchEnvironment["BOAZ_UITEST_FIXTURES"] = fixtureURL.path
        // A Chromium build keeps its browser profile under the home folder; never let a test reach the real one.
        if let appPath = ProcessInfo.processInfo.environment["BOAZ_UITEST_APP"],
           FileManager.default.fileExists(atPath: appPath + "/Contents/Frameworks/Chromium Framework.framework"),
           launchEnvironment["CFFIXED_USER_HOME"] == nil {
            let home = FileManager.default.temporaryDirectory.appendingPathComponent("BoazUITest-\(UUID().uuidString)").path
            launchEnvironment["CFFIXED_USER_HOME"] = home
            launchEnvironment["HOME"] = home
        }

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
        // layout bug the way the same frame would be outside a non-scrolling screen. Such controls must be labeled,
        // not on screen, and only their visible part counts for overlap. `XCUIElement` isn't usefully `Hashable`,
        // so membership is keyed by type and frame instead of the element itself.
        func key(_ control: XCUIElement) -> String { "\(control.elementType.rawValue)|\(control.frame)" }
        var scrollViewFrames: [String: CGRect] = [:]
        for scrollView in element.descendants(matching: .scrollView).allElementsBoundByIndex where scrollView.exists {
            let viewport = scrollView.frame
            for kind in [XCUIElement.ElementType.button, .staticText, .textField] {
                for control in scrollView.descendants(matching: kind).allElementsBoundByIndex {
                    scrollViewFrames[key(control)] = viewport
                }
            }
        }
        // A page's own content is the site's, not Boaz's UI: it's left out of these checks and the audit.
        let webContent = Set(app.windows.webViews.allElementsBoundByIndex.flatMap { webView in
            [webView] + webView.descendants(matching: .any).allElementsBoundByIndex
        }.map(key))

        var hittableButtons: [(label: String, frame: CGRect)] = []
        for kind in [XCUIElement.ElementType.button, .staticText, .textField] {
            for control in element.descendants(matching: kind).allElementsBoundByIndex where control.exists && control.isHittable {
                let controlKey = key(control)
                guard !webContent.contains(controlKey) else { continue }
                // SwiftUI's `Text` reaches AppKit accessibility as a static text whose words are its value, not its
                // label; a text field without a label still speaks its placeholder.
                let spoken = [control.label, control.identifier, control.value as? String ?? "", control.placeholderValue ?? ""]
                XCTAssertTrue(spoken.contains { !$0.isEmpty },
                             "A \(Self.typeName(kind)) under \(name) at \(control.frame) has no label, value or identifier",
                             file: file, line: line)
                let viewport = scrollViewFrames[controlKey]
                if viewport == nil {
                    XCTAssertTrue(windowFrame.contains(control.frame),
                                 "A \(Self.typeName(kind)) under \(name) (\(control.label)) falls outside its window",
                                 file: file, line: line)
                }
                let visible = viewport.map { control.frame.intersection($0) } ?? control.frame
                if kind == .button, !visible.isEmpty { hittableButtons.append((control.label, visible)) }
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
        let context = AuditContext(
            containerFrames: (app.windows.allElementsBoundByIndex + app.popovers.allElementsBoundByIndex
                + app.sheets.allElementsBoundByIndex).filter { $0.exists }.map { $0.frame },
            listFrames: app.windows.outlines.allElementsBoundByIndex.filter { $0.exists }.map { $0.frame })
        do {
            try app.performAccessibilityAudit(
                // `.textClipped`, `.dynamicType` and `.trait` are iOS/tvOS/watchOS-only; macOS adds `.action`
                // and `.parentChild` in their place. `.contrast` samples the screen and flags system-colored text
                // (`.secondary` footnotes, a Form's own row labels) differently from run to run, so it isn't run.
                for: [.elementDetection, .hitRegion, .sufficientElementDescription, .action, .parentChild]
            ) { issue in
                if let element = issue.element {
                    let issueFrame = element.frame
                    if !issueFrame.isEmpty, !screenFrame.insetBy(dx: -1, dy: -1).intersects(issueFrame) { return true }
                    if element.elementType == .webView || webContent.contains(key(element)) { return true }
                }
                if Self.auditIssueIsAllowed(issue, context) { return true }
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
    private struct AuditContext {
        /// Every window, popover and sheet.
        let containerFrames: [CGRect]
        /// Every SwiftUI `List` (an outline).
        let listFrames: [CGRect]
    }

    private static func auditIssueIsAllowed(_ issue: XCUIAccessibilityAuditIssue, _ context: AuditContext) -> Bool {
        // A parent/child mismatch the audit can't attach to any element: AppKit's shared field editor, which sits in
        // whichever text field is being edited (the command bar, the find bar, a sheet's field), not one of our views.
        guard let element = issue.element else { return issue.auditType == .parentChild }
        let containerFrames = context.containerFrames
        // AppKit's own views (`_NS:` identifiers): an NSAlert's title in a confirmation dialog, the text finder's bar.
        // And AppKit's tooltip, up when the pointer happens to rest on a control (`.help`), which it shows unlabeled.
        if element.identifier.hasPrefix("_NS:") || element.elementType == .helpTag,
           issue.auditType == .sufficientElementDescription {
            return true
        }
        // A SwiftUI `List` section header is bridged as an unlabeled row group around the header's own (labeled)
        // text, whose parent doesn't list it as a child; no modifier on the header reaches that group.
        if [.parentChild, .sufficientElementDescription].contains(issue.auditType), element.elementType == .group,
           element.identifier.isEmpty, element.label.isEmpty, element.frame.height <= 32,
           context.listFrames.contains(where: { $0.insetBy(dx: -1, dy: -1).contains(element.frame) }) {
            return true
        }
        // A `Picker` is an NSPopUpButton, whose action is AXShowMenu (XCUITest opens it with a click), not AXPress.
        if issue.auditType == .action, element.elementType == .popUpButton { return true }
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
        // A `Menu` with `.menuStyle(.button)` (the sidebar's New, the Library's Filter, Responsive Design's device
        // menu) is a menu button whose action is AXShowMenu, which it has; the audit asks for AXPress. Tried on "New":
        // a label on the Menu or its label view, and `.accessibilityElement(children: .ignore)` with `.isButton`,
        // none of which changed what the audit sees.
        if issue.auditType == .action, element.elementType == .menuButton { return true }
        return false
    }

    /// Opens Boaz ▸ Settings… and selects the pane titled `tab` ("General", "Theme", "Privacy",
    /// "Accounts & Sync", "Passwords", "Sites" or "Shortcuts"), returning that pane (`screen.settings.<pane>`).
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

    private static let settingsPaneIDs = ["General": "general", "Theme": "theme", "Privacy": "privacy",
                                          "Accounts & Sync": "accountsAndSync", "Passwords": "passwords",
                                          "Sites": "sites", "Shortcuts": "shortcuts"]

    /// The first element anywhere in the app with accessibility identifier `id` (the `screen.*` convention).
    /// Searches the windows (sheets and popovers are in them), not the menu bar, which is most of the app's tree.
    func element(_ id: String) -> XCUIElement { app.windows.descendants(matching: .any)[id].firstMatch }

    /// The current space's title row in the sidebar; its label is the space's name.
    var spaceHeader: XCUIElement { sidebar.descendants(matching: .any)["sidebar.spaceHeader"].firstMatch }

    /// Waits until the sidebar shows the space named `title`.
    @discardableResult
    func waitForSpace(_ title: String, timeout: TimeInterval = 10) -> Bool {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true AND label == %@", title),
                                              object: spaceHeader)
        return XCTWaiter().wait(for: [shown], timeout: timeout) == .completed
    }

    /// The main window's sidebar (`sidebar.root`).
    var sidebar: XCUIElement { mainWindow.descendants(matching: .any)["sidebar.root"].firstMatch }

    /// Waits for `element` to go away.
    @discardableResult
    func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    /// Clicks a path of menu bar items, e.g. `menu("Tabs", "Pin Tab")`. Each item is looked up in the one before
    /// it, so a title another menu also has ("New Folder", "Restore") can't send the click elsewhere.
    func menu(_ path: String...) {
        guard let first = path.first else { return }
        var element = app.menuBars.menuBarItems[first]
        _ = element.waitForExistence(timeout: 5)
        element.click()
        for item in path.dropFirst() {
            element = element.menuItems[item].firstMatch
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
