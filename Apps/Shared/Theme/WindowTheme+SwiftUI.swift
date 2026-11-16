import BoazKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension WindowTheme.RGBA {
    /// Arc writes extended-sRGB components (some fall outside 0…1); the platform colors keep them intact.
    var color: Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor(red: red, green: green, blue: blue, alpha: alpha))
        #else
        Color(nsColor: NSColor(colorSpace: .extendedSRGB, components: [red, green, blue, alpha], count: 4))
        #endif
    }

    /// Hue, saturation and brightness of the color clamped to sRGB.
    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let r = min(max(red, 0), 1), g = min(max(green, 0), 1), b = min(max(blue, 0), 1)
        let high = max(r, g, b), delta = high - min(r, g, b)
        guard delta > 0 else { return (0, 0, high) }
        var hue = switch high {
        case r: (g - b) / delta
        case g: (b - r) / delta + 2
        default: (r - g) / delta + 4
        }
        hue /= 6
        return (hue < 0 ? hue + 1 : hue, delta / high, high)
    }
}

/// Renders a space's Arc theme. Falls back to Boaz's indigo palette when a space has no theme.
struct SpaceStyle {
    let theme: WindowTheme?
    let dark: Bool

    init(_ space: Space?, scheme: ColorScheme) {
        theme = space?.theme
        dark = (Self.fixedScheme(theme) ?? scheme) == .dark
    }

    /// The appearance an Arc theme pins its space to on the Mac (a light theme stays light in Dark Mode, as in
    /// Arc), or nil to follow the system.
    static func colorScheme(of space: Space?) -> ColorScheme? { fixedScheme(space?.theme) }

    private static func fixedScheme(_ theme: WindowTheme?) -> ColorScheme? {
        #if os(macOS)
        switch theme?.fixedAppearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
        #else
        nil
        #endif
    }

    var background: Color { theme?.color("background", dark: dark)?.color.opacity(1) ?? Theme.indigo(3) }
    var tint: Color { theme?.primaryColorPalette?["midTone"]?.color ?? Theme.brand }
    /// Text on the backdrop: Arc's `title` role (its sidebar text color; `foregroundPrimary` is closer to an
    /// accent) where it reads at 4.5:1 (WCAG AA) on every part of the backdrop, else that color pushed toward
    /// black or white until it does.
    var foreground: Color { Color(primaryText) }

    /// Secondary text (headers, hints, captions): a step from `foreground` toward the backdrop, kept at 4.5:1.
    var secondary: Color {
        Color(Contrast.legible(Contrast.mix(primaryText, Contrast.average(backdrop), 0.4), on: backdrop))
    }

    /// `secondary` for the Mac sidebar: still 4.5:1 where a row's hover or selection fill (the label color at up to
    /// 12%) lies under it.
    var secondaryOnFills: Color {
        let label = (dark ? Color.white : .black).resolve(in: environment)
        let fill = Color.Resolved(red: label.red, green: label.green, blue: label.blue, opacity: 0.12)
        let backgrounds = backdrop + backdrop.map { Contrast.over(fill, $0) }
        return Color(Contrast.legible(Contrast.mix(primaryText, Contrast.average(backdrop), 0.4), on: backgrounds))
    }

    private var themeText: Color {
        (theme?.color("title", dark: dark) ?? theme?.color("foregroundPrimary", dark: dark))?.color ?? Theme.textPrimary
    }

    private var primaryText: Color.Resolved { Contrast.legible(themeText.resolve(in: environment), on: backdrop) }

    /// The gradient's stops as drawn: over the window's own background.
    private var backdrop: [Color.Resolved] {
        let base = (dark ? Color.black : Color.white).resolve(in: environment)
        return stopColors.map { Contrast.over($0.opacity(opacity).resolve(in: environment), base) }
    }

