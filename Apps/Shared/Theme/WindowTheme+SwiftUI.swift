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
    /// Arc's `title` role is its sidebar text color; `foregroundPrimary` is closer to an accent.
    var foreground: Color {
        (theme?.color("title", dark: dark) ?? theme?.color("foregroundPrimary", dark: dark))?.color ?? Theme.textPrimary
    }
    /// Arc's grain overlay strength, 0…1.
    var grain: Double { theme?.backdrop(dark: dark)?.noise ?? 0 }

    var gradient: LinearGradient {
        guard let backdrop = theme?.backdrop(dark: dark) else {
            return LinearGradient(colors: [background, tint.opacity(dark ? 0.55 : 0.45)], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(colors: Self.stops(backdrop, base: theme?.color("background", dark: dark)),
                              startPoint: .topLeading, endPoint: .bottomTrailing)
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
