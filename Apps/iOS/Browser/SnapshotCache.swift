import UIKit

/// Tab previews kept in Caches, so cards still show each page after a relaunch. Local only: never synced, private
/// tabs are never written, and the system may empty the folder whenever it needs the space.
enum SnapshotCache {
    nonisolated private static var folder: URL {
        URL.cachesDirectory.appending(path: "Snapshots", directoryHint: .isDirectory)
    }

    /// Saves and removals run in order, so a tab closed right after its preview was taken leaves no file behind.
    nonisolated private static let queue = DispatchQueue(label: "com.chenkahana.boaz.snapshots", qos: .utility)

    /// Nil unless the id is a plain file name: ids from a synced folder's JSON can't be trusted to stay in `folder`.
    nonisolated private static func file(for tabID: String) -> URL? {
        guard !tabID.isEmpty, !tabID.contains("/"), tabID != ".", tabID != ".." else { return nil }
        return folder.appending(path: tabID)
    }

    static func save(_ data: Data, for tabID: String) {
        guard let file = file(for: tabID) else { return }
        queue.async {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    static func remove(_ tabID: String) {
        guard let file = file(for: tabID) else { return }
        queue.async { try? FileManager.default.removeItem(at: file) }
    }

    /// The saved previews of `tabIDs`. Other tabs' files (archived or removed meanwhile) are deleted, except those
    /// written since `cutoff`: they belong to tabs opened after `tabIDs` was read. Runs in turn with saves and removals.
    static func load(keeping tabIDs: Set<String>, writtenBefore cutoff: Date) async -> [String: UIImage] {
        await withCheckedContinuation { continuation in
            queue.async {
                let files = (try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                var images: [String: UIImage] = [:]
                for file in files {
                    if tabIDs.contains(file.lastPathComponent), let image = UIImage(contentsOfFile: file.path) {
                        images[file.lastPathComponent] = image
                    } else if let written = try? file.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate, written < cutoff {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
                continuation.resume(returning: images)
            }
        }
    }
}
