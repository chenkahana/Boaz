import SwiftUI

/// Palette lives in Assets.xcassets/Palette (light + dark variants).
/// Values follow Arc Search's shipped palette: brand blue #3139FB, a 12-step indigo scale, peach→blue gradients.
enum Theme {
    private static func palette(_ name: String) -> Color {
        #if BOAZ_CHROMIUM
        Color(name, bundle: BoazRuntimeResources.bundle)
        #else
        Color(name)
        #endif
    }

    static func indigo(_ step: Int) -> Color { palette("Palette/Indigo\(step)") }

    static let brand = palette("Palette/Brand")
    static let peach = palette("Palette/Peach")
    static let electric = palette("Palette/Electric")
    static let violet = palette("Palette/Violet")
    static let yellow = palette("Palette/Yellow")

    static let background = palette("Palette/Background")
    static let textPrimary = palette("Palette/TextPrimary")
    static let textSecondary = palette("Palette/TextSecondary")
    static let textTertiary = palette("Palette/TextTertiary")
    static let hairline = palette("Palette/Hairline")
    static let card = palette("Palette/CardBackground")
    static let cardStroke = palette("Palette/CardStroke")

    /// Signature diagonal wash used behind search and onboarding. Ends in Indigo 12's light-mode navy in both
    /// appearances: its dark-mode value is near white, which white text on the wash can't be read against.
    static let hero = LinearGradient(colors: [peach, brand, Color(.sRGB, red: 16 / 255, green: 18 / 255, blue: 69 / 255)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)

    /// Glow used for loading and the fold crease.
    static let glow = LinearGradient(colors: [peach, violet, electric],
                                     startPoint: .leading, endPoint: .trailing)

    static let cornerRadius: CGFloat = 18

    /// iOS corner radii, smallest to largest, so rows, tiles and cards nest consistently.
    enum Radius {
        static let row: CGFloat = 12
        static let tile: CGFloat = 18
        static let card: CGFloat = 20
        static let sheet: CGFloat = 30
    }
}

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Theme.card, in: .rect(cornerRadius: Theme.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).stroke(Theme.cardStroke))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}
