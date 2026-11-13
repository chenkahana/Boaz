#if BOAZ_CHROMIUM
import Foundation

extension ChromiumEnginePageAdapter {
    func reloadFromOrigin() throws {
        guard state.lifecycle == .active else { throw EnginePageError.closed }
        guard let reload = api.reload_from_origin else { throw EnginePageError.incompatibleBridge }
        try check(reload(handle))
    }
}

@MainActor
enum ChromiumCache {
    private static var pending: Set<EngineProfileIdentity> = []
    static func isPending(for profile: EngineProfileIdentity?) -> Bool {
        profile.map { pending.contains($0) } ?? false
    }
    static func clear(in browser: BrowserState) {
        guard let engine = browser.activeEnginePage,
              let page = engine.adapter as? ChromiumEnginePageAdapter,
              page.state.lifecycle == .active, !pending.contains(page.profile) else { return }
        let profile = page.profile
        let navigation = page.state.navigationID
        let url = page.state.url
        pending.insert(profile)
        Task { [weak browser] in
            defer { pending.remove(profile) }
            do {
                try await ChromiumRuntime.clearCaches(for: profile)
                guard !Task.isCancelled, let browser else { return }
                guard browser.activeEnginePage === engine, page.profile == profile,
                      page.state.navigationID == navigation, page.state.url == url,
                      page.state.lifecycle == .active else {
                    browser.model.showToast("Caches emptied. Cookies and website storage were kept.")
                    return
                }
                do {
                    try page.reloadFromOrigin()
                    browser.model.showToast("Caches emptied. Cookies and website storage were kept.")
                } catch {
                    browser.model.showToast("Caches emptied, but the page could not be reloaded.")
                }
            } catch {
                browser?.model.showToast("Caches could not be fully emptied. Please try again.")
            }
        }
    }
}
#endif
