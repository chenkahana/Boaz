import XCTest

/// Live folders against canned github.com answers (`Fixtures/github-pulls.json`, read through `BOAZ_GITHUB_FIXTURE`).
/// `BOAZ_GITHUB_SIGNED_OUT` answers as if no one is signed in to github.com.
final class LiveFolderUITests: BoazUITestCase {
    private func launchSignedIn(signedIn: Bool = true) {
        guard let fixture = Bundle(for: Self.self).url(forResource: "github-pulls", withExtension: "json", subdirectory: "Fixtures")
            ?? Bundle(for: Self.self).url(forResource: "github-pulls", withExtension: "json") else {
            XCTFail("Missing Fixtures/github-pulls.json")
            return
        }
        var environment = ["BOAZ_GITHUB_FIXTURE": fixture.path]
        if !signedIn { environment["BOAZ_GITHUB_SIGNED_OUT"] = "1" }
        // Live folders are off per profile until turned on; the fixture's only profile is "fixture-default".
        launch(fixture: "standard", environment: environment, arguments: ["-liveFoldersEnabled.fixture-default", "YES"])
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
                     "Repositories", "Single Sign-On"] {
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

    func testSignedOutFolderAsksToSignIn() {
        launchSignedIn(signedIn: false)
        newPullRequestsFolder()
        XCTAssertTrue(folder.waitForExistence(timeout: 5), "The Pull Requests folder never appeared")
        folder.rightClick()
        app.menuItems["Pull Requests"].firstMatch.hover()
        XCTAssertTrue(app.menuItems["Sign in to GitHub"].firstMatch.waitForExistence(timeout: 10),
                      "The folder's menu doesn't offer to sign in to GitHub")
    }

    func testAccountsSettingsListsProfiles() {
        launchSignedIn()
        let pane = openSettings(tab: "Accounts")
        XCTAssertTrue(pane.staticTexts["Live Folders"].firstMatch.waitForExistence(timeout: 5))
        assertScreenIntact(pane, name: "settings-accounts")
    }
}
