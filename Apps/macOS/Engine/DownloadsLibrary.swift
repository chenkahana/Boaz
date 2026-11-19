import AppKit
import BoazKit
import Foundation
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// One file under the downloads folder, as shown in the Library panel's Downloads pane.
struct LibraryDownloadItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let size: Int64
    /// When Finder considers the file "added" to the folder (falls back to its modification date).
    let dateAdded: Date
    let contentType: UTType?
    /// The download's source host, read from `kMDItemWhereFroms` (Safari/WebKit and Chromium both write it).
    let sourceHost: String?

    var kindDescription: String { contentType?.localizedDescription ?? "Document" }
    /// "<Kind> from <host>" when the source is known, else just the kind — matches Arc's subtitle.
    var subtitle: String {
        guard let sourceHost else { return kindDescription }
        return "\(kindDescription) from \(sourceHost)"
    }
}

/// The Library panel's Filter menu: broad kinds a downloaded file can be grouped under.
enum DownloadsFilter: String, CaseIterable, Identifiable {
    case all, images, pdfs, documents, diskImages, archives, video, audio
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .images: "Images"
        case .pdfs: "PDFs"
        case .documents: "Documents"
        case .diskImages: "Disk Images"
        case .archives: "Archives"
        case .video: "Video"
        case .audio: "Audio"
        }
    }

    func matches(_ type: UTType?) -> Bool {
        guard self != .all else { return true }
        guard let type else { return false }
        switch self {
        case .all: return true
        case .images: return type.conforms(to: .image)
        case .pdfs: return type.conforms(to: .pdf)
        case .diskImages: return type.conforms(to: .diskImage)
        case .archives: return type.conforms(to: .archive) || type.conforms(to: .zip)
        case .video: return type.conforms(to: .movie)
        case .audio: return type.conforms(to: .audio)
        case .documents:
            return !type.conforms(to: .pdf) && !type.conforms(to: .archive) && !type.conforms(to: .zip)
                && !type.conforms(to: .image) && !type.conforms(to: .movie) && !type.conforms(to: .audio)
                && !type.conforms(to: .diskImage)
        }
    }
}

/// Scans the downloads folder (`UITestMode.downloadsDirectory` in UI tests, else `Downloads.directory()`) and
/// watches it for changes, so the Library panel's Downloads and Media panes stay live.
@MainActor @Observable
final class DownloadsLibraryModel {
    private(set) var items: [LibraryDownloadItem] = []
    /// Whether the first scan has landed, so the panes don't flash their empty state before it.
    private(set) var loaded = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var reloadTask: Task<Void, Never>?

    var directory: URL? { UITestMode.downloadsDirectory ?? (try? Downloads.directory()) }

    deinit { watcher?.cancel() }

    /// The first scan and the folder watch. Called from the panel's `.task`, not `init`: SwiftUI makes (and throws
    /// away) a new `@State` model every time the panel's parent re-renders.
    func start() {
        guard !started else { return }
        started = true
        reload()
        startWatching()
    }

