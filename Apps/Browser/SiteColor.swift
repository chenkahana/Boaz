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
    private static var cache: [String: SiteColor] = [:]

    static func cached(for url: URL?) -> SiteColor? { url?.host().flatMap { cache[$0] } }

    /// Reads the color from a loaded page; `nil` when it has none worth tinting with.
    static func sample(_ page: WebPage) async -> SiteColor? {
        guard let host = page.url?.host(),
              let values = try? await page.callJavaScript(SiteEdges.sampler + "return sampleEdges();",
                                                         contentWorld: .defaultClient) as? [NSNumber],
              let edges = SiteEdges(values.map(\.doubleValue))
        else { return nil }
        let usable = edges.top.isPlainWhite ? nil : edges.top
        cache[host] = usable
        return usable
    }
}

/// The page's own background color along each edge of the viewport, which the screen's edges around the page
/// (safe areas, the camera strip, the fold) take on so the page seems to run under them. White pages get white.
struct SiteEdges: Hashable {
    /// `theme-color` for the current appearance, else what's under the top edge.
    let top: SiteColor
    let bottom: SiteColor
    /// Down the right-hand edge, top to bottom: where each run of one color starts and ends.
    let trailing: [Stop]

    struct Stop: Hashable {
        let color: SiteColor
        /// 0 at the top of the viewport, 1 at the bottom.
        let location: Double
    }

    /// The crossfade as the colors change (navigating, scrolling into a differently colored section).
    static func fade(reduceMotion: Bool) -> Animation { .easeInOut(duration: reduceMotion ? 0.15 : 0.25) }

    /// From the sampler's flat array: top and bottom `r, g, b` (0–255), then `r, g, b, location` per trailing stop.
    init?(_ components: [Double]) {
        guard components.count >= 6 + 4, (components.count - 6) % 4 == 0 else { return nil }
        func color(_ i: Int) -> SiteColor {
            SiteColor(red: components[i] / 255, green: components[i + 1] / 255, blue: components[i + 2] / 255)
        }
        top = color(0)
        bottom = color(3)
        trailing = stride(from: 6, to: components.count, by: 4).map { Stop(color: color($0), location: components[$0 + 3]) }
    }

    /// The trailing color at a fraction (0 top … 1 bottom) of the page's height.
    func trailing(at fraction: Double) -> SiteColor {
        (trailing.last { $0.location <= fraction } ?? trailing[0]).color
    }

    /// The trailing colors as a gradient's stops, sharp where the page changes color.
    var trailingStops: [Gradient.Stop] { trailing.map { Gradient.Stop(color: $0.color.color, location: $0.location) } }

    // MARK: Cache

    /// Per page (a site's pages differ), then per host for a page not seen yet. Kept in memory only.
    private static var pages: [String: SiteEdges] = [:]
    private static var hosts: [String: SiteEdges] = [:]
    private static var recency: [String] = []

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
        if let host = url.host() { hosts[host] = edges }
    }

    private static func pageKey(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.string ?? url.absoluteString
    }

    // MARK: Live sampling

    static let messageName = "boazSiteEdges"

    /// Samples once the document is ready, then again (only posting changes) on load, scroll (at most every
    /// 150 ms), resize, back-forward cache restores, `theme-color` edits, appearance changes and theme toggles
    /// on the root elements. Runs in the client world, so pages can't see or spoof it.
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
            let last = '', timer = 0, lastRun = 0;
            const post = () => {
                timer = 0;
                lastRun = Date.now();
                const c = sampleEdges(), key = c.join();
                if (key === last) return;
                last = key;
                window.webkit.messageHandlers.\(messageName).postMessage({ href: location.href, c });
            };
            const schedule = (delay = 0) => {
                if (timer) return;
                timer = setTimeout(() => requestAnimationFrame(post), delay);
            };
            const throttled = () => schedule(Math.max(0, 150 - (Date.now() - lastRun)));
            addEventListener('scroll', throttled, { passive: true, capture: true });
            addEventListener('resize', throttled, { passive: true });
            addEventListener('load', () => schedule());
            addEventListener('pageshow', () => { last = ''; schedule(); });
            matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => schedule(50));
            new MutationObserver(() => schedule(100)).observe(document.head || document.documentElement,
                { subtree: true, childList: true, attributes: true, attributeFilter: ['content', 'media'] });
            // Theme switches flip a class or attribute on <html> or <body>; their transitions finish later.
            const settled = () => { schedule(50); setTimeout(() => schedule(), 450); };
            new MutationObserver(settled).observe(document.documentElement, { attributes: true });
            if (document.body) new MutationObserver(settled).observe(document.body, { attributes: true });
            schedule();
        })();
        """

    /// Defines `sampleEdges()`, returning the top and bottom `r, g, b` (0–255), then `r, g, b, location` where each
    /// run of one color starts and ends down the right-hand edge (probed every ~32 px). Colors
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
        const colorAt = (x, y, minWidth) => {
            const stack = document.elementsFromPoint(x, y);
            for (const el of [document.body, document.documentElement]) if (el && !stack.includes(el)) stack.push(el);
            const layers = [];
            for (const el of stack) {
                if (el !== document.body && el !== document.documentElement
                    && el.getBoundingClientRect().width < minWidth) continue;
                const c = rgba(getComputedStyle(el).backgroundColor);
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
                if (c[3] > 0) top = over(c, colorAt(w / 2, 1, w * 0.9));
            }
            const out = [...(top || colorAt(w / 2, 1, w * 0.9)), ...colorAt(w / 2, h - 2, w * 0.9)];
            const n = Math.min(40, Math.max(8, Math.ceil(h / 32)));
            const probes = [];
            for (let i = 0; i < n; i++) {
                const y = 1 + (h - 3) * i / (n - 1);
                probes.push([...colorAt(w - 2, y, w * 0.5), y / h]);
            }
            const same = (a, b) => b && a[0] === b[0] && a[1] === b[1] && a[2] === b[2];
            probes.forEach((p, i) => { if (!same(p, probes[i - 1]) || !same(p, probes[i + 1])) out.push(...p); });
            return out;
        };
        """
}
