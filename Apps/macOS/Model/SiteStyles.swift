import BoazKit
import Foundation
import Observation
import WebKit

/// Site Styles: the user's own CSS for a site, applied every time it loads. Saved per profile and exact host in
/// UserDefaults (`siteStyles.v1`), never in the library, so it never syncs. The CSS reaches only the page's own
/// document, as one `<style>` element a script in Boaz's own isolated world keeps in `<head>`; the browser chrome
/// is native and never reads it.
@MainActor @Observable
final class SiteStyles {
    static let shared = SiteStyles()
    static let defaultsKey = "siteStyles.v1"
    /// WebKit pages run the style keeper here, out of the page's reach.
    static let world = WKContentWorld.world(name: "BoazSiteStyles")

    /// What the keeper reports after it ran: the style is in place, the page's CSP refused it, it was removed, or
    /// the document has no element to hold it yet.
    enum Outcome: String { case applied, blocked, removed, pending, error }

    /// The editor's unsaved text, shown only on the page it was opened from while that page stays on its host.
    struct Preview {
        let page: ObjectIdentifier
        let profileID: String
        let host: String
        var css: String
    }

    private(set) var book: SiteStyleBook
    @ObservationIgnored var preview: Preview?

    private final class WebKitEntry {
        weak var page: WebPage?
        weak var controller: WKUserContentController?
        var script: WKUserScript?
        let profileID: String
        init(page: WebPage, controller: WKUserContentController, profileID: String) {
            self.page = page; self.controller = controller; self.profileID = profileID
        }
    }
    @ObservationIgnored private var webKitPages: [WebKitEntry] = []
    #if BOAZ_CHROMIUM
    @ObservationIgnored let chromiumPages = NSHashTable<ChromiumEnginePageAdapter>.weakObjects()
    /// The document each Chromium page last had its style applied to (`navigationID`).
    @ObservationIgnored var chromiumDocuments: [ObjectIdentifier: UInt64] = [:]
    #endif

