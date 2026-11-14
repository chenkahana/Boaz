#if BOAZ_CHROMIUM
import Foundation

@MainActor
enum ChromiumEnginePreferences {
    private(set) static var revision: UInt64 = 0

    static func rulesDidChange() { revision &+= 1 }
}
#endif
