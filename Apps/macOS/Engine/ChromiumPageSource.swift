#if BOAZ_CHROMIUM
import Foundation

@MainActor
enum ChromiumPageSource {
    static func show(in browser: BrowserState) {
        guard let engine = browser.activeEnginePage,
              let page = engine.adapter as? ChromiumEnginePageAdapter,
              page.state.lifecycle == .active else { return }
        let navigation = page.state.navigationID
        let profile = page.profile
        let url = page.state.url
        let title = page.state.title.isEmpty ? (url?.host() ?? "Page Source") : page.state.title
        Task { [weak browser] in
            do {
                let html = try await ChromiumTextTransfer.read(from: page,
                    body: "return document.documentElement?.outerHTML ?? '';")
                try Task.checkCancellation()
                guard let browser, browser.activeEnginePage === engine,
                      page.profile == profile, page.state.navigationID == navigation,
                      page.state.url == url, page.state.lifecycle == .active else {
                    browser?.model.showToast("The page changed before its source could be shown. Try again.")
                    return
                }
                browser.devTools.sheet = .source(title: title, html: html)
            } catch is CancellationError {
                return
            } catch ChromiumTextTransferError.tooLarge {
                browser?.model.showToast("This page's source exceeds the 4 MiB limit and cannot be shown in full.")
            } catch {
                browser?.model.showToast("The page source could not be read. The page may have changed; please try again.")
            }
        }
    }
}
#endif
