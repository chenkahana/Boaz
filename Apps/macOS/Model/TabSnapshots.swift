#if BOAZ_CHROMIUM
import Foundation

/// The last look of each tab, kept on disk so a tab that comes back after an unload or a relaunch shows it while its
/// page loads. A cache, never the library: under Caches, per profile, at most `budget` bytes each (least recently
/// written go first), never synced, and never written for Incognito tabs (the caller keeps those in memory only).
nonisolated enum TabSnapshots {
    static let budget = 200 * 1024 * 1024

    private static let root: URL? = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                                  appropriateFor: nil, create: true))?
        .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.chenkahana.boaz", isDirectory: true)
        .appendingPathComponent("TabSnapshots", isDirectory: true)

    private static let queue = DispatchQueue(label: "com.chenkahana.boaz.tab-snapshots", qos: .utility)

    private static func directory(_ profileID: String?) -> URL? {
        root?.appendingPathComponent(safe(profileID ?? "default"), isDirectory: true)
    }

    private static func safe(_ name: String) -> String {
        String(name.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" })
    }

    private static func files(_ tabID: String, _ profileID: String?) -> (image: URL, page: URL)? {
        guard let directory = directory(profileID) else { return nil }
        let base = directory.appendingPathComponent(safe(tabID))
        return (base.appendingPathExtension("png"), base.appendingPathExtension("url"))
    }

    /// Writes `png` as `tabID`'s look of `url`, then trims the profile's snapshots to the budget.
    static func save(_ png: Data, tabID: String, url: URL, profileID: String?) {
        queue.async {
            guard let files = files(tabID, profileID), let directory = directory(profileID) else { return }
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard (try? png.write(to: files.image, options: .atomic)) != nil,
                  (try? Data(url.absoluteString.utf8).write(to: files.page, options: .atomic)) != nil else { return }
            trim(directory)
        }
    }

    /// `tabID`'s saved look, if it shows `url`; one that shows another page is out of date and goes.
    static func load(tabID: String, url: URL, profileID: String?) async -> Data? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let files = files(tabID, profileID),
                      let saved = try? String(contentsOf: files.page, encoding: .utf8) else {
                    return continuation.resume(returning: nil)
                }
                guard saved == url.absoluteString else {
                    remove(files)
                    return continuation.resume(returning: nil)
                }
                continuation.resume(returning: try? Data(contentsOf: files.image))
            }
        }
    }

    static func remove(tabID: String, profileID: String?) {
        queue.async { files(tabID, profileID).map(remove) }
    }

    private static func remove(_ files: (image: URL, page: URL)) {
        try? FileManager.default.removeItem(at: files.image)
        try? FileManager.default.removeItem(at: files.page)
    }

    private static func trim(_ directory: URL) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let images = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
            .filter({ $0.pathExtension == "png" }) else { return }
        var entries = images.compactMap { url -> (url: URL, date: Date, size: Int)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        entries.sort { $0.date < $1.date }
        for entry in entries where total > budget {
            remove((entry.url, entry.url.deletingPathExtension().appendingPathExtension("url")))
            total -= entry.size
        }
    }
}
#endif
