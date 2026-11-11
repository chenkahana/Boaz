import Foundation

/// Arc's `windowTheme` format, shared by Arc desktop (per space) and Arc Search (per app icon).
/// The palettes are decoded with `Codable`; the `background` (a nested Swift-enum encoding) is read leniently
/// by `decode(_:)`, so an unfamiliar background never costs a space its palettes.
public struct WindowTheme: Codable, Hashable, Sendable {
    public struct RGBA: Codable, Hashable, Sendable {
        public var colorSpace: String?
        public var red: Double
        public var green: Double
        public var blue: Double
        public var alpha: Double

        public init(colorSpace: String? = "extendedSRGB", red: Double, green: Double, blue: Double, alpha: Double = 1) {
            self.colorSpace = colorSpace; self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
        }
    }

    public struct SemanticPalette: Codable, Hashable, Sendable {
        /// Keyed by appearance ("light", "dark"), then by role ("background", "foregroundPrimary", "title", …).
        public var appearanceBased: [String: [String: RGBA]]?
    }

    /// How Arc paints a space's window behind the sidebar for one appearance.
    public struct Backdrop: Hashable, Sendable {
        /// One color (`blendedSingleColor`, `basicColor`) or a gradient's base colors (`blendedGradient`).
        public var colors: [RGBA]
        /// Arc's `noiseFactor`, 0…1: how strongly the `overlay` texture ("grain", "sand", …) shows.
        public var noise: Double
        public var overlay: String?
        /// "light" or "dark": the appearance Arc draws sidebar content in over this backdrop.
        public var contentAppearance: String?
        public var isVibrant: Bool
    }

    public var semanticColorPalette: SemanticPalette?
    /// Keyed by tone ("tintedLight", "midTone", "shaded", "shadedDark", …).
    public var primaryColorPalette: [String: RGBA]?
    /// From `background.single` (one backdrop, both appearances) or `background.appearanceBased`.
    public var lightBackdrop: Backdrop?
    public var darkBackdrop: Backdrop?
    /// Set when the theme pins its space to one appearance: Arc's `single` backgrounds (and `windowAppearance`
    /// "light"/"dark") ignore the system setting. Nil follows the system.
    public var fixedAppearance: String?
    /// Boaz's own options (`boazGrain`, `boazLightStreak`): the grain texture and the light from the top corner
    /// show only when a theme turns them on.
    public var showsGrain = false
    public var showsLightStreak = false

    enum CodingKeys: String, CodingKey { case semanticColorPalette, primaryColorPalette }

    public static func decode(_ data: Data) throws -> WindowTheme {
        var theme = try JSONDecoder().decode(WindowTheme.self, from: data)
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            theme.readBackground(root)
            theme.showsGrain = root["boazGrain"] as? Bool ?? false
            theme.showsLightStreak = root["boazLightStreak"] as? Bool ?? false
        }
        return theme
    }

    public func color(_ role: String, dark: Bool) -> RGBA? {
        semanticColorPalette?.appearanceBased?[dark ? "dark" : "light"]?[role]
    }

    public func backdrop(dark: Bool) -> Backdrop? { dark ? darkBackdrop : lightBackdrop }

    // MARK: Background

    /// `{"single": {"_0": spec}}` or `{"appearanceBased": {"light": spec, "dark": spec}}`, where a spec is
    /// `{"style": {"color": {"_0": {"blendedSingleColor" | "blendedGradient" | "basicColor": {"_0": …}}}}, …}`.
    private mutating func readBackground(_ root: [String: Any]) {
        let background = root["background"] as? [String: Any]
        if let single = (background?["single"] as? [String: Any])?["_0"] as? [String: Any], let backdrop = Self.backdrop(single) {
            lightBackdrop = backdrop; darkBackdrop = backdrop
            fixedAppearance = backdrop.contentAppearance
        } else if let both = background?["appearanceBased"] as? [String: Any] {
            lightBackdrop = (both["light"] as? [String: Any]).flatMap(Self.backdrop)
            darkBackdrop = (both["dark"] as? [String: Any]).flatMap(Self.backdrop)
        }
        // Boaz writes "system" to follow the system again, even over a single backdrop.
        if let appearance = root["windowAppearance"] as? String, ["light", "dark", "system"].contains(appearance) {
            fixedAppearance = appearance == "system" ? nil : appearance
        }
    }

    private static func backdrop(_ spec: [String: Any]) -> Backdrop? {
        guard let style = ((spec["style"] as? [String: Any])?["color"] as? [String: Any])?["_0"] as? [String: Any]
        else { return nil }
        var colors: [RGBA] = []
        var modifiers: [String: Any]?
        if let single = (style["blendedSingleColor"] as? [String: Any])?["_0"] as? [String: Any] {
            colors = rgba(single["color"]).map { [$0] } ?? []
            modifiers = single["modifiers"] as? [String: Any]
        } else if let gradient = (style["blendedGradient"] as? [String: Any])?["_0"] as? [String: Any] {
            colors = (gradient["baseColors"] as? [Any] ?? []).compactMap(rgba)
            modifiers = gradient["modifiers"] as? [String: Any]
        } else if let basic = (style["basicColor"] as? [String: Any])?["_0"] {
            colors = rgba(basic).map { [$0] } ?? []
        }
        guard !colors.isEmpty else { return nil }
        let appearance = spec["contentOverBackgroundAppearance"] as? String
        return Backdrop(colors: colors, noise: modifiers?["noiseFactor"] as? Double ?? 0,
                        overlay: modifiers?["overlay"] as? String,
                        contentAppearance: ["light", "dark"].contains(appearance ?? "") ? appearance : nil,
                        isVibrant: spec["isVibrant"] as? Bool ?? false)
    }

    private static func rgba(_ value: Any?) -> RGBA? {
        guard let value = value as? [String: Any], let r = value["red"] as? Double, let g = value["green"] as? Double,
              let b = value["blue"] as? Double else { return nil }
        return RGBA(colorSpace: value["colorSpace"] as? String, red: r, green: g, blue: b, alpha: value["alpha"] as? Double ?? 1)
    }
}