    private init() {
        book = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(SiteStyleBook.self, from: $0) } ?? SiteStyleBook()
    }

    /// The profile a page's styles belong to. A WebKit Incognito tab has no profile of its own and reads the
    /// default profile's, read-only; Chromium's private pages already name their parent profile.
    static func profileKey(_ profileID: String?) -> String {
        guard profileID == "incognito" else { return profileID ?? "default" }
        return MacModel.shared.sidebar.profiles.first(where: \.isDefault)?.id ?? "default"
    }

    // MARK: Saving

    func save(_ css: String, profileID: String, host: String) throws {
        var next = book
        try next.save(css, profileID: profileID, host: host)
        commit(next, profileID: profileID, host: host)
    }

    func delete(profileID: String, host: String) {
        var next = book
        next.delete(profileID: profileID, host: host)
        commit(next, profileID: profileID, host: host)
    }

    /// Deleting a profile drops its styles. Skipped while the library hasn't loaded its profiles.
    func keepProfiles(_ profileIDs: Set<String>) {
        guard !profileIDs.isEmpty else { return }
        var next = book
        next.keepProfiles(profileIDs.union(["default"]))
        guard next != book else { return }
        book = next
        persist()
    }

    private func commit(_ next: SiteStyleBook, profileID: String, host: String) {
        guard next != book else { return }
        book = next
        persist()
        guard let key = SiteStyleBook.key(forHost: host) else { return }
        refresh(profileID: profileID, host: key)
    }

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(book), forKey: Self.defaultsKey)
    }

    /// The CSS a page of `host` shows now: the editor's draft on the page it previews, else the saved text.
    func effectiveCSS(page: ObjectIdentifier, profileID: String, host: String) -> String {
        if let preview, preview.page == page, preview.profileID == profileID, preview.host == host { return preview.css }
        return book.css(profileID: profileID, host: host) ?? ""
    }

    /// Every open page of the host in the profile (Incognito ones too) takes the saved text, and new pages of the
    /// profile start with it.
    private func refresh(profileID: String, host: String) {
        webKitPages.removeAll { $0.page == nil || $0.controller == nil }
        for entry in webKitPages where entry.profileID == profileID {
            installScript(entry)
            if let page = entry.page, Self.hostKey(page.url) == host {
                let css = effectiveCSS(page: ObjectIdentifier(page), profileID: profileID, host: host)
                Task { await Self.run(css, on: page) }
            }
        }
        #if BOAZ_CHROMIUM
        refreshChromium(profileID: profileID, host: host)
        #endif
    }

    static func hostKey(_ url: URL?) -> String? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host() else { return nil }
        return SiteStyleBook.key(forHost: host)
    }

    // MARK: WebKit

    /// A new WebKit page (a tab, a peek, the protected-video fallback) picks its host's style up at document start.
    /// The page's controller is shared with it by reference, so a script swapped in later reaches its next load.
    func attach(_ page: WebPage, controller: WKUserContentController, profileID: String?) {
        webKitPages.removeAll { $0.page == nil || $0.controller == nil }
        let entry = WebKitEntry(page: page, controller: controller, profileID: Self.profileKey(profileID))
        webKitPages.append(entry)
        installScript(entry)
    }

    /// WKUserContentController can only remove all of its scripts, so the others are put back around ours.
    private func installScript(_ entry: WebKitEntry) {
        guard let controller = entry.controller else { return }
        let styles = book.cssByHost(profileID: entry.profileID)
        if let old = entry.script {
            let others = controller.userScripts.filter { $0 !== old }
            controller.removeAllUserScripts()
            others.forEach(controller.addUserScript)
            entry.script = nil
        }
        guard !styles.isEmpty, let data = try? JSONEncoder().encode(styles) else { return }
        let script = WKUserScript(source: Self.userScript(styles: String(decoding: data, as: UTF8.self)),
                                  injectionTime: .atDocumentStart, forMainFrameOnly: true, in: Self.world)
        controller.addUserScript(script)
        entry.script = script
    }

    @discardableResult
    static func run(_ css: String, on page: WebPage) async -> Outcome? {
        let value = try? await page.callJavaScript("return (\(keeper))(css);", arguments: ["css": css],
                                                   contentWorld: world)
        return (value as? String).flatMap(Outcome.init(rawValue:))
    }

    /// Runs at document start in every main frame: the page looks its own host up, as `SiteStyleBook.key` does.
    private static func userScript(styles: String) -> String {
        """
        (() => {
            if (!/^https?:$/.test(location.protocol)) return;
            const styles = \(styles);
            let host = location.hostname.toLowerCase().replace(/\\.+$/, '');
            if (host.startsWith('www.') && host.slice(4).includes('.')) host = host.slice(4);
            const css = Object.prototype.hasOwnProperty.call(styles, host) ? styles[host] : '';
            if (css) (\(keeper))(css);
        })();
        """
    }

    // MARK: The style keeper

    /// Keeps one `<style>` in the document: created with `textContent` only (never markup), in `<head>`, or in the
    /// root element until there is one, moved to the end of `<head>` once the document is parsed so it comes after
    /// the site's own rules, and put back if the page (Turbo, hydration) removes it. Called again with new text, it
    /// updates in place; with empty text, it removes the element. Rules the browser can't read are skipped by the
    /// browser itself, and nothing here can throw into the caller.
    static let keeper = """
        (css) => {
            try {
                const k = window.__boazSiteStyle || (window.__boazSiteStyle = { css: '', node: null, observer: null, watched: [] });
                k.css = typeof css === 'string' ? css : '';
                const unwatch = () => { k.observer?.disconnect(); k.watched = []; };
                const watch = () => {
                    const targets = [document, document.documentElement, document.head].filter(Boolean);
                    if (targets.length === k.watched.length && targets.every((t, i) => t === k.watched[i])) return;
                    k.observer = k.observer || new MutationObserver(() => k.place());
                    k.observer.disconnect();
                    targets.forEach(t => k.observer.observe(t, { childList: true }));
                    k.watched = targets;
                };
                k.place = () => {
                    if (!k.css) { k.node?.remove(); unwatch(); return; }
                    if (!k.node) {
                        k.node = document.createElement('style');
                        k.node.setAttribute('data-boaz-site-style', '');
                    }
                    if (k.node.textContent !== k.css) k.node.textContent = k.css;
                    const parent = document.head || document.documentElement;
                    if (parent && k.node.parentNode !== parent) parent.appendChild(k.node);
                    watch();
                };
                if (!k.parsed && document.readyState === 'loading') {
                    k.parsed = true;
                    document.addEventListener('DOMContentLoaded', () => {
                        if (k.css && k.node && document.head) document.head.appendChild(k.node);
                    }, { once: true });
                }
                k.place();
                if (!k.css) return 'removed';
                if (!k.node.isConnected) return 'pending';
                return k.node.sheet ? 'applied' : 'blocked';
            } catch (error) {
                return 'error';
            }
        }
        """
}