    /// Rescans off the main thread: the folder can hold thousands of files, each with an extended attribute to read.
    func reload() {
        guard let directory else { items = []; loaded = true; return }
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            let items = await Task.detached(priority: .userInitiated) { Self.scan(directory) }.value
            guard !Task.isCancelled, let self else { return }
            self.items = items
            self.loaded = true
        }
    }

    private func startWatching() {
        guard let directory else { return }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete],
                                                               queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleReload() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    /// Debounced: a browser download writes the file in several steps (a `.crdownload`/`.download` rename on
    /// completion), so one burst of filesystem events should produce one rescan.
    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    nonisolated private static func scan(_ directory: URL) -> [LibraryDownloadItem] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .addedToDirectoryDateKey,
                                         .contentTypeKey, .isDirectoryKey, .isHiddenKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys),
                                                                  options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url -> LibraryDownloadItem? in
            guard let values = try? url.resourceValues(forKeys: keys), values.isDirectory != true else { return nil }
            // In-progress browser downloads keep a partial-download extension; hide them until they land.
            let ext = url.pathExtension.lowercased()
            guard ext != "crdownload", ext != "download" else { return nil }
            return LibraryDownloadItem(url: url, name: url.lastPathComponent, size: Int64(values.fileSize ?? 0),
                                       dateAdded: values.addedToDirectoryDate ?? values.contentModificationDate ?? .now,
                                       contentType: values.contentType, sourceHost: whereFromHost(url))
        }
        .sorted { $0.dateAdded > $1.dateAdded }
    }

    /// The first `kMDItemWhereFroms` URL's host, from the `com.apple.metadata:kMDItemWhereFroms` extended
    /// attribute WebKit and Chromium both write (a binary-plist array of strings: usually `[sourceURL, referrer]`).
    nonisolated private static func whereFromHost(_ url: URL) -> String? {
        guard let data = try? url.extendedAttribute(named: "com.apple.metadata:kMDItemWhereFroms"),
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String]
        else { return nil }
        for value in values {
            if let host = URL(string: value)?.host, !host.isEmpty { return host }
        }
        return nil
    }
}

extension URL {
    /// Reads an extended attribute (e.g. `com.apple.metadata:kMDItemWhereFroms`) by name.
    nonisolated func extendedAttribute(named name: String) throws -> Data {
        let length = withUnsafeFileSystemRepresentation { getxattr($0, name, nil, 0, 0, 0) }
        guard length >= 0 else { throw CocoaError(.fileReadUnknown) }
        var data = Data(count: length)
        let read = data.withUnsafeMutableBytes { buffer in
            withUnsafeFileSystemRepresentation { getxattr($0, name, buffer.baseAddress, length, 0, 0) }
        }
        guard read >= 0 else { throw CocoaError(.fileReadUnknown) }
        return data
    }
}

/// A calendar day's section title relative to now, the way Arc's Library buckets downloads ("Today",
/// "3 weeks ago", "1 month ago", …).
func relativeLibrarySection(for date: Date, now: Date = .now) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return "Today" }
    if calendar.isDateInYesterday(date) { return "Yesterday" }
    let start = calendar.startOfDay(for: date)
    let today = calendar.startOfDay(for: now)
    let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
    if days < 7 { return "\(days) days ago" }
    if days < 35 {
        let weeks = days / 7
        return String(inflecting: "^[\(weeks) week](inflect: true) ago")
    }
    let months = max(calendar.dateComponents([.month], from: start, to: today).month ?? 1, 1)
    if months < 12 { return String(inflecting: "^[\(months) month](inflect: true) ago") }
    let years = max(calendar.dateComponents([.year], from: start, to: today).year ?? 1, 1)
    return String(inflecting: "^[\(years) year](inflect: true) ago")
}

/// Caches `QLThumbnailGenerator` output per file so re-rendering a row (scrolling, filtering) doesn't regenerate it.
@MainActor
final class DownloadThumbnailCache {
    static let shared = DownloadThumbnailCache()
    private var cache = NSCache<NSURL, NSImage>()
    func cached(for url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: NSImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

/// A download row's thumbnail: a `QLThumbnailGenerator` render of the file, falling back to a generic icon
/// while it loads or if generation fails.
struct DownloadThumbnail: View {
    let url: URL
    var size: CGFloat = 32
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.primary.opacity(0.06))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: "doc").foregroundStyle(.secondary).font(.system(size: size * 0.4))
            }
        }
        .frame(width: size, height: size)
        .task(id: url) { await load() }
    }

    private func load() async {
        if let cached = DownloadThumbnailCache.shared.cached(for: url) { image = cached; return }
        let scale = 2.0
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                    scale: scale, representationTypes: .thumbnail)
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
        else { return }
        let nsImage = representation.nsImage
        DownloadThumbnailCache.shared.store(nsImage, for: url)
        if !Task.isCancelled { image = nsImage }
    }
}
