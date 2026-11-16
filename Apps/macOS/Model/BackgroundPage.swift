import Foundation
#if !BOAZ_CHROMIUM
import WebKit
#endif

/// A page no window shows, one per profile, for app work that needs that profile's own browser session (live folders
/// reading github.com as the signed-in user). It runs trusted app code in a document at a site's origin, with the
/// profile's cookies, and answers what it returns.
///
/// Chromium keeps it in a window that's never ordered in (`ChromiumBackgroundWindow`); WebKit in a `WebPage` on the
/// profile's website data store.
@MainActor
enum BackgroundPage {
    /// What the function threw.
    struct Failure: LocalizedError {
        let errorDescription: String?
    }

    /// Runs `function`, trusted app source of the form `async (value) => string`, on `json` parsed, in `profileID`'s
    /// page at `url`.
    static func run(_ function: String, arguments json: String, at url: URL, profileID: String) async throws -> String {
        #if BOAZ_CHROMIUM
        return try await chromiumBackgroundWindow(profileID: profileID, at: url).run(function, arguments: json, at: url)
        #else
        let page = try await page(for: profileID, at: url)
        do {
            let value = try await page.callJavaScript("return await (\(function))(JSON.parse(json));",
                                                      arguments: ["json": json], contentWorld: .defaultClient)
            guard let text = value as? String else { throw Failure(errorDescription: "The page answered nothing Boaz could read.") }
            return text
        } catch let error as Failure {
            throw error
        } catch {
            pages[profileID] = nil
            throw Failure(errorDescription: (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
                          ?? error.localizedDescription)
        }
        #endif
    }

    /// Closes the pages of every profile but `profileIDs`.
    static func keep(only profileIDs: Set<String>) {
        #if BOAZ_CHROMIUM
        closeChromiumBackgroundWindows(keeping: profileIDs)
        #else
        pages = pages.filter { profileIDs.contains($0.key) }
        #endif
    }

    #if !BOAZ_CHROMIUM
    private static var pages: [String: WebPage] = [:]

    private static func page(for profileID: String, at url: URL) async throws -> WebPage {
        if let page = pages[profileID], !page.isLoading, page.url?.host() == url.host() { return page }
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = MacModel.shared.dataStore(for: profileID)
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        let page = WebPage(configuration: configuration)
        for try await event in page.load(URLRequest(url: url)) where event == .finished { break }
        guard page.url?.host() == url.host() else { throw Failure(errorDescription: "\(url.host() ?? "The site") didn't open.") }
        pages[profileID] = page
        return page
    }
    #endif
}
