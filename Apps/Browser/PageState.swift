import Foundation
import OSLog
import WebKit

/// Where a tab's page was scrolled: the window, and the inner scrollers that chat and mail sites scroll instead (their
/// root doesn't scroll). A page loaded again (unloaded to save memory, its process ended by the system, or after a
/// relaunch) goes back there. Read and put back by a script in its own content world, which pages can't see or call.
/// Lives in `Apps/Browser` so both apps compile it.
struct PageState: Codable, Equatable {
    /// Where the page was, as the script reads it.
    struct Place: Codable, Equatable {
        struct Offset: Codable, Equatable {
            /// A CSS selector for an inner scroller; nil for the window.
            var path: String?
            var top: Double
            var left: Double
            /// Within 4 px of the end: put back at the end, however much content arrived since (a chat's newest message).
            var atBottom: Bool
        }

        var url: URL
        var window: Offset
        /// The largest first, at most 8.
        var scrollers: [Offset]

        init?(json: String) {
            guard let place = try? JSONDecoder().decode(Self.self, from: Data(json.utf8)) else { return nil }
            self = place
        }
    }

    var place: Place
    var savedAt: Date

    var url: URL { place.url }

    /// The page at its very top, with no inner scroller moved: nothing to go back to.
    private var isAtStart: Bool {
        place.window.top == 0 && place.window.left == 0 && !place.window.atBottom && place.scrollers.isEmpty
    }

    // MARK: Script

    private static let world = WKContentWorld.world(name: "boaz-page-state")
    private static let messageName = "boazPageState"

