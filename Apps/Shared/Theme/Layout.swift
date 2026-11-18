import CoreGraphics

/// Boaz's spacing scale (docs/design.md), the same on both platforms.
enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let m: CGFloat = 8
    static let l: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let xxxl: CGFloat = 24
    static let section: CGFloat = 32
}

/// Corner radii, smallest to largest, so icons, rows, tiles, cards and panels nest consistently. Sheets keep the
/// system's corners. Always drawn `.continuous`.
enum Radius {
    #if os(macOS)
    static let icon: CGFloat = 6
    static let row: CGFloat = 8
    static let tile: CGFloat = 10
    static let card: CGFloat = 12
    static let panel: CGFloat = 16
    #else
    static let icon: CGFloat = 8
    static let row: CGFloat = 12
    static let tile: CGFloat = 16
    static let card: CGFloat = 20
    static let panel: CGFloat = 28
    #endif

    /// The concentric rule: a container inset inside another takes the outer radius less the inset, rounded to the
    /// nearest token and never above the outer.
    static func concentric(in outer: CGFloat, inset: CGFloat) -> CGFloat {
        let ideal = max(outer - inset, 0)
        return [icon, row, tile, card, panel].filter { $0 <= outer }.min { abs($0 - ideal) < abs($1 - ideal) } ?? ideal
    }
}
