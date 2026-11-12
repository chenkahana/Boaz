import Foundation
import Security

/// A site's sign-in that Boaz keeps: who for, and where. The password itself stays in the Keychain until it is asked
/// for (`SavedPasswords.password(for:)`).
public struct SavedPassword: Identifiable, Hashable, Sendable {
    public var host: String
    /// Nil for the scheme's own port.
    public var port: Int?
    /// Saved on an https page. One saved on an http page is offered there only, never on the secure site.
    public var isSecure: Bool
    public var username: String
    public var modified: Date?

    public init(host: String, port: Int? = nil, isSecure: Bool = true, username: String, modified: Date? = nil) {
        self.host = host.lowercased()
        self.port = port
        self.isSecure = isSecure
        self.username = username
        self.modified = modified
    }

    /// The page's address, as a sign-in for it: nil for anything but http and https.
    public init?(url: URL, username: String) {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), !host.isEmpty else { return nil }
        self.init(host: host, port: url.port, isSecure: scheme == "https", username: username)
    }

    public var id: String { "\(isSecure ? "https" : "http")://\(site)|\(username)" }

    /// The host, with its port when it has one.
    public var site: String { port.map { "\(host):\($0)" } ?? host }
}

/// Boaz's own passwords, in the Keychain: in iCloud Keychain, so they reach Boaz on the user's other devices, and
/// readable only by Boaz while the device is unlocked.
public enum SavedPasswords {
    public enum Change: Sendable { case added, updated, unchanged }

    public struct KeychainError: LocalizedError {
        public let status: OSStatus
        public var errorDescription: String? {
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        }
    }

    /// Every saved sign-in, without its password.
    public static func all() throws -> [SavedPassword] {
        var query = common
        query[kSecMatchLimit] = kSecMatchLimitAll
        query[kSecReturnAttributes] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return (result as? [[CFString: Any]] ?? []).compactMap { item in
            guard let host = item[kSecAttrServer] as? String, let username = item[kSecAttrAccount] as? String else {
                return nil
            }
            let port = (item[kSecAttrPort] as? Int).flatMap { $0 == 0 ? nil : $0 }
            let isSecure = (item[kSecAttrProtocol] as? String) != (kSecAttrProtocolHTTP as String)
            return SavedPassword(host: host, port: port, isSecure: isSecure, username: username,
                                 modified: item[kSecAttrModificationDate] as? Date)
        }
    }

    public static func password(for entry: SavedPassword) throws -> String {
        var query = item(entry)
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecReturnData] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
        return String(decoding: data, as: UTF8.self)
    }

    /// Adds the sign-in, or gives the one already saved for this site and username the new password.
    @discardableResult
    public static func save(_ entry: SavedPassword, password: String) throws -> Change {
        let data = Data(password.utf8)
        switch Result(catching: { try Self.password(for: entry) }) {
        case .success(let current) where current == password:
            return .unchanged
        case .success:
            let status = SecItemUpdate(item(entry) as CFDictionary, [kSecValueData: data] as CFDictionary)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
            return .updated
        case .failure(let error as KeychainError) where error.status == errSecItemNotFound:
            var attributes = item(entry)
            attributes[kSecValueData] = data
            attributes[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
            attributes[kSecAttrLabel] = entry.site
            let status = SecItemAdd(attributes as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
            return .added
        case .failure(let error):
            throw error
        }
    }

    public static func delete(_ entry: SavedPassword) throws {
        let status = SecItemDelete(item(entry) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }

    /// Saves each imported sign-in; a site and username listed twice keeps the last.
    public static func save(_ imported: [ImportedPassword]) throws -> (added: Int, updated: Int) {
        var added = 0, updated = 0
        for item in imported {
            switch try save(item.entry, password: item.password) {
            case .added: added += 1
            case .updated: updated += 1
            case .unchanged: break
            }
        }
        return (added, updated)
    }

    /// The data protection keychain on the Mac too (iOS has no other), which is the one that syncs.
    private static var common: [CFString: Any] {
        [
            kSecClass: kSecClassInternetPassword,
            kSecAttrSynchronizable: true,
            kSecUseDataProtectionKeychain: true,
        ]
    }

    private static func item(_ entry: SavedPassword) -> [CFString: Any] {
        var query = common
        query[kSecAttrServer] = entry.host
        query[kSecAttrPort] = entry.port ?? 0
        query[kSecAttrAccount] = entry.username
        query[kSecAttrProtocol] = entry.isSecure ? kSecAttrProtocolHTTPS : kSecAttrProtocolHTTP
        return query
    }
}

extension [SavedPassword] {
    /// The sign-ins to offer on a page at `url`: on a secure page, those for any host of its site
    /// (accounts.example.com's on example.com), its own host first; on an insecure page, only that host's own.
    public func offered(at url: URL) -> [SavedPassword] {
        guard let page = SavedPassword(url: url, username: "") else { return [] }
        let host = page.host.droppingWWW
        let matches = filter { entry in
            let sameHost = entry.host.droppingWWW == host && entry.port == page.port
            if !page.isSecure { return sameHost && !entry.isSecure }
            return sameHost || entry.isSecure && SiteDomain.of(entry.host) == SiteDomain.of(page.host)
        }
        return matches.sorted { a, b in
            let aOwn = a.host.droppingWWW == host, bOwn = b.host.droppingWWW == host
            if aOwn != bOwn { return aOwn }
            return (a.modified ?? .distantPast) > (b.modified ?? .distantPast)
        }
    }
}

/// The part of a host its owner registered: example.co.il for www.example.co.il. Without the public suffix list,
/// a two-letter country code behind a short second level (co, com, org, net, ac, gov, edu) takes three labels.
enum SiteDomain {
    static func of(_ host: String) -> String {
        let labels = host.lowercased().split(separator: ".")
        guard labels.count > 2, !host.contains(":"), !labels.allSatisfy({ $0.allSatisfy(\.isNumber) }) else {
            return host.lowercased()
        }
        let secondLevels: Set<Substring> = ["co", "com", "org", "net", "ac", "gov", "edu"]
        let keep = labels.last!.count == 2 && secondLevels.contains(labels[labels.count - 2]) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }
}

private extension String {
    var droppingWWW: Substring { hasPrefix("www.") ? dropFirst(4) : self[...] }
}
