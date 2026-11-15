import XCTest

/// Live folders against canned GitHub answers (`Fixtures/github-pulls.json`, read through `BOAZ_GITHUB_FIXTURE`).
/// `BOAZ_GITHUB_TOKEN` signs the run in without touching the Keychain.
final class LiveFolderUITests: BoazUITestCase {
    private func launchSignedIn(signedIn: Bool = true) {
        guard let fixture = Bundle(for: Self.self).url(forResource: "github-pulls", withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle(for: Self.self).url(forResource: "github-pulls", withExtension: "json") else {
            XCTFail("Missing Fixtures/github-pulls.json")
            return
        }
        var environment = ["BOAZ_GITHUB_FIXTURE": fixture.path]
        if signedIn { environment["BOAZ_GITHUB_TOKEN"] = "fixture-token" }
        launch(fixture: "standard", environment: environment)
    }

    /// The space's menu (right-click its title in the sidebar, "Work" in the standard fixture) ▸ New Live Folder ▸
    /// GitHub Pull Requests. Scoped to the sidebar: an empty window also shows the space's name, big, in the content area.
    private func newPullRequestsFolder() {
        XCTAssertTrue(waitForSpace("Work"), "The Work space never appeared in the sidebar")
        spaceHeader.rightClick()
        app.menuItems["New Live Folder"].firstMatch.hover()
        app.menuItems["GitHub Pull Requests"].firstMatch.click()
    }

    private var folder: XCUIElement { mainWindow.descendants(matching: .any)["sidebar.folder.Pull Requests"].firstMatch }

    func testPullRequestsFolderListsPullRequestsWithBadges() {
        launchSignedIn()
        newPullRequestsFolder()
        XCTAssertTrue(folder.waitForExistence(timeout: 5), "The Pull Requests folder never appeared")

        // Created by Me + Review Requests, with #116 (in both) listed once.
        let rows = ["Live folders for GitHub pull requests", "Docker: keep pnpm store between builds",
                    "Exclude testKit from the bundle", "Draft: try a new cache"]
        for title in rows {
            XCTAssertTrue(mainWindow.buttons[title].waitForExistence(timeout: 10), "\(title) isn't listed")
        }
        XCTAssertEqual(mainWindow.buttons.matching(NSPredicate(format: "label == %@", "Live folders for GitHub pull requests")).count, 1)
        XCTAssertFalse(mainWindow.buttons["chore(knip): drop unused exports"].exists, "Team Review Requests is off by default")

        let badges = mainWindow.descendants(matching: .any)
        XCTAssertTrue(badges["sidebar.livePull.checks.success"].firstMatch.exists)
        XCTAssertTrue(badges["sidebar.livePull.checks.failure"].firstMatch.exists)
        XCTAssertTrue(badges["sidebar.livePull.checks.pending"].firstMatch.exists)
        XCTAssertTrue(badges["sidebar.livePull.checks.none"].firstMatch.exists)
        assertScreenIntact(mainWindow, name: "live-folder")
    }

    func testFolderMenuTogglesAFilter() {
        launchSignedIn()
        newPullRequestsFolder()
        XCTAssertTrue(folder.waitForExistence(timeout: 5))

        folder.rightClick()
        for item in ["Pull Requests", "Move to", "Copy All Links", "Change Icon…", "Rename…", "Delete Live Folder"] {
            XCTAssertTrue(app.menuItems[item].firstMatch.waitForExistence(timeout: 3), "\(item) is missing from the folder menu")
        }
        app.menuItems["Pull Requests"].firstMatch.hover()
        for item in ["Refresh", "Created by Me", "Review Requests", "Team Review Requests", "Assigned to Me", "Mentioned",
                     "Repositories", "Single Sign-On", "Sign Out of GitHub"] {
            XCTAssertTrue(app.menuItems[item].firstMatch.waitForExistence(timeout: 3), "\(item) is missing from Pull Requests")
        }
        // `mainWindow`'s own screenshot, not `app.screenshot()`: on macOS the latter captures the whole physical
        // display (every other window on the machine), not just this app.
        let screenshot = XCTAttachment(screenshot: mainWindow.screenshot())
        screenshot.name = "live-folder-menu"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.menuItems["Team Review Requests"].firstMatch.click()
        XCTAssertTrue(mainWindow.buttons["chore(knip): drop unused exports"].waitForExistence(timeout: 10),
                      "Turning on Team Review Requests didn't list the team's pull request")
    }

    func testChangeIconOpensThePicker() {
        launchSignedIn()
        newPullRequestsFolder()
        XCTAssertTrue(folder.waitForExistence(timeout: 5))
        folder.rightClick()
        app.menuItems["Change Icon…"].firstMatch.click()
        let picker = app.descendants(matching: .any)["screen.iconPicker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        assertScreenIntact(picker, name: "icon-picker")
    }

    func testSignedOutCreationAsksToSignIn() {
        launchSignedIn(signedIn: false)
        newPullRequestsFolder()
        let sheet = app.descendants(matching: .any)["screen.githubSignIn"].firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5), "No sign-in sheet")
        XCTAssertTrue(app.staticTexts["BOAZ-TEST"].waitForExistence(timeout: 5), "The fixture's device code isn't shown")
        assertScreenIntact(sheet, name: "github-sign-in")
        // The fixture's device flow succeeds by itself (after 15 s) and makes the folder.
        XCTAssertTrue(folder.waitForExistence(timeout: 25))
    }

    func testAccountsSettingsShowsTheAccount() {
        launchSignedIn()
        let pane = openSettings(tab: "Accounts")
        XCTAssertTrue(pane.buttons["Sign Out"].firstMatch.waitForExistence(timeout: 5))
        assertScreenIntact(pane, name: "settings-accounts")
    }
}
