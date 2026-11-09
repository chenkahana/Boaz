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

    private var themeText: Color {
        (theme?.color("title", dark: dark) ?? theme?.color("foregroundPrimary", dark: dark))?.color ?? Theme.textPrimary
    }

    private var primaryText: Color.Resolved { Contrast.legible(themeText.resolve(in: environment), on: backdrop) }

    /// The gradient's stops as drawn: over the window's own background.
    private var backdrop: [Color.Resolved] {
        let base = (dark ? Color.black : Color.white).resolve(in: environment)
        return stopColors.map { Contrast.over($0.resolve(in: environment), base) }
    }

    private var environment: EnvironmentValues {
        var environment = EnvironmentValues()
        environment.colorScheme = dark ? .dark : .light
        return environment
    }
    /// Arc's grain overlay strength, 0…1.
    var grain: Double { theme?.backdrop(dark: dark)?.noise ?? 0 }

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

/// Arc's grain overlay (`noiseFactor`): a static noise texture tiled over the space's backdrop.
struct GrainOverlay: View {
    let amount: Double

    var body: some View {
        Image(decorative: Self.texture, scale: 2)
            .resizable(resizingMode: .tile)
            .blendMode(.overlay)
            .opacity(min(max(amount, 0), 1))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private static let texture: CGImage = {
        let side = 128
        var seed: UInt32 = 0x2545F491
        let pixels = (0..<side * side).map { _ -> UInt8 in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: seed >> 24)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                       space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }()
}