    private var environment: EnvironmentValues {
        var environment = EnvironmentValues()
        environment.colorScheme = dark ? .dark : .light
        return environment
    }
    /// The texture over the backdrop: the theme's own, or grain in themes from before textures that turn it on.
    var texture: WindowTheme.Texture { theme?.texture ?? (theme?.showsGrain == true ? .grain : .none) }

    /// The texture's strength, 0…1: the theme's, else Arc's `noiseFactor`, else a light default.
    var textureAmount: Double {
        if let amount = theme?.textureIntensity { return amount }
        let noise = theme?.backdrop(dark: dark)?.noise ?? 0
        return noise > 0 ? noise : 0.2
    }

    /// The backdrop's opacity where the window lets the desktop show through (Mac): what the theme's translucency
    /// leaves, never under 40%, so the space keeps its color and the text measured against it stays legible.
    var opacity: Double {
        #if os(macOS)
        1 - min(max(theme?.translucency ?? 0, 0), 1) * 0.6
        #else
        1
        #endif
    }

    /// Whether the theme turns on the soft light from the window's top corner.
    var lightStreak: Bool { theme?.showsLightStreak == true }

    var gradient: LinearGradient {
        theme?.backdrop(dark: dark) == nil
            ? LinearGradient(colors: stopColors, startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: stopColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var stopColors: [Color] {
        guard let backdrop = theme?.backdrop(dark: dark) else { return [background, tint.opacity(dark ? 0.55 : 0.45)] }
        return Self.stops(backdrop, base: theme?.color("background", dark: dark))
    }

    /// Arc's semantic `background` is the first base color already blended for this appearance (intensity,
    /// translucency). A single-color theme is flat in that color; a gradient's other stops keep their own hue and
    /// take the same blend, scaled by how they differ from the first base color.
    private static func stops(_ backdrop: WindowTheme.Backdrop, base: WindowTheme.RGBA?) -> [Color] {
        guard let base else { return backdrop.colors.count == 1 ? [backdrop.colors[0].color, backdrop.colors[0].color]
                                                                : backdrop.colors.map(\.color) }
        guard backdrop.colors.count > 1 else { return [base.color, base.color] }
        let blended = base.hsb, first = backdrop.colors[0].hsb
        return [base.color] + backdrop.colors.dropFirst().map { stop in
            let own = stop.hsb
            return Color(hue: own.hue,
                         saturation: min(1, blended.saturation * own.saturation / max(first.saturation, 0.05)),
                         brightness: min(1, blended.brightness * own.brightness / max(first.brightness, 0.05)))
        }
    }
}

/// WCAG 2 contrast arithmetic on resolved sRGB colors.
enum Contrast {
    static func luminance(_ c: Color.Resolved) -> Double {
        func linear(_ v: Float) -> Double {
            let v = Double(min(max(v, 0), 1))
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
    }

    static func ratio(_ a: Color.Resolved, _ b: Color.Resolved) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// `top` composited over the opaque `base`.
    static func over(_ top: Color.Resolved, _ base: Color.Resolved) -> Color.Resolved {
        let a = top.opacity
        return Color.Resolved(red: top.red * a + base.red * (1 - a), green: top.green * a + base.green * (1 - a),
                              blue: top.blue * a + base.blue * (1 - a))
    }

    /// `amount` of the way from `a` to `b` (opaque).
    static func mix(_ a: Color.Resolved, _ b: Color.Resolved, _ amount: Float) -> Color.Resolved {
        Color.Resolved(red: a.red + (b.red - a.red) * amount, green: a.green + (b.green - a.green) * amount,
                       blue: a.blue + (b.blue - a.blue) * amount)
    }

    static func average(_ colors: [Color.Resolved]) -> Color.Resolved {
        let n = Float(max(colors.count, 1))
        return Color.Resolved(red: colors.map(\.red).reduce(0, +) / n, green: colors.map(\.green).reduce(0, +) / n,
                              blue: colors.map(\.blue).reduce(0, +) / n)
    }

    /// `color` itself if it reaches `minimum` against every background, else the least shift toward black or white
    /// (whichever reads better) that does; black or white when even that falls short.
    static func legible(_ color: Color.Resolved, on backgrounds: [Color.Resolved], minimum: Double = 4.5)
        -> Color.Resolved {
        func worst(_ c: Color.Resolved) -> Double { backgrounds.map { ratio(c, $0) }.min() ?? 21 }
        let color = Color.Resolved(red: color.red, green: color.green, blue: color.blue)
        guard worst(color) < minimum else { return color }
        let black = Color.Resolved(red: 0, green: 0, blue: 0), white = Color.Resolved(red: 1, green: 1, blue: 1)
        let target = worst(black) >= worst(white) ? black : white
        guard worst(target) > minimum else { return target }
        var low: Float = 0, high: Float = 1
        for _ in 0..<12 {
            let middle = (low + high) / 2
            if worst(mix(color, target, middle)) >= minimum { high = middle } else { low = middle }
        }
        return mix(color, target, high)
    }
}

/// A texture tiled over a space's backdrop, blended so it lightens and darkens the colors under it. Grain is Arc's
/// (`noiseFactor`); paper, dots and linen are Boaz's.
struct TextureOverlay: View {
    let texture: WindowTheme.Texture
    let amount: Double

    var body: some View {
        if let image = Self.images[texture] {
            Image(decorative: image, scale: 2)
                .resizable(resizingMode: .tile)
                .blendMode(.overlay)
                .opacity(min(max(amount, 0), 1))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// 128-pixel gray tiles around mid-gray, which the overlay blend leaves unchanged.
    private static let images: [WindowTheme.Texture: CGImage] = {
        let side = 128
        var seed: UInt32 = 0x2545F491
        func random() -> Double {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return Double(seed >> 24) / 255
        }
        func tile(_ value: (_ x: Int, _ y: Int) -> Double) -> CGImage {
            let pixels = (0..<side * side).map { UInt8((min(max(value($0 % side, $0 / side), 0), 1) * 255).rounded()) }
            let provider = CGDataProvider(data: Data(pixels) as CFData)!
            return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                           space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        }
        let grain = (0..<side * side).map { _ in random() }
        // Paper: soft blotches (a coarse noise grid, smoothly interpolated and wrapped so it tiles) under fine grain.
        let cells = 8, coarse = (0..<cells * cells).map { _ in random() }
        func blotch(_ x: Int, _ y: Int) -> Double {
            let fx = Double(x) / Double(side / cells), fy = Double(y) / Double(side / cells)
            let x0 = Int(fx), y0 = Int(fy), tx = fx - Double(x0), ty = fy - Double(y0)
            func at(_ i: Int, _ j: Int) -> Double { coarse[(j % cells) * cells + i % cells] }
            let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
            let top = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * sx
            let bottom = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * sx
            return top + (bottom - top) * sy
        }
        // Linen: every row and column of thread a little lighter or darker than the next.
        let rows = (0..<side).map { _ in random() - 0.5 }, columns = (0..<side).map { _ in random() - 0.5 }
        return [
            .grain: tile { x, y in grain[y * side + x] },
            .paper: tile { x, y in 0.5 + (blotch(x, y) - 0.5) * 0.7 + (grain[y * side + x] - 0.5) * 0.3 },
            // Dots: a halftone grid of soft dark dots, every 8 pixels.
            .dots: tile { x, y in
                let dx = Double(x % 8) - 3.5, dy = Double(y % 8) - 3.5
                return 0.5 - 0.4 * max(0, 1 - (dx * dx + dy * dy).squareRoot() / 2.2)
            },
            .linen: tile { x, y in 0.5 + rows[y] * 0.45 + columns[x] * 0.45 + (grain[y * side + x] - 0.5) * 0.15 },
        ]
    }()
}
