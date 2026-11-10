import SwiftUI
import WebKit

/// A site's own color, which the browser chrome takes on (Arc-style). Comes from the page's `theme-color` for the
/// current appearance, else the background of whatever spans the top of the viewport: a header bar, or the page.
struct SiteColor: Hashable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

    /// WCAG relative luminance.
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// Above this luminance black text out-contrasts white (where the two WCAG contrast ratios cross).
    var isLight: Bool { luminance > 0.179 }

    /// The appearance whose text and glass stay legible on the color.
    var colorScheme: ColorScheme { isLight ? .light : .dark }

    /// Text and icons drawn on the color.
    var foreground: Color { isLight ? .black.opacity(0.82) : .white }

    /// Plain white pages are most of the web; tinting with them would only wash out the space.
    private var isPlainWhite: Bool { luminance > 0.88 && max(red, green, blue) - min(red, green, blue) < 0.06 }

    /// The fade between colors on tab switches and navigations.
    static func fade(reduceMotion: Bool) -> Animation { .easeInOut(duration: reduceMotion ? 0.15 : 0.45) }

    // MARK: Sampling

    /// Last color seen per host, so a tab arriving at a known site is tinted before its page finishes loading.
    /// The 300 most recently sampled hosts.
    private static var cache: [String: SiteColor] = [:]
    private static var cacheRecency: [String] = []

    static func cached(for url: URL?) -> SiteColor? { url?.host().flatMap { cache[$0] } }

    /// Reads the color from a loaded page; `nil` when it has none worth tinting with.
    static func sample(_ page: WebPage) async -> SiteColor? {
        guard let host = page.url?.host(),
              let values = try? await page.callJavaScript(SiteEdges.sampler + "return sampleEdges();",
                                                         contentWorld: .defaultClient) as? [NSNumber],
              let edges = SiteEdges(values.map(\.doubleValue))
        else { return nil }
        let usable = edges.top.isPlainWhite ? nil : edges.top
        cacheRecency.removeAll { $0 == host }
        if let usable {
            cache[host] = usable
            cacheRecency.append(host)
            if cacheRecency.count > 300 { cache[cacheRecency.removeFirst()] = nil }
        } else {
            cache[host] = nil
        }
        return usable
    }
}

/// The page's own background color along each edge of the viewport, which the screen's edges around the page
/// (safe areas, the camera strip, the fold) take on so the page seems to run under them. White pages get white.
struct SiteEdges: Hashable {
    /// `theme-color` for the current appearance, else what's under the top edge.
    let top: SiteColor
    let bottom: SiteColor
    /// The page's own background (its page-sized wrappers, `body`, `html`), behind the rail. Unlike what's under the right-hand edge,
    /// it doesn't change while scrolling past differently colored cards and sections.
    let page: SiteColor

    /// The crossfade as the colors change (navigating, scrolling into a differently colored section).
    static func fade(reduceMotion: Bool) -> Animation { .easeInOut(duration: reduceMotion ? 0.15 : 0.25) }

    /// From the sampler's flat array: top, bottom and page `r, g, b` (0–255).
    init?(_ components: [Double]) {
        guard components.count == 9 else { return nil }
        func color(_ i: Int) -> SiteColor {
            SiteColor(red: components[i] / 255, green: components[i + 1] / 255, blue: components[i + 2] / 255)
        }
        top = color(0)
        bottom = color(3)
        page = color(6)
    }

    // MARK: Cache

    /// Per page (a site's pages differ), then per host for a page not seen yet. Kept in memory only, for the 300
    /// most recent of each.
    private static var pages: [String: SiteEdges] = [:]
    private static var hosts: [String: SiteEdges] = [:]
    private static var recency: [String] = []
    private static var hostRecency: [String] = []

    static func cached(for url: URL?) -> SiteEdges? {
        guard let url else { return nil }
        return pages[pageKey(url)] ?? url.host().flatMap { hosts[$0] }
    }

    static func remember(_ edges: SiteEdges, for url: URL) {
        let key = pageKey(url)
        if pages.updateValue(edges, forKey: key) == nil {
            recency.append(key)
            if recency.count > 300 { pages[recency.removeFirst()] = nil }
        }
        if let host = url.host(), hosts.updateValue(edges, forKey: host) == nil {
            hostRecency.append(host)
            if hostRecency.count > 300 { hosts[hostRecency.removeFirst()] = nil }
        }
    }

    private static func pageKey(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.string ?? url.absoluteString
    }

    // MARK: Live sampling

    static let messageName = "boazSiteEdges"

    /// Samples once the document is ready, then again (only posting changes) on load, once scrolling or resizing
    /// settles (at most once a second while it goes on), back-forward cache restores, `theme-color` edits,
    /// appearance changes and theme toggles on the root elements. A hidden page (another tab, or a page not on
    /// screen) doesn't sample until it shows again. Runs in the client world, so pages can't see or spoof it.
    static func userScript() -> WKUserScript {
        WKUserScript(source: liveScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient)
    }

    /// Receives the live script's samples for one page.
    final class Messages: NSObject, WKScriptMessageHandler {
        private let onSample: (SiteEdges, URL?) -> Void

