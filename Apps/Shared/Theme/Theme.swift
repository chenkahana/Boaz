import SwiftUI

/// Palette lives in Assets.xcassets/Palette (light + dark variants).
/// Values follow Arc Search's shipped palette: brand blue #3139FB, a 12-step indigo scale, peach→blue gradients.
enum Theme {
    static func indigo(_ step: Int) -> Color { Color("Palette/Indigo\(step)") }

    static let brand = Color("Palette/Brand")
    static let peach = Color("Palette/Peach")
    static let electric = Color("Palette/Electric")
    static let violet = Color("Palette/Violet")
    static let yellow = Color("Palette/Yellow")

    static let background = Color("Palette/Background")
    static let textPrimary = Color("Palette/TextPrimary")
    static let textSecondary = Color("Palette/TextSecondary")
    static let textTertiary = Color("Palette/TextTertiary")
    static let hairline = Color("Palette/Hairline")
    static let card = Color("Palette/CardBackground")
    static let cardStroke = Color("Palette/CardStroke")

    /// Signature diagonal wash used behind search and onboarding.
    static let hero = LinearGradient(colors: [peach, brand, indigo(12)],
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
