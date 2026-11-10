import Foundation
import WebKit

/// A downloaded file (iOS: `Documents/Downloads`; macOS: `~/Downloads`).
struct DownloadedFile: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int
    let savedAt: Date
}

enum DownloadError: Error { case noFilename, saveFailed }

/// Downloads non-renderable responses (anything `WebPage` can't show) by re-fetching them with
/// `URLSession`, carrying over the page's cookies, since `WebPage.NavigationDeciding` only hands us
/// the response metadata, not a body.
enum Downloads {
    @MainActor
    static func directory() throws -> URL {
        #if os(macOS)
        return try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        #else
        let docs = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let dir = docs.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
        #endif
    }

    /// Fetches `response.url` with the originating page's cookies and saves it under Documents/Downloads.
    /// Returns the saved file's URL and suggested display name.
    @MainActor
    static func save(_ response: URLResponse, dataStore: WKWebsiteDataStore) async throws -> (url: URL, name: String) {
        guard let sourceURL = response.url else { throw DownloadError.noFilename }
        return try await save(sourceURL, dataStore: dataStore)
    }

    /// Fetches `sourceURL` with the page's cookies and saves it to `directory()`.
    @MainActor
    static func save(_ sourceURL: URL, dataStore: WKWebsiteDataStore) async throws -> (url: URL, name: String) {
        var request = URLRequest(url: sourceURL)
        let cookies = await cookies(for: sourceURL, in: dataStore.httpCookieStore)
        if !cookies.isEmpty {
            for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) {
                request.setValue(value, forHTTPHeaderField: field)
            }
        }
        // A private page's download leaves no cookies or cache behind, as the page itself doesn't.
        let session = dataStore.isPersistent ? URLSession.shared : URLSession(configuration: .ephemeral)
        defer { if session !== URLSession.shared { session.finishTasksAndInvalidate() } }
        let (tempURL, finalResponse) = try await session.download(for: request)
        let name = suggestedName(for: finalResponse, fallbackURL: sourceURL)
        let dest = uniqueDestination(named: name, in: try directory())
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tempURL, to: dest)
        return (dest, dest.lastPathComponent)
    }

    /// The cookies a request to `url` would carry.
    @MainActor
    private static func cookies(for url: URL, in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        if #available(macOS 27.0, iOS 27.0, *) { return await store.cookies(for: url) }
        guard let host = url.host()?.lowercased() else { return [] }
        let path = url.path.isEmpty ? "/" : url.path
        return await store.allCookies().filter { cookie in
            let domain = cookie.domain.lowercased()
            let matchesHost = domain.hasPrefix(".") ? host == domain.dropFirst() || host.hasSuffix(domain) : host == domain
            return matchesHost && path.hasPrefix(cookie.path) && (!cookie.isSecure || url.scheme == "https")
                && (cookie.expiresDate ?? .distantFuture) > .now
        }
    }

    @MainActor
    static func list() -> [DownloadedFile] {
        guard let dir = try? directory() else { return [] }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys))) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: keys)
            return DownloadedFile(url: url, size: values?.fileSize ?? 0, savedAt: values?.contentModificationDate ?? .now)
        }
        .sorted { $0.savedAt > $1.savedAt }
    }

    @MainActor
    static func delete(_ file: DownloadedFile) {
        try? FileManager.default.removeItem(at: file.url)
    }

    private static func suggestedName(for response: URLResponse, fallbackURL: URL) -> String {
        if let name = response.suggestedFilename, !name.isEmpty { return name }
        let last = fallbackURL.lastPathComponent
        return last.isEmpty ? "Download" : last
    }

    private static func uniqueDestination(named name: String, in dir: URL) -> URL {
        var candidate = dir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let base = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension
        var index = 2
        repeat {
            let newName = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            candidate = dir.appendingPathComponent(newName)
            index += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }
}
