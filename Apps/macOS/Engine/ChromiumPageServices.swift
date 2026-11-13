#if BOAZ_CHROMIUM
import Foundation

@MainActor
enum ChromiumPageServices {
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
