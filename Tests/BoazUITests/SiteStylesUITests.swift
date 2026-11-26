import Network
import XCTest

/// Site Styles end to end on a page this test serves on the loopback address (styles need an http(s) host):
/// save from View › Edit Site Style…, see it after a reload, edit it live, delete it from Settings.
final class SiteStylesUITests: BoazUITestCase {
    private var server: LoopbackPage?

    override func tearDownWithError() throws {
        server?.stop()
        server = nil
        try super.tearDownWithError()
    }

    func testSaveApplyEditDelete() throws {
        let server = try LoopbackPage(html: "<!doctype html><title>Styled</title><h1>Site Styles Fixture</h1>")
        self.server = server
        launch(fixture: "standard")
        XCTAssertTrue(waitForSpace("Work"), "The standard fixture never seeded")

        openCommandBar()
        XCTAssertTrue(element("screen.commandBar").waitForExistence(timeout: 5))
        app.typeText("http://127.0.0.1:\(server.port)/\r")
        let page = mainWindow.webViews.firstMatch
        XCTAssertTrue(page.staticTexts["Site Styles Fixture"].waitForExistence(timeout: 15), "The fixture page didn't load")

        // Save: the preview shows as it's typed, and stays after Save.
        let editor = openEditor()
        let css = editor.textViews["siteStyle.css"].firstMatch
        XCTAssertTrue(css.waitForExistence(timeout: 5), "The editor has no CSS field")
        css.click()
        css.typeText("body::before{content:\"BOOST-ON\"}")
        XCTAssertTrue(page.staticTexts["BOOST-ON"].waitForExistence(timeout: 5), "The draft didn't preview on the page")
        editor.buttons["Save"].click()
        XCTAssertTrue(waitForDisappearance(editor), "Save didn't close the editor")

        // Apply on load.
        menu("View", "Reload Page")
        XCTAssertTrue(page.staticTexts["Site Styles Fixture"].waitForExistence(timeout: 15))
        XCTAssertTrue(page.staticTexts["BOOST-ON"].waitForExistence(timeout: 5), "The saved style didn't apply on reload")

        // Edit: the change shows live, without a reload.
        let again = openEditor()
        let field = again.textViews["siteStyle.css"].firstMatch
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("body::before{content:\"BOOST-2\"}")
        XCTAssertTrue(page.staticTexts["BOOST-2"].waitForExistence(timeout: 5), "The edit didn't show live")
        XCTAssertFalse(page.staticTexts["BOOST-ON"].exists)
        again.buttons["Save"].click()
        XCTAssertTrue(waitForDisappearance(again), "Save didn't close the editor")

        // Delete from Settings: the row goes, and so does the style on the open page.
        let pane = openSettings(tab: "Site Styles")
        XCTAssertTrue(pane.staticTexts["127.0.0.1"].waitForExistence(timeout: 5), "Settings doesn't list the style")
        pane.buttons["siteStyles.delete.127.0.0.1"].click()
        let confirm = app.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "Delete didn't ask to confirm")
        confirm.click()
        XCTAssertTrue(waitForDisappearance(pane.staticTexts["127.0.0.1"]), "The deleted style is still listed")
        XCTAssertTrue(pane.staticTexts["No site styles"].waitForExistence(timeout: 5), "No empty state after delete")
        XCTAssertTrue(waitForDisappearance(page.staticTexts["BOOST-2"]), "Deleting didn't remove the style from the page")
    }

    private func openEditor(file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        mainWindow.click()
        menu("View", "Edit Site Style…")
        let editor = element("screen.siteStyleEditor")
        XCTAssertTrue(editor.waitForExistence(timeout: 5), "View › Edit Site Style… didn't open the editor",
                      file: file, line: line)
        return editor
    }
}

/// One HTML page on 127.0.0.1 at a free port, for every path, until stopped.
private final class LoopbackPage: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "SiteStylesUITests.server")
    private(set) var port: UInt16 = 0

    init(html: String) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        let body = Data(html.utf8)
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\n"
            + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
        let response = Data(head.utf8) + body
        listener.newConnectionHandler = { [queue] connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { _, _, _, _ in
                connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready, .failed, .cancelled: ready.signal()
            default: break
            }
        }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        guard let port = listener.port?.rawValue, port != 0 else {
            listener.cancel()
            throw URLError(.cannotConnectToHost)
        }
        self.port = port
    }

    func stop() { listener.cancel() }
}