    /// Follows the page's scrolling, reporting where it settles to `onSettle`.
    static func install(in configuration: inout WebPage.Configuration, onSettle: @escaping (PageState) -> Void) {
        configuration.userContentController.addUserScript(
            WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
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

    /// Receives the script's readings once scrolling settles.
    private final class Messages: NSObject, WKScriptMessageHandler {
        private let onSettle: (PageState) -> Void

        init(onSettle: @escaping (PageState) -> Void) { self.onSettle = onSettle }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let json = message.body as? String, let place = Place(json: json) else { return }
            onSettle(PageState(place: place, savedAt: .now))
        }
    }

    /// Scroll events don't bubble, but the document sees every one while capturing: the elements the user scrolled are
    /// remembered as they go, so reading never walks the DOM. A selector stops at the nearest element with an id.
    private static let script = """
        (() => {
            if (window.__boazPageState) return;
            const seen = new WeakSet();
            let scrollers = [], settle = 0, restoring = false;
            const atEnd = (offset, max) => max > 4 && offset >= max - 4;
            const selector = element => {
                const parts = [];
                for (let e = element; e && e !== document.documentElement; e = e.parentElement) {
                    if (e.id) { parts.unshift('#' + CSS.escape(e.id)); return parts.join(' > '); }
                    let n = 1;
                    for (let s = e.previousElementSibling; s; s = s.previousElementSibling) if (s.localName === e.localName) n++;
                    parts.unshift(e.localName + ':nth-of-type(' + n + ')');
                }
                return [':root', ...parts].join(' > ');
            };
            const read = () => {
                if (restoring) return null;
                const root = document.scrollingElement || document.documentElement;
                const live = scrollers.map(r => r.deref())
                    .filter(e => e && e.isConnected && (e.scrollHeight > e.clientHeight || e.scrollWidth > e.clientWidth))
                    .sort((a, b) => b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight)
                    .slice(0, 8);
                return JSON.stringify({
                    url: location.href,
                    window: { top: scrollY, left: scrollX, atBottom: atEnd(scrollY, root.scrollHeight - innerHeight) },
                    scrollers: live.map(e => ({ path: selector(e), top: e.scrollTop, left: e.scrollLeft,
                                                atBottom: atEnd(e.scrollTop, e.scrollHeight - e.clientHeight) })),
                });
            };
            document.addEventListener('scroll', event => {
                const target = event.target;
                if (target instanceof Element && !seen.has(target)) {
                    seen.add(target);
                    scrollers.push(new WeakRef(target));
                    if (scrollers.length > 32) scrollers = scrollers.filter(r => r.deref()?.isConnected).slice(-32);
                }
                clearTimeout(settle);
                settle = setTimeout(() => {
                    const state = read();
                    if (state) window.webkit.messageHandlers.\(messageName).postMessage(state);
                }, 400);
            }, { capture: true, passive: true });
            // Tries again every 150 ms while the page is still rendering what it scrolled (the element is missing, or
            // too short to get there); at the end, until there is content and it has stopped growing for 450 ms.
            const restore = place => new Promise(resolve => {
                const deadline = Date.now() + 8000, heights = new Map(), interactions = ['wheel', 'touchstart', 'keydown', 'pointerdown'];
                const { top, left, atBottom } = place.window;
                const offsets = (top || left || atBottom ? [place.window] : []).concat(place.scrollers);
                let timer = 0;
                const finish = () => {
                    clearTimeout(timer);
                    interactions.forEach(type => removeEventListener(type, finish, true));
                    restoring = false;
                    resolve(null);
                };
                const step = () => {
                    let done = true;
                    for (const offset of offsets) {
                        let element = null;
                        if (offset.path) {
                            try { element = document.querySelector(offset.path); } catch {}
                            if (!element) { done = false; continue; }
                        }
                        const root = document.scrollingElement || document.documentElement;
                        const height = (element || root).scrollHeight;
                        const max = height - (element ? element.clientHeight : innerHeight);
                        const y = offset.atBottom ? max : offset.top;
                        if (element) { element.scrollTop = y; element.scrollLeft = offset.left; } else { scrollTo(offset.left, y); }
                        const now = element ? element.scrollTop : scrollY;
                        if (offset.atBottom) {
                            const last = heights.get(offset.path);
                            const steady = last && last.height === height ? last.steady + 1 : 0;
                            heights.set(offset.path, { height, steady });
                            if (max <= 4 || steady < 3) done = false;
                        } else if (Math.abs(now - y) > 2) {
                            done = false;
                        }
                    }
                    if (done || Date.now() > deadline) finish(); else timer = setTimeout(step, 150);
                };
                interactions.forEach(type => addEventListener(type, finish, { capture: true, passive: true }));
                restoring = true;
                step();
            });
            window.__boazPageState = { read, restore };
        })();
        """

    // MARK: Store

    /// Each tab's state, by tab id: saved in one small file and kept a week, or (private browsing) only in memory.
    final class Store {
        private static let lifetime: TimeInterval = 7 * 86_400
        nonisolated private static let log = Logger(subsystem: "com.chenkahana.boaz", category: "page-state")
        /// Writes run in order, off the main thread.
        nonisolated private static let queue = DispatchQueue(label: "com.chenkahana.boaz.page-state", qos: .utility)

        private var states: [String: PageState]
        private let file: URL?

        /// Kept only in memory.
        init() {
            states = [:]
            file = nil
        }

        /// The states saved on this device, less those older than a week.
        private init(file: URL) {
            self.file = file
            let saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: PageState].self, from: $0) }
            states = (saved ?? [:]).filter { $0.value.savedAt > .now - Self.lifetime }
        }

        static func saved() -> Store {
            Store(file: URL.applicationSupportDirectory.appending(path: "Page States.json"))
        }

        subscript(tabID: String) -> PageState? { states[tabID] }

        /// A page back at its very top replaces the saved state with none. The same place is written again only
        /// once an hour, which keeps a tab in use from expiring.
        func set(_ state: PageState, for tabID: String) {
            let new = state.isAtStart ? nil : state
            if let old = states[tabID], let new, old.place == new.place, new.savedAt.timeIntervalSince(old.savedAt) < 3600 {
                return
            }
            guard states[tabID] != new else { return }
            states[tabID] = new
            save()
        }

        func remove(_ tabID: String) {
            guard states.removeValue(forKey: tabID) != nil else { return }
            save()
        }

        /// Forgets the tabs that are gone.
        func prune(keeping tabIDs: Set<String>) {
            let kept = states.filter { tabIDs.contains($0.key) }
            guard kept.count != states.count else { return }
            states = kept
            save()
        }

        /// Waits for the writes queued so far, before the app quits.
        static func flush() { queue.sync {} }

        private func save() {
            guard let file, let data = try? JSONEncoder().encode(states) else { return }
            Self.queue.async {
                do {
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    try data.write(to: file, options: .atomic)
                } catch {
                    Self.log.error("Saving page states failed: \(String(describing: error))")
                }
            }
        }
    }
}
