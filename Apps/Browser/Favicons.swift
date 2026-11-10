import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#else
import AppKit
public typealias PlatformImage = NSImage
#endif

extension Image {
    init(platformImage image: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: image)
        #else
        self.init(nsImage: image)
        #endif
    }
}

/// Per-host favicon cache shared by iOS's `Monogram` and macOS's `SiteMonogram`. An icon is either
/// learned from a page's own markup once it loads, or — for a pinned/favorite tile that hasn't loaded
/// yet — fetched directly from the site's well-known icon paths. No third-party favicon service, so no
/// browsing data ever leaves the device for an icon we can't resolve ourselves.
@Observable
final class Favicons {
    static let shared = Favicons()

    /// For `page.callJavaScript`, which runs this as a function BODY (no implicit return, and no outer
    /// `(function(){...})()` wrapper — see the note on `Reader.lengthEstimateScript`). Picks the
    /// `link[rel~=icon]` / `apple-touch-icon` with the largest declared `sizes`.
    static let discoveryScript = """
    var links = document.querySelectorAll("link[rel~='icon'], link[rel~='apple-touch-icon']");
    var best = null, bestSize = 0;
    for (var i = 0; i < links.length; i++) {
      var href = links[i].getAttribute('href');
      if (!href) continue;
      var rel = (links[i].getAttribute('rel') || '').toLowerCase();
      var match = (links[i].getAttribute('sizes') || '').match(/(\\d+)x(\\d+)/);
      var size = match ? parseInt(match[1], 10) : (rel.indexOf('apple-touch-icon') !== -1 ? 180 : 32);
      if (size > bestSize) { bestSize = size; best = href; }
    }
    return best;
    """

    /// Observed per host, so an icon arriving redraws only the tiles showing that site.
    @ObservationIgnored private let resolved = ObservedDictionary<String, PlatformImage>()

    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var negativeCache: [String: Date] = [:]
    @ObservationIgnored private let diskDirectory: URL?
    @ObservationIgnored private let gate = FetchGate(permits: 4)
    private let negativeCacheLifetime: TimeInterval = 86_400

