import FolioKit
import SwiftUI

extension WindowTheme.RGBA {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

/// Renders a space's Arc theme. Falls back to Folio's indigo palette when a space has no theme.
struct SpaceStyle {
    let theme: WindowTheme?
    let dark: Bool

    init(_ space: Space?, scheme: ColorScheme) {
        theme = space?.theme
        dark = scheme == .dark
    }

    var background: Color { theme?.color("background", dark: dark)?.color.opacity(1) ?? Theme.indigo(3) }
    var tint: Color { theme?.primaryColorPalette?["midTone"]?.color ?? Theme.brand }
    var foreground: Color { theme?.color("foregroundPrimary", dark: dark)?.color ?? Theme.textPrimary }

    var gradient: LinearGradient {
        LinearGradient(colors: [background, tint.opacity(dark ? 0.55 : 0.45)], startPoint: .top, endPoint: .bottom)
    }
}
