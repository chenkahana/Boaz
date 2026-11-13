#if BOAZ_CHROMIUM
import Foundation

enum ProtectedMediaService {
    enum KeySystem: Sendable { case widevine, playReady, fairPlay, clearKey }
    static let widevineAvailable = false
}
#endif