    private init() {
        diskDirectory = (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true))
            .map { $0.appendingPathComponent("Favicons", isDirectory: true) }
        if let diskDirectory {
            try? FileManager.default.createDirectory(at: diskDirectory, withIntermediateDirectories: true)
        }
    }

    private static func hostKey(_ url: URL?) -> String? {
        guard let host = url?.host()?.lowercased(), !host.isEmpty else { return nil }
        return host
    }

    /// Already-known icon for `url`'s host. Reading this in a view body is tracked reactively, so a tile
    /// redraws once `request`/`learn` resolves (or a disk load completes).
    @ObservationIgnored private var learned: [String: URL] = [:]

    func resolved(for url: URL?) -> PlatformImage? {
        Self.hostKey(url).flatMap { resolved[$0] }
    }

    /// Kicks off a lookup for `url`'s host if nothing is cached, already in flight, or recently failed.
    /// Checks disk before spending a network round trip, then tries `apple-touch-icon.png` and
    /// `favicon.ico` directly. Safe to call on every render — it no-ops once a result (or a miss) is known.
    /// In private browsing it only reads what's already cached: no request goes out and nothing is written,
    /// so private hosts leave no trace on disk.
    func request(_ url: URL?, isPrivate: Bool = false) {
        guard let host = Self.hostKey(url), resolved[host] == nil, !inFlight.contains(host) else { return }
        if !isPrivate, let missedAt = negativeCache[host], Date().timeIntervalSince(missedAt) < negativeCacheLifetime {
            return
        }
        inFlight.insert(host)
        Task { [weak self] in
            guard let self else { return }
            defer { self.inFlight.remove(host) }
            if let onDisk = await self.loadFromDisk(host: host) {
                self.resolved[host] = onDisk
                return
            }
            guard !isPrivate else { return }
            guard let image = await self.fetchWellKnownIcon(host: host) else {
                self.negativeCache[host] = .now
                return
            }
            self.keep(image, for: host)
        }
    }

    /// Called from the page-load-finished hooks with the icon URL scraped from the loaded page's markup.
    /// Skipped for private tabs so nothing learned from a private page reaches the shared cache.
    func learn(iconURL: URL, forPageAt pageURL: URL, isPrivate: Bool) {
        // Only public https icons, and each one once: every page load on a site reports the same icon.
        guard !isPrivate, iconURL.scheme == "https", let host = Self.hostKey(pageURL),
              learned[host] != iconURL else { return }
        learned[host] = iconURL
        Task { [weak self] in
            guard let self, let image = await self.download(iconURL) else { return }
            self.keep(image, for: host)
        }
    }

    /// Holds a downloaded icon at the size it's saved at, not the full download (touch icons run to 512 px).
    private func keep(_ image: PlatformImage, for host: String) {
        let small = Self.downscaled(image, maxDimension: 128)
        resolved[host] = small
        negativeCache[host] = nil
        saveToDisk(small, host: host)
    }

    /// Seeds the cache with an icon another browser already had for `pageURL` (Arc import), so imported tabs
    /// show their real icons before they ever load. Never replaces an icon Boaz already has for the host.
    func seed(_ data: Data, for pageURL: URL) {
        guard let host = Self.hostKey(pageURL), resolved[host] == nil, let file = diskURL(host: host),
              !FileManager.default.fileExists(atPath: file.path),
              let image = PlatformImage(data: data), Self.isUsable(image) else { return }
        try? data.write(to: file, options: .atomic)
        resolved[host] = Self.downscaled(image, maxDimension: 128)
        negativeCache[host] = nil
    }

    private func fetchWellKnownIcon(host: String) async -> PlatformImage? {
        for path in ["apple-touch-icon.png", "favicon.ico"] {
            guard let url = URL(string: "https://\(host)/\(path)"), let image = await download(url) else { continue }
            return image
        }
        return nil
    }

    private func download(_ url: URL) async -> PlatformImage? {
        await Self.usableIcon(at: url, gate: gate).flatMap(PlatformImage.init(data:))
    }

    /// The icon's data if it decodes to something worth showing. Fetching and checking it (which copies the whole
    /// bitmap) stay off the main thread.
    nonisolated private static func usableIcon(at url: URL, gate: FetchGate) async -> Data? {
        await gate.wait()
        defer { gate.signal() }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count > 128, let image = PlatformImage(data: data), isUsable(image)
        else { return nil }
        return data
    }

    nonisolated private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    // MARK: Validity

    /// Rejects corrupt decodes, icons too small to bother with, and placeholder images that are
    /// effectively blank (sampled alpha channel comes back fully transparent).
    nonisolated private static func isUsable(_ image: PlatformImage) -> Bool {
        guard let cg = image.validationCGImage, cg.width >= 8, cg.height >= 8 else { return false }
        guard cg.bitsPerPixel == 32, let data = cg.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return true }
        let length = CFDataGetLength(data)
        guard length >= 4 else { return true }
        let stride = max(4, (length / 4 / 64) * 4)
        var index = 0
        while index + 3 < length {
            if bytes[index + 3] > 20 { return true }
            index += stride
        }
        return false
    }

    // MARK: Disk cache

    private func diskURL(host: String) -> URL? {
        diskDirectory?.appendingPathComponent(host.replacingOccurrences(of: "/", with: "_")).appendingPathExtension("png")
    }

    /// Reads the file off the main thread; the image decodes when it's first drawn.
    private func loadFromDisk(host: String) async -> PlatformImage? {
        guard let url = diskURL(host: host),
              let data = await Task.detached(priority: .utility, operation: { try? Data(contentsOf: url) }).value
        else { return nil }
        return PlatformImage(data: data)
    }

    private func saveToDisk(_ image: PlatformImage, host: String) {
        guard let url = diskURL(host: host), let data = Self.pngData(Self.downscaled(image, maxDimension: 128))
        else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Caps concurrent favicon network fetches (~4). A plain lock-based gate rather than an actor, so
/// `signal()` can run synchronously from a `defer`.
private nonisolated final class FetchGate: @unchecked Sendable {
    private let lock = NSLock()
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(permits: Int) { available = permits }

    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if available > 0 {
                available -= 1
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func signal() {
        lock.lock()
        if waiters.isEmpty {
            available += 1
            lock.unlock()
        } else {
            let waiter = waiters.removeFirst()
            lock.unlock()
            waiter.resume()
        }
    }
}

#if canImport(UIKit)
private extension PlatformImage {
    nonisolated var validationCGImage: CGImage? { cgImage }
}

private extension Favicons {
    static func downscaled(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height, 1))
        guard scale < 1 else { return image }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    static func pngData(_ image: UIImage) -> Data? { image.pngData() }
}
#else
private extension PlatformImage {
    nonisolated var validationCGImage: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

private extension Favicons {
    static func downscaled(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height, 1))
        guard scale < 1 else { return image }
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let scaled = NSImage(size: newSize)
        scaled.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size),
                   operation: .copy, fraction: 1)
        scaled.unlockFocus()
        return scaled
    }

    static func pngData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
#endif

/// Shared favicon rendering behind `Monogram` (iOS) and `SiteMonogram` (macOS): swaps in the site's real
/// icon once `Favicons` resolves one, fading in over the tinted letter-tile fallback. Small tiles keep
/// the icon centered on a subtle backing; large ones (touch-icon scale) let it fill the tile.
extension EnvironmentValues {
    /// Set on private (Incognito) browsing UI so favicons there never fetch or cache.
    @Entry var isPrivateBrowsing = false
}

struct FaviconTile: View {
    @Environment(\.isPrivateBrowsing) private var isPrivate
    let url: URL?
    let tint: Color
    let size: CGFloat
    var letterScale: CGFloat = 0.5

    private var isLarge: Bool { size >= 26 }
    private var cornerRadius: CGFloat { size * 0.28 }
    private var host: String { url?.host()?.replacingOccurrences(of: "www.", with: "") ?? "?" }

    var body: some View {
        let icon = Favicons.shared.resolved(for: url)
        ZStack {
            if let icon {
                // Only icons with enough pixels fill a large tile; a 32px favicon stretched that far goes soft.
                if isLarge, icon.size.width >= 64 {
                    Image(platformImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                } else {
                    if !isLarge { RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.quaternary) }
                    Image(platformImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size * (isLarge ? 0.7 : 0.62), height: size * (isLarge ? 0.7 : 0.62))
                }
            } else {
                Rectangle().fill(tint.gradient)
                Text(host.prefix(1).uppercased())
                    .font(.system(size: size * letterScale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.18), value: icon != nil)
        .task(id: url) { Favicons.shared.request(url, isPrivate: isPrivate) }
    }
}
