#if BOAZ_CHROMIUM
import BoazKit
import Foundation

@MainActor
enum ChromiumEnginePreferences {
    private(set) static var revision: UInt64 = 0

    private static func key(_ profileID: String) -> String {
        "boaz.chromium.engine.default." + Data(profileID.utf8).base64EncodedString()
    }

    static func defaultEngine(profileID: String) -> StoredBrowserEngine {
        UserDefaults.standard.string(forKey: key(profileID)).flatMap(StoredBrowserEngine.init(rawValue:)) ?? .chromium
    }

    static func setDefaultEngine(_ engine: StoredBrowserEngine, profileID: String) {
        guard !profileID.isEmpty, defaultEngine(profileID: profileID) != engine else { return }
        UserDefaults.standard.set(engine.rawValue, forKey: key(profileID))
        rulesDidChange()
    }

    static func rulesDidChange() { revision &+= 1 }
}
#endif
