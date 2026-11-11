import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// A site's icon, decoded once, with what it takes to draw it well.
struct Favicon: Sendable {
    let image: CGImage
    /// Opaque out to its edges, as most touch icons are: square artwork, drawn filling a rounded tile.
    let isFullBleed: Bool
    /// A mark that is nearly all near-black, so it disappears on a dark background.
    let isDark: Bool
    /// A mark that is nearly all near-white, so it disappears on a light background.
    let isLight: Bool

    /// Decodes the largest image in `data` (an .ico holds several sizes), at most `maxPixelSize` on a side. Nil for
    /// corrupt data, icons too small to bother with and blank placeholders.
    nonisolated init?(data: Data, maxPixelSize: Int = 128) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let widths = (0..<CGImageSourceGetCount(source)).map { index in
            (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth] as? Int ?? 0
        }
        guard let largest = widths.indices.max(by: { widths[$0] < widths[$1] }),
              let image = CGImageSourceCreateThumbnailAtIndex(source, largest, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
              ] as CFDictionary),
              image.width >= 8, image.height >= 8
        else { return nil }

        // Judged on a 16 × 16 copy: whether the edges are opaque, and how dark or light the opaque pixels are.
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        func alpha(_ x: Int, _ y: Int) -> Int { Int(pixels[(y * side + x) * 4 + 3]) }
        // The edges short of the corners, so artwork with rounded corners still counts as square.
        let edges = (2..<(side - 2)).flatMap { k in [alpha(k, 0), alpha(k, side - 1), alpha(0, k), alpha(side - 1, k)] }
        var opaque = 0, dark = 0, light = 0
        for index in stride(from: 0, to: pixels.count, by: 4) where pixels[index + 3] > 128 {
            let a = Int(pixels[index + 3])
            let channels = (0..<3).map { Int(pixels[index + $0]) * 255 / a }
            opaque += 1
            if channels.max()! < 80 { dark += 1 }
            if channels.min()! > 225 { light += 1 }
        }
        guard opaque > 0 else { return nil }
        self.image = image
        isFullBleed = edges.reduce(0, +) >= edges.count * 225
        isDark = !isFullBleed && dark * 10 >= opaque * 8
        isLight = !isFullBleed && light * 10 >= opaque * 8
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
    @ObservationIgnored private let resolved = ObservedDictionary<String, Favicon>()

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

    func resolved(for url: URL?) -> Favicon? {
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
            let onDisk = await self.loadFromDisk(host: host)
            if let onDisk { self.resolved[host] = onDisk }
            guard !isPrivate else { return }
            // Earlier builds kept the smallest image in an .ico, so a small one gets one look for a sharper icon.
            if let onDisk, onDisk.image.width >= 32 { return }
            guard let icon = await self.fetchWellKnownIcon(host: host) else {
                if onDisk == nil { self.negativeCache[host] = .now }
                return
            }
            if icon.image.width > onDisk?.image.width ?? 0 { self.keep(icon, for: host) }
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
            guard let self, let icon = await self.download(iconURL) else { return }
            // A page's 16 px favicon never replaces the sharper touch icon already kept for its site.
            var current = self.resolved[host]
            if current == nil { current = await self.loadFromDisk(host: host) }
            if let current, current.image.width > icon.image.width { return }
            self.keep(icon, for: host)
        }
    }

    private func keep(_ icon: Favicon, for host: String) {
        resolved[host] = icon
        negativeCache[host] = nil
        guard let url = diskURL(host: host), let data = Self.pngData(icon.image) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Seeds the cache with an icon another browser already had for `pageURL` (Arc import), so imported tabs
    /// show their real icons before they ever load. Never replaces an icon Boaz already has for the host.
    func seed(_ data: Data, for pageURL: URL) {
        guard let host = Self.hostKey(pageURL), resolved[host] == nil, let file = diskURL(host: host),
              !FileManager.default.fileExists(atPath: file.path), let icon = Favicon(data: data) else { return }
        keep(icon, for: host)
    }

    private func fetchWellKnownIcon(host: String) async -> Favicon? {
        for path in ["apple-touch-icon.png", "favicon.ico"] {
            guard let url = URL(string: "https://\(host)/\(path)"), let icon = await download(url) else { continue }
            return icon
        }
        return nil
    }

    /// Fetching and decoding stay off the main thread.
    private func download(_ url: URL) async -> Favicon? {
        await Self.usableIcon(at: url, gate: gate)
    }

    nonisolated private static func usableIcon(at url: URL, gate: FetchGate) async -> Favicon? {
        await gate.wait()
        defer { gate.signal() }
        guard let (data, response) = try? await session.data(from: url),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), data.count > 128
        else { return nil }
        return Favicon(data: data)
    }

    nonisolated private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.timeoutIntervalForResource = 10
        return URLSession(configuration: config)
    }()

    // MARK: Disk cache

    private func diskURL(host: String) -> URL? {
        diskDirectory?.appendingPathComponent(host.replacingOccurrences(of: "/", with: "_")).appendingPathExtension("png")
    }

    private func loadFromDisk(host: String) async -> Favicon? {
        guard let url = diskURL(host: host) else { return nil }
        return await Task.detached(priority: .utility) { (try? Data(contentsOf: url)).flatMap { Favicon(data: $0) } }.value
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
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

extension EnvironmentValues {
    /// Set on private (Incognito) browsing UI so favicons there never fetch or cache.
    @Entry var isPrivateBrowsing = false
}

/// Shared favicon rendering behind `Monogram` (iOS) and `SiteMonogram` (macOS), fading the site's real icon in over
/// a tinted letter tile once `Favicons` resolves one. Square artwork fills the tile with an app icon's corners; a
/// mark draws on its own, on a contrasting tile only when it would vanish against the background.
struct FaviconTile: View {
    @Environment(\.isPrivateBrowsing) private var isPrivate
    @Environment(\.colorScheme) private var scheme
    let url: URL?
    let tint: Color
    let size: CGFloat
    var letterScale: CGFloat = 0.5

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.225, style: .continuous) }
    private var host: String { url?.host()?.replacingOccurrences(of: "www.", with: "") ?? "?" }

    var body: some View {
        let icon = Favicons.shared.resolved(for: url)
        ZStack {
            if let icon {
                let image = Image(decorative: icon.image, scale: 1).resizable().interpolation(.high)
                if icon.isFullBleed {
                    image.aspectRatio(contentMode: .fill).frame(width: size, height: size).clipShape(shape)
                } else if scheme == .dark ? icon.isDark : icon.isLight {
                    shape.fill(scheme == .dark ? Color.white : Color.black)
                    image.aspectRatio(contentMode: .fit).padding(size * 0.18)
                } else {
                    // Never drawn at more points than it has pixels, where it would go soft.
                    let side = min(size, max(16, CGFloat(icon.image.width)))
                    image.aspectRatio(contentMode: .fit).frame(width: side, height: side)
                }
            } else {
                shape.fill(tint.gradient)
                Text(host.prefix(1).uppercased())
                    .font(.system(size: size * letterScale, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.18), value: icon != nil)
        .task(id: url) { Favicons.shared.request(url, isPrivate: isPrivate) }
    }
}
