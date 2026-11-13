#if BOAZ_CHROMIUM
import Foundation

enum ProtectedMediaService {
    enum KeySystem { case widevine, playReady, fairPlay, clearKey }
    static let widevineAvailable = false
}
#endif
