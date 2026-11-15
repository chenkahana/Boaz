import XCTest

/// Minimal check that the UI test contract actually works: the app launches in test mode, seeds the standard
/// fixture, and shows an intact main window. `ScreenTests.swift` covers the rest of the app.
final class SmokeTests: BoazUITestCase {
    func testMainWindowIntact() {
        launch(fixture: "standard")
        assertScreenIntact(mainWindow, name: "browser")
    }
}
