#if os(macOS)
import Foundation
import GRDB
import WebKit

/// Copies Arc's cookies for one profile into that profile's Boaz website data store.
///
/// SECURITY: cookies are session credentials. They go only into the local `WKWebsiteDataStore`
/// (`Profile.dataStoreID`); they are never written to the Boaz store and never synced.
public enum ArcCookieImporter {
    public struct Result: Sendable, Equatable {
        public var imported = 0, expired = 0, failed = 0
    }

    /// Reads and decrypts `<profile>/Cookies`. Arc may hold the database open, so it's read from a temporary copy.
    public static func readCookies(from database: URL, storage: ChromiumSafeStorage, now: Date = .now) throws
        -> (cookies: [HTTPCookie], result: Result) {
        try ChromiumDatabase.withCopy(of: database) { db in
            let metaVersion = try Int(String.fetchOne(db, sql: "SELECT value FROM meta WHERE key = 'version'") ?? "") ?? 0
            // Partitioned (CHIPS) cookies belong to one top-level site; WebKit would make them global, so skip them.
            let partitioned = try Row.fetchAll(db, sql: "PRAGMA table_info(cookies)")
                .contains { ($0["name"] as String?) == "top_frame_site_key" }
            let rows = try Row.fetchAll(db, sql: """
                SELECT host_key, name, value, encrypted_value, path, expires_utc, is_secure, is_httponly,
                       has_expires, is_persistent, samesite FROM cookies
                """ + (partitioned ? " WHERE top_frame_site_key IS NULL OR top_frame_site_key = ''" : ""))
            var cookies: [HTTPCookie] = []
            var result = Result()
            for row in rows {
                let host: String = row["host_key"]
                let persistent = (row["has_expires"] as Int? ?? 1) != 0 && (row["is_persistent"] as Int? ?? 1) != 0
                let expires = ChromiumDatabase.date(row["expires_utc"])
                if persistent, let expires, expires < now { result.expired += 1; continue }
                do {
                    let plainValue: String = row["value"] ?? ""
                    let encrypted: Data = row["encrypted_value"] ?? Data()
                    let value = plainValue.isEmpty && !encrypted.isEmpty
                        ? try storage.decryptCookie(encrypted, hostKey: host, metaVersion: metaVersion) : plainValue
                    var properties: [HTTPCookiePropertyKey: Any] = [
                        .domain: host, .path: row["path"] as String? ?? "/", .name: row["name"] as String, .value: value,
                    ]
                    if (row["is_secure"] as Int? ?? 0) != 0 { properties[.secure] = "TRUE" }
                    if (row["is_httponly"] as Int? ?? 0) != 0 { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
                    if persistent, let expires { properties[.expires] = expires }
                    switch row["samesite"] as Int? {
                    case 1: properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteLax.rawValue
                    case 2: properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict.rawValue
                    default: break
                    }
                    guard let cookie = HTTPCookie(properties: properties) else { result.failed += 1; continue }
                    cookies.append(cookie)
                } catch {
                    result.failed += 1
                }
            }
            result.imported = cookies.count
            return (cookies, result)
        }
    }

    /// Installs cookies into the profile's persistent website data store.
    @MainActor
    public static func install(_ cookies: [HTTPCookie], dataStoreID: UUID) async {
        let store = WKWebsiteDataStore(forIdentifier: dataStoreID).httpCookieStore
        for cookie in cookies { await store.setCookie(cookie) }
    }
}

/// Read-only access to a Chromium SQLite database through a private temporary copy.
enum ChromiumDatabase {
    static func withCopy<T>(of database: URL, _ body: (Database) throws -> T) throws -> T {
        let fm = FileManager.default
        guard fm.isReadableFile(atPath: database.path) else { throw ArcImportError.missingFile(database.lastPathComponent) }
        let dir = fm.temporaryDirectory.appendingPathComponent("boaz-arc-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? fm.removeItem(at: dir) }
        let copy = dir.appendingPathComponent(database.lastPathComponent)
        try fm.copyItem(at: database, to: copy)
        for suffix in ["-wal", "-journal"] {
            let sidecar = URL(fileURLWithPath: database.path + suffix)
            if fm.fileExists(atPath: sidecar.path) { try? fm.copyItem(at: sidecar, to: URL(fileURLWithPath: copy.path + suffix)) }
        }
        let queue = try DatabaseQueue(path: copy.path)  // writable copy so SQLite can replay a WAL
        defer { try? queue.close() }
        return try queue.read(body)
    }

    /// Chromium timestamps: microseconds since 1601-01-01 UTC; 0 means none.
    static func date(_ microseconds: Int64?) -> Date? {
        guard let microseconds, microseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(microseconds) / 1_000_000 - 11_644_473_600)
    }
}
#endif