        init(onSample: @escaping (SiteEdges, URL?) -> Void) { self.onSample = onSample }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any],
                  let values = body["c"] as? [NSNumber],
                  let edges = SiteEdges(values.map(\.doubleValue)) else { return }
            onSample(edges, (body["href"] as? String).flatMap(URL.init(string:)))
        }
    }

    private static let liveScript = """
        (() => {
            if (window.__boazSiteEdges) return;
            window.__boazSiteEdges = true;
            \(sampler)
            let last = '', timer = 0, lastRun = 0, missed = false, scrollTimer = 0, settleTimer = 0;
            const post = () => {
                timer = 0;
                if (document.hidden) { missed = true; return; }
                lastRun = Date.now();
                const c = sampleEdges(), key = c.join();
                if (key === last) return;
                last = key;
                window.webkit.messageHandlers.\(messageName).postMessage({ href: location.href, c });
            };
            const schedule = (delay = 0) => {
                if (timer) return;
                if (document.hidden) { missed = true; return; }
                timer = setTimeout(() => requestAnimationFrame(post), delay);
            };
            const moved = () => {
                clearTimeout(scrollTimer);
                if (Date.now() - lastRun > 1000) schedule();
                scrollTimer = setTimeout(() => schedule(), 150);
            };
            addEventListener('scroll', moved, { passive: true, capture: true });
            addEventListener('resize', moved, { passive: true });
            addEventListener('load', () => schedule());
            addEventListener('pageshow', () => { last = ''; schedule(); });
            document.addEventListener('visibilitychange', () => {
                if (!document.hidden && missed) { missed = false; schedule(); }
            });
            matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => schedule(50));
            // Only theme-color changes count: single-page apps rewrite <title> and other tags in <head> constantly.
            const isThemeColor = n => n.nodeName === 'META' && /^theme-color$/i.test(n.getAttribute('name') || '');
            new MutationObserver(records => {
                if (records.some(r => r.type === 'attributes' ? isThemeColor(r.target)
                    : [...r.addedNodes, ...r.removedNodes].some(isThemeColor))) schedule(100);
            }).observe(document.head || document.documentElement,
                { subtree: true, childList: true, attributes: true, attributeFilter: ['content', 'media', 'name'] });
            // Theme switches flip a class or attribute on <html> or <body>; their transitions finish later.
            const settled = () => {
                schedule(50);
                clearTimeout(settleTimer);
                settleTimer = setTimeout(() => schedule(), 450);
            };
            new MutationObserver(settled).observe(document.documentElement, { attributes: true });
            if (document.body) new MutationObserver(settled).observe(document.body, { attributes: true });
            schedule();
        })();
        """

    /// Defines `sampleEdges()`, returning the top, bottom and page background `r, g, b` (0–255). Colors
    /// go through a 1px canvas so WebKit's own CSS parser handles every syntax (names, hex, rgb, hsl, color(),
    /// oklch…) and converts it to sRGB. Each point composites the backgrounds stacked under it down to the first
    /// opaque one, skipping narrow elements (buttons, logos); then `body`, `html` and the canvas.
    static let sampler = """
        const edgeContext = Object.assign(document.createElement('canvas'), { width: 1, height: 1 })
            .getContext('2d', { willReadFrequently: true });
        const parsedColors = new Map();
        const rgba = css => {
            let c = parsedColors.get(css);
            if (c) return c;
            edgeContext.clearRect(0, 0, 1, 1);
            edgeContext.fillStyle = 'transparent';
            edgeContext.fillStyle = css;
            edgeContext.fillRect(0, 0, 1, 1);
            c = Array.from(edgeContext.getImageData(0, 0, 1, 1).data);
            if (parsedColors.size > 64) parsedColors.clear();
            parsedColors.set(css, c);
            return c;
        };
        const over = (top, under) => {
            const a = top[3] / 255;
            return [0, 1, 2].map(i => Math.round(top[i] * a + under[i] * (1 - a)));
        };
        const canvasColor = () => {
            const dark = matchMedia('(prefers-color-scheme: dark)').matches
                && /dark/.test(getComputedStyle(document.documentElement).colorScheme);
            return dark ? [0, 0, 0] : [255, 255, 255];
        };
        const colorAt = (x, y, minWidth, minHeight = 0) => {
            const stack = document.elementsFromPoint(x, y);
            for (const el of [document.body, document.documentElement]) if (el && !stack.includes(el)) stack.push(el);
            const layers = [];
            for (const el of stack) {
                if (el !== document.body && el !== document.documentElement) {
                    const r = el.getBoundingClientRect();
                    if (r.width < minWidth || r.height < minHeight) continue;
                }
                const style = getComputedStyle(el);
                let c = rgba(style.backgroundColor);
                // A gradient background (often under a translucent header) counts as its first color.
                if (c[3] < 255 && style.backgroundImage.includes('gradient')) {
                    const stop = style.backgroundImage.match(/rgba?\\([^)]*\\)/);
                    if (stop) { const g = rgba(stop[0]); if (g[3] > 0) { if (c[3] > 0) layers.push(c); c = g; } }
                }
                if (c[3] === 0) continue;
                layers.push(c);
                if (c[3] === 255) break;
            }
            return layers.reduceRight((under, layer) => over(layer, under), canvasColor());
        };
        const sampleEdges = () => {
            const w = innerWidth, h = innerHeight;
            let top = null;
            const meta = [...document.querySelectorAll('meta[name="theme-color" i]')]
                .find(m => m.content && (!m.media || matchMedia(m.media).matches));
            if (meta) {
                const c = rgba(meta.content);
                // Only a translucent theme-color needs what's under it.
                if (c[3] === 255) top = c.slice(0, 3);
                else if (c[3] > 0) top = over(c, colorAt(w / 2, 1, w * 0.9));
            }
            // The page's background: only page-sized layers (wrappers, `body`, `html`), never the cards and section
            // bars scrolling past.
            return [...(top || colorAt(w / 2, 1, w * 0.9)), ...colorAt(w / 2, h - 2, w * 0.9),
                    ...colorAt(w - 2, h / 2, w * 0.9, h - 1)];
        };
        """
}
