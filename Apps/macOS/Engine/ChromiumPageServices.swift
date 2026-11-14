#if BOAZ_CHROMIUM
import Foundation

@MainActor
enum ChromiumPageServices {
    static func prepareScroll(on page: ChromiumEnginePageAdapter, restoring saved: PageState?) async throws {
        let navigation = page.state.navigationID
        let url = page.state.url
        try await PageState.install(on: page)
        guard !Task.isCancelled, page.state.navigationID == navigation, page.state.url == url else {
            throw ChromiumTrustedScriptError.identityMismatch
        }
        if let saved, saved.url == url { try await saved.beginRestore(on: page) }
    }

    static func captureScroll(from page: ChromiumEnginePageAdapter) async -> PageState? {
        let navigation = page.state.navigationID
        let url = page.state.url
        guard page.state.lifecycle == .active, !page.state.isLoading,
              page.state.loadFailure == nil else { return nil }
        // Hidden pages may already have changed layout; prefer the last on-screen reading.
        let function = """
            () => document.visibilityState === 'visible'
                ? (window.__boazPageState?.read() ?? null)
                : (window.__boazLatestPageState ?? null)
            """
        guard let value = try? await page.executeTrusted(function: function, arguments: [:]),
              !Task.isCancelled, page.state.lifecycle == .active, !page.state.isLoading,
              page.state.navigationID == navigation, page.state.url == url,
              case .string(let json) = value, let place = PageState.Place(json: json),
              place.url == url else { return nil }
        return PageState(place: place, savedAt: .now)
    }

    static func learnFavicon(from page: ChromiumEnginePageAdapter) async {
        let original = page.state
        guard !page.profile.isPrivate, original.lifecycle == .active,
              !original.isLoading, let pageURL = original.url else { return }
        func unchanged() -> Bool {
            !Task.isCancelled && page.state.lifecycle == .active && !page.state.isLoading &&
                page.state.navigationID == original.navigationID && page.state.url == pageURL
        }
        do {
            try await Task.sleep(for: .milliseconds(150))
            guard unchanged() else { return }
            let value = try await page.executeTrusted(
                function: "function() {\n" + Favicons.discoveryScript + "\n}", arguments: [:])
            guard unchanged(), case .string(let href) = value,
                  let iconURL = URL(string: href, relativeTo: pageURL)?.absoluteURL else { return }
            Favicons.shared.learn(iconURL: iconURL, forPageAt: pageURL, isPrivate: false)
        } catch {
            // Discovery is optional; navigation and close invalidate its result.
        }
    }
}
#endif
