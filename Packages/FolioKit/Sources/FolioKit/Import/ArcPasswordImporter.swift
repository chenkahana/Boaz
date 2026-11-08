#if os(macOS)
import Foundation
import GRDB
import Security

/// Copies Arc's saved passwords for one profile into the Keychain as internet passwords.
///
/// SECURITY: items are synchronizable (iCloud Keychain) and labelled "Folio — imported from Arc".
/// Existing items for the same server, protocol, port and account are left untouched.
public enum ArcPasswordImporter {
    public static let label = "Folio — imported from Arc"

    public struct Login: Sendable, Equatable {
        public var url: URL
        public var username: String
        public var password: String
    }

    public struct Result: Sendable, Equatable {
        public var added = 0, existing = 0, skipped = 0, failed = 0
    }

    /// Reads and decrypts `<profile>/Login Data`. Skips "never save" entries and non-web logins.
    public static func readLogins(from database: URL, storage: ChromiumSafeStorage) throws -> (logins: [Login], result: Result) {
        try ChromiumDatabase.withCopy(of: database) { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT origin_url, signon_realm, username_value, password_value, blacklisted_by_user FROM logins
                """)
            var logins: [Login] = []
            var result = Result()
            for row in rows {
                let origin: String = row["origin_url"] ?? ""
                let realm: String = row["signon_realm"] ?? ""
                guard (row["blacklisted_by_user"] as Int? ?? 0) == 0,
                      let url = URL(string: origin.isEmpty ? realm : origin), url.host() != nil,
                      ["http", "https"].contains(url.scheme?.lowercased() ?? "")
                else { result.skipped += 1; continue }
                do {
                    let encrypted: Data = row["password_value"] ?? Data()
                    guard let password = String(data: try storage.decrypt(encrypted), encoding: .utf8), !password.isEmpty
                    else { result.skipped += 1; continue }
                    logins.append(Login(url: url, username: row["username_value"] ?? "", password: password))
                } catch {
                    result.failed += 1
                }
            }
            return (logins, result)
        }
    }

    /// Adds each login as a synchronizable internet password unless one already exists.
    public static func save(_ logins: [Login], into result: inout Result) {
        for login in logins {
            var identity: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecAttrServer as String: login.url.host() ?? "",
                kSecAttrAccount as String: login.username,
                kSecAttrProtocol as String: login.url.scheme?.lowercased() == "http" ? kSecAttrProtocolHTTP : kSecAttrProtocolHTTPS,
                kSecUseDataProtectionKeychain as String: true,
            ]
            if let port = login.url.port { identity[kSecAttrPort as String] = port }

            var lookup = identity
            lookup[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            lookup[kSecMatchLimit as String] = kSecMatchLimitOne
            if SecItemCopyMatching(lookup as CFDictionary, nil) == errSecSuccess { result.existing += 1; continue }

            var item = identity
            item[kSecAttrSynchronizable as String] = true
            item[kSecAttrLabel as String] = label
            if !login.url.path().isEmpty, login.url.path() != "/" { item[kSecAttrPath as String] = login.url.path() }
            item[kSecValueData as String] = Data(login.password.utf8)
            switch SecItemAdd(item as CFDictionary, nil) {
            case errSecSuccess: result.added += 1
            case errSecDuplicateItem: result.existing += 1
            default: result.failed += 1
            }
        }
    }
}
#endif
