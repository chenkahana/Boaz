import UIKit

/// Tab previews kept in Caches, so cards still show each page after a relaunch. Local only: never synced, private
/// tabs are never written, and the system may empty the folder whenever it needs the space.
enum SnapshotCache {
    nonisolated private static var folder: URL {
        URL.cachesDirectory.appending(path: "Snapshots", directoryHint: .isDirectory)
    }

    nonisolated private static func file(for tabID: String) -> URL { folder.appending(path: tabID) }

    static func save(_ data: Data, for tabID: String) {
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: file(for: tabID), options: .atomic)
        }
    }

    static func remove(_ tabID: String) {
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: file(for: tabID)) }
    }

    /// The saved previews of `tabIDs`. Every other tab's file (archived or removed meanwhile) is deleted.
    static func load(keeping tabIDs: Set<String>) async -> [String: UIImage] {
        await Task.detached(priority: .utility) {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            var images: [String: UIImage] = [:]
            for file in files {
                if tabIDs.contains(file.lastPathComponent), let image = UIImage(contentsOfFile: file.path) {
                    images[file.lastPathComponent] = image
                } else {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            return images
        }.value
    }
}
