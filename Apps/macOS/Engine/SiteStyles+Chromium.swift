#if BOAZ_CHROMIUM
import BoazKit
import Foundation

/// Chromium pages take their site style through the host's trusted execution: Boaz's isolated world, the primary
/// main frame of an http(s) document only, the document checked against its browser-side origin. No DevTools
/// client is attached and no extension surface is touched.
extension SiteStyles {
    static let chromiumFunction = "({css}) => (\(keeper))(css)"

    /// Every page event: a page that has committed a new document gets its host's style, while it is still loading.
    func pageChanged(_ page: ChromiumEnginePageAdapter) {
        let id = ObjectIdentifier(page)
        let state = page.state
        guard state.lifecycle == .active else {
            if state.lifecycle == .closed {
                chromiumPages.remove(page)
                chromiumDocuments[id] = nil
            }
            return
        }
        chromiumPages.add(page)
        guard chromiumDocuments[id] != state.navigationID, let host = Self.hostKey(state.url),
              !effectiveCSS(page: id, profileID: page.profile.id, host: host).isEmpty else { return }
        let navigation = state.navigationID
        chromiumDocuments[id] = navigation
        Task {
            // A document that wasn't ready yet is tried again on the page's next event.
            if await apply(on: page) == nil, chromiumDocuments[id] == navigation { chromiumDocuments[id] = nil }
        }
    }

    /// Applies what the page's own document origin calls for, so a page that moved on meanwhile can't take another
    /// host's CSS. Nil when the page has no document to style.
    @discardableResult
    func apply(on page: ChromiumEnginePageAdapter) async -> Outcome? {
        guard let target = try? page.captureTrustedDocument() else { return nil }
        guard let host = Self.hostKey(target.origin) else {
            target.release()
            return nil
        }
        let css = effectiveCSS(page: ObjectIdentifier(page), profileID: page.profile.id, host: host)
        guard let value = try? await page.executeTrusted(on: target, function: Self.chromiumFunction,
                                                         arguments: ["css": .string(css)]),
              case .string(let outcome) = value else { return nil }
        return Outcome(rawValue: outcome)
    }

    func refreshChromium(profileID: String, host: String) {
        for page in chromiumPages.allObjects where page.profile.id == profileID && page.state.lifecycle == .active
            && Self.hostKey(page.state.url) == host {
            chromiumDocuments[ObjectIdentifier(page)] = page.state.navigationID
            Task { await apply(on: page) }
        }
    }
}
#endif
