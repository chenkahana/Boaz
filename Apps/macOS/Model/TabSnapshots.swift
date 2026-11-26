#if BOAZ_CHROMIUM || TAB_SNAPSHOTS_TESTS
import Foundation

/// The last look of each tab, kept on disk so a tab that comes back after an unload or a relaunch shows it while its
/// page loads: an image, and for a page that had to close, the page itself as MHTML. A cache, never the library: under
/// Caches, per profile, at most `budget` bytes each (least recently written go first), never synced, and never written
/// for Incognito tabs (the caller keeps those in memory only).
nonisolated enum TabSnapshots {
    static let budget = 200 * 1024 * 1024
    /// A saved page larger than this isn't kept: reloading costs less than reading it back.
    static let largestArchive: Int64 = 50 * 1024 * 1024

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

    private struct Files {
        let image, page, archive, archivePage: URL
        init(_ base: URL) {
            image = base.appendingPathExtension("png")
            page = base.appendingPathExtension("url")
            archive = base.appendingPathExtension("mhtml")
            archivePage = base.appendingPathExtension("archive-url")
        }
        var all: [URL] { [image, page, archive, archivePage] }
    }

    private static func files(_ tabID: String, _ profileID: String?) -> Files? {
        directory(profileID).map { Files($0.appendingPathComponent(safe(tabID))) }
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
                    try? FileManager.default.removeItem(at: files.image)
                    try? FileManager.default.removeItem(at: files.page)
                    return continuation.resume(returning: nil)
                }
                continuation.resume(returning: try? Data(contentsOf: files.image))
            }
        }
    }

    /// Where `tabID`'s page is saved as MHTML (`ChromiumEnginePageAdapter.saveMHTML`), its directory made.
    static func archiveFile(tabID: String, profileID: String?) async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let directory = directory(profileID), let files = files(tabID, profileID),
                      (try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)) != nil
                else { return continuation.resume(returning: nil) }
                try? FileManager.default.removeItem(at: files.archivePage)
                continuation.resume(returning: files.archive)
            }
        }
    }

    /// The page saved to `archiveFile` shows `url`; nil `url` (a failed or oversized save) drops it.
    static func archived(tabID: String, url: URL?, size: Int64, profileID: String?) {
        queue.async {
            guard let files = files(tabID, profileID), let directory = directory(profileID) else { return }
            guard let url, size > 0, size <= largestArchive,
                  (try? Data(url.absoluteString.utf8).write(to: files.archivePage, options: .atomic)) != nil else {
                try? FileManager.default.removeItem(at: files.archive)
                try? FileManager.default.removeItem(at: files.archivePage)
                return
            }
            trim(directory)
        }
    }

    /// Takes `tabID`'s saved page for showing, if it shows `url`: it moves to a name of its own (`claim`), so it shows
    /// once, and the file the caller later drops (`dropClaimed`) is that one, never a page saved again since.
    static func claimArchive(tabID: String, url: URL, profileID: String?) async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async {
                guard let files = files(tabID, profileID) else { return continuation.resume(returning: nil) }
                continuation.resume(returning: claim(archive: files.archive, archivePage: files.archivePage, for: url))
            }
        }
    }

    /// Moves `archive` to a unique name beside it if `archivePage` says it shows `url`; otherwise, or if the move fails,
    /// both go. Either way the saved page is no longer there to be found again.
    static func claim(archive: URL, archivePage: URL, for url: URL) -> URL? {
        let manager = FileManager.default
        defer {
            try? manager.removeItem(at: archive)
            try? manager.removeItem(at: archivePage)
        }
        guard let saved = try? String(contentsOf: archivePage, encoding: .utf8), saved == url.absoluteString else {
            return nil
        }
        let claimed = archive.deletingPathExtension()
            .appendingPathExtension("shown-\(UUID().uuidString)").appendingPathExtension("mhtml")
        return (try? manager.moveItem(at: archive, to: claimed)) != nil ? claimed : nil
    }

    /// Removes a page taken by `claimArchive`.
    static func dropClaimed(_ file: URL) {
        queue.async { try? FileManager.default.removeItem(at: file) }
    }

    /// `tabID`'s saved page goes unshown: its page came back without it.
    static func dropArchive(tabID: String, profileID: String?) {
        queue.async {
            guard let files = files(tabID, profileID) else { return }
            try? FileManager.default.removeItem(at: files.archive)
            try? FileManager.default.removeItem(at: files.archivePage)
        }
    }

    static func remove(tabID: String, profileID: String?) {
        queue.async { files(tabID, profileID).map(remove) }
    }

    private static func remove(_ files: Files) {
        for file in files.all { try? FileManager.default.removeItem(at: file) }
    }

    private static func trim(_ directory: URL) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let saved = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
            .filter({ ["png", "mhtml"].contains($0.pathExtension) }) else { return }
        var entries = saved.compactMap { url -> (url: URL, date: Date, size: Int)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        entries.sort { $0.date < $1.date }
        for entry in entries where total > budget {
            let files = Files(entry.url.deletingPathExtension())
            try? FileManager.default.removeItem(at: entry.url)
            try? FileManager.default.removeItem(at: entry.url == files.image ? files.page : files.archivePage)
            total -= entry.size
        }
    }
}
#endif
