import CoreGraphics

/// Corner radii for the Mac chrome, so rows, tiles, cards and panels nest consistently.
enum MacRadius {
    static let icon: CGFloat = 6
    static let row: CGFloat = 8
    static let tile: CGFloat = 10
    static let card: CGFloat = 12
    static let panel: CGFloat = 16
}
