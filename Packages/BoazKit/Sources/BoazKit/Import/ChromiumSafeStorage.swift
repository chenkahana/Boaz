import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Chromium's macOS "Safe Storage" encryption, used by Arc for cookie values and saved passwords.
///
/// Key = PBKDF2-HMAC-SHA1(Keychain password, salt "saltysalt", 1003 iterations, 16 bytes).
/// Value = "v10" + AES-128-CBC(PKCS#7, IV = 16 spaces). Cookie DBs at meta version ≥ 24 prefix the
/// plaintext with SHA-256(host_key).
public struct ChromiumSafeStorage: Sendable {
    public static let arcKeychainService = "Arc Safe Storage"
    static let versionPrefix = Data("v10".utf8)
    static let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)

    let key: Data

    public init(password: Data) { key = Self.deriveKey(password: password) }

    public static func deriveKey(password: Data) -> Data {
        let salt = Data("saltysalt".utf8)
        var key = Data(repeating: 0, count: kCCKeySizeAES128)
        let status = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2),
                                         passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self), password.count,
                                         saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), salt.count,
                                         CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                                         keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self), kCCKeySizeAES128)
                }
            }
        }
        precondition(status == kCCSuccess, "PBKDF2 failed: \(status)")
        return key
    }

    /// Decrypts a "v10" blob. Blobs without a version prefix are returned as stored (pre-encryption plaintext);
    /// any other version ("v11", "v20", …) is a scheme Boaz doesn't know, so it fails rather than pass ciphertext on.
    public func decrypt(_ blob: Data) throws -> Data {
        guard blob.starts(with: Self.versionPrefix) else {
            let prefix = blob.prefix(3)
            if prefix.count == 3, prefix.first == UInt8(ascii: "v"), prefix.dropFirst().allSatisfy({ (0x30...0x39).contains($0) }) {
                throw ArcImportError.decryption("unsupported encryption version \(String(decoding: prefix, as: UTF8.self))")
            }
            return blob
        }
        return try crypt(CCOperation(kCCDecrypt), blob.dropFirst(Self.versionPrefix.count))
    }

    /// Encrypts like Chromium does. Used to build synthetic test vectors; Boaz never writes Arc's data.
    public func encrypt(_ plaintext: Data) throws -> Data {
        Self.versionPrefix + (try crypt(CCOperation(kCCEncrypt), plaintext))
    }

    /// Decrypts a `cookies.encrypted_value`, stripping the SHA-256(host_key) prefix from meta version 24 on.
    public func decryptCookie(_ blob: Data, hostKey: String, metaVersion: Int) throws -> String {
        var plain = try decrypt(blob)
        if metaVersion >= 24, blob.starts(with: Self.versionPrefix) {
            guard plain.count >= 32, plain.prefix(32) == Data(SHA256.hash(data: Data(hostKey.utf8))) else {
                throw ArcImportError.decryption("cookie for \(hostKey) has no matching domain hash")
            }
            plain = plain.dropFirst(32)
        }
        guard let value = String(data: plain, encoding: .utf8) else {
            throw ArcImportError.decryption("cookie for \(hostKey) isn't UTF-8")
        }
        return value
    }

    private func crypt(_ operation: CCOperation, _ input: Data) throws -> Data {
        var output = Data(repeating: 0, count: input.count + kCCBlockSizeAES128)
        var written = 0
        let outputCount = output.count
        let status = output.withUnsafeMutableBytes { out in
            input.withUnsafeBytes { inBytes in
                key.withUnsafeBytes { keyBytes in
                    Self.iv.withUnsafeBytes { ivBytes in
                        CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
                                keyBytes.baseAddress, key.count, ivBytes.baseAddress,
                                inBytes.baseAddress, input.count, out.baseAddress, outputCount, &written)
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw ArcImportError.decryption("AES status \(status)") }
        return output.prefix(written)
    }

    #if os(macOS)
    /// Reads Arc's Safe Storage password from the login Keychain. macOS asks the user to allow it.
    ///
    /// SECURITY: call only from an explicit user action (Import from Arc with cookies or passwords checked).
    /// The password and derived key stay in memory for the import and are never stored or logged.
    public static func fromKeychain(service: String = arcKeychainService) throws -> ChromiumSafeStorage {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let password = result as? Data else { throw ArcImportError.keychain(status) }
        return ChromiumSafeStorage(password: password)
    }
    #endif
}
