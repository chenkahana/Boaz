import Foundation
import WebKit

extension PageState {
    // MARK: Script

    private static let world = WKContentWorld.world(name: "boaz-page-state")
    private static let messageName = "boazPageState"

    /// Follows the page's scrolling, reporting where it settles to `onSettle`.
    static func install(in configuration: inout WebPage.Configuration, onSettle: @escaping (PageState) -> Void) {
        configuration.userContentController.addUserScript(
            WKUserScript(source: trackingScript(report: "window.webkit.messageHandlers.boazPageState.postMessage(state);"), injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
        configuration.userContentController.add(Messages(onSettle: onSettle), contentWorld: world, name: messageName)
    }

    /// Where `page` is now; nil when it can't say (no document yet, or it is still going back to its place).
    static func read(_ page: WebPage) async -> PageState? {
        guard let json = try? await page.callJavaScript("return window.__boazPageState?.read() ?? null;",
                                                        contentWorld: world) as? String,
              let place = Place(json: json) else { return nil }
        return PageState(place: place, savedAt: .now)
    }

    /// Puts the page back as its content arrives. Returns once it is there, after 8 seconds, or as soon as the user
    /// scrolls, taps or types.
    func restore(on page: WebPage) async {
        guard let data = try? JSONEncoder().encode(place), let json = String(data: data, encoding: .utf8) else { return }
        _ = try? await page.callJavaScript("return window.__boazPageState?.restore(JSON.parse(place));",
                                           arguments: ["place": json], contentWorld: Self.world)
    }

    /// Takes a page that is showing again back to where it was last read on screen: laid out off screen at another
    /// size, it moved (a chat at its end comes back halfway up). Returns once it is there, or when there is nothing to
    /// go back to; the page does this on its own as it shows, and this only says when it is done.
    static func returnToPlace(_ page: WebPage) async {
        _ = try? await page.callJavaScript("return window.__boazPageState?.returnToPlace() ?? null;", contentWorld: world)
    }

    /// Receives the script's readings once scrolling settles.
    private final class Messages: NSObject, WKScriptMessageHandler {
        private let onSettle: (PageState) -> Void

        init(onSettle: @escaping (PageState) -> Void) { self.onSettle = onSettle }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let json = message.body as? String, let place = Place(json: json) else { return }
            onSettle(PageState(place: place, savedAt: .now))
        }
    }

}
