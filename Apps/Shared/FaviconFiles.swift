import BoazKit
import Foundation

/// Where favicons are kept on disk, one PNG per host. On iPhone that's the App Group's caches, so the widget can show
/// the same icons as the app; elsewhere it's the app's own caches.
enum FaviconFiles {
    static let directory: URL? = {
        #if os(iOS)
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BoazStore.appGroup)?
            .appendingPathComponent("Library/Caches/Favicons", isDirectory: true)
        #else
        (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))?
            .appendingPathComponent("Favicons", isDirectory: true)
        #endif
    }()

    static func file(host: String) -> URL? {
        directory?.appendingPathComponent(host.replacingOccurrences(of: "/", with: "_")).appendingPathExtension("png")
    }
}
