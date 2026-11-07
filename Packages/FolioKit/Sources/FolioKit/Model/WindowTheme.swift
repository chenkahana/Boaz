import Foundation

/// Arc's `windowTheme` format, shared by Arc desktop (per space) and Arc Search (per app icon).
/// Only the palettes are typed; the `background` gradient is a deeply nested enum encoding that
/// stays in the raw JSON (`Space.themeJSON`) until the renderer needs it.
public struct WindowTheme: Codable, Hashable, Sendable {
    public struct RGBA: Codable, Hashable, Sendable {
        public var colorSpace: String?
        public var red: Double
        public var green: Double
        public var blue: Double
        public var alpha: Double
    }

    public struct SemanticPalette: Codable, Hashable, Sendable {
        /// Keyed by appearance ("light", "dark"), then by role ("background", "foregroundPrimary", "title", …).
        public var appearanceBased: [String: [String: RGBA]]?
    }

    public var semanticColorPalette: SemanticPalette?
    /// Keyed by tone ("tintedLight", "midTone", "shaded", "shadedDark", …).
    public var primaryColorPalette: [String: RGBA]?

    public static func decode(_ data: Data) throws -> WindowTheme {
        try JSONDecoder().decode(WindowTheme.self, from: data)
    }

    public func color(_ role: String, dark: Bool) -> RGBA? {
        semanticColorPalette?.appearanceBased?[dark ? "dark" : "light"]?[role]
    }
}
