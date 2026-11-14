#if BOAZ_CHROMIUM
import Foundation

struct ChromiumMedia: Equatable {
    enum MediaType: Int32, CaseIterable { case screen, print }
    enum Preference: Int32, CaseIterable { case system, first, second }
    enum Vision: Int32, CaseIterable {
        case none, blurred, reducedContrast, achromatopsia, deuteranopia, protanopia, tritanopia
        var title: String {
            switch self {
            case .none: "None"
            case .blurred: "Blurred vision"
            case .reducedContrast: "Reduced contrast"
            case .achromatopsia: "Achromatopsia"
            case .deuteranopia: "Deuteranopia"
            case .protanopia: "Protanopia"
            case .tritanopia: "Tritanopia"
            }
        }
    }
    var type = MediaType.screen
    var colorScheme = Preference.system
    var reducedMotion = Preference.system
    var contrast = Preference.system
    var forcedColors = false
    var vision = Vision.none

    var native: BoazHostMedia {
        BoazHostMedia(type: type.rawValue, color_scheme: colorScheme.rawValue,
            reduced_motion: reducedMotion.rawValue, contrast: contrast.rawValue,
            vision: vision.rawValue, forced_colors: forcedColors ? 1 : 0)
    }
}
#endif
