#if BOAZ_CHROMIUM
import Foundation

enum ProtectedMediaService {
    enum KeySystem: Sendable { case widevine, playReady, fairPlay, clearKey }
    /// Chromium answers Widevine itself once the build registers Google's component and its CDM passes the signature check.
    @MainActor static var widevineAvailable: Bool { (try? ChromiumRuntime.widevineVersion()) != nil }
}
#endif
