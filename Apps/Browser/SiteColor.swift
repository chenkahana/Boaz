import SwiftUI
import WebKit

/// A site's own color, which the browser chrome takes on (Arc-style). Comes from the page's `theme-color` for the
/// current appearance, else the background of whatever spans the top of the viewport: a header bar, or the page.
struct SiteColor: Equatable {
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
              let rgba = try? await page.callJavaScript(script, contentWorld: .defaultClient) as? [NSNumber], rgba.count == 4
        else { return nil }
        let color = SiteColor(red: rgba[0].doubleValue / 255, green: rgba[1].doubleValue / 255,
                              blue: rgba[2].doubleValue / 255)
        let usable = color.isPlainWhite ? nil : color
        cache[host] = usable
        return usable
    }

    /// Returns `[r, g, b, a]` (0–255) or null. Colors go through a 1px canvas so WebKit's own CSS parser handles
    /// every syntax (names, hex, rgb, hsl, color(), oklch…) and converts it to sRGB.
    private static let script = """
        const ctx = Object.assign(document.createElement('canvas'), { width: 1, height: 1 })
            .getContext('2d', { willReadFrequently: true });
        const rgba = css => {
            ctx.clearRect(0, 0, 1, 1);
            ctx.fillStyle = 'transparent';
            ctx.fillStyle = css;
            ctx.fillRect(0, 0, 1, 1);
            return Array.from(ctx.getImageData(0, 0, 1, 1).data);
        };
        const meta = [...document.querySelectorAll('meta[name="theme-color" i]')]
            .find(m => m.content && (!m.media || matchMedia(m.media).matches));
        if (meta) {
            const c = rgba(meta.content);
            if (c[3] > 0) return c;
        }
        const top = [...document.elementsFromPoint(innerWidth / 2, 1), document.body, document.documentElement];
        for (const el of top) {
            if (!el || el.getBoundingClientRect().width < innerWidth * 0.9) continue;
            const c = rgba(getComputedStyle(el).backgroundColor);
            if (c[3] >= 128) return c;
        }
        return null;
        """
}
