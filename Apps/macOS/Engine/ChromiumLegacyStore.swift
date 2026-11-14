#if BOAZ_CHROMIUM
import Foundation
import Darwin
import OSLog
import WebKit

/// Selects the existing library in place; GRDB still owns opening and migration.
enum ChromiumLegacyStore {
    static func importMissingPreferences() throws {
        let domain = "com.chenkahana.boaz"
        guard Bundle.main.bundleIdentifier == domain,
              Bundle.main.object(forInfoDictionaryKey: "BoazDistributionChannel") as? String == "production" else { return }
        let defaults = UserDefaults.standard
        let marker = "BoazChromiumLegacyPreferencesImportedV1"
        var current = defaults.persistentDomain(forName: domain) ?? [:]
        guard current[marker] as? Bool != true else { return }
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.chenkahana.boaz/Data/Library/Preferences/com.chenkahana.boaz.plist")
        let descriptor = path.withUnsafeFileSystemRepresentation { name in
            name.map { Darwin.open($0, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC) } ?? -1
        }
        guard descriptor >= 0 else {
            if errno == ENOENT { return }
            throw failure("Boaz could not read its previous preferences. Check access to the previous Boaz container before continuing.")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        let limit = 16 * 1024 * 1024
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0,
              metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_size >= 0, metadata.st_size <= limit else {
            throw failure("Boaz's previous preferences must be a regular file no larger than 16 MiB.")
        }
        var data = Data()
        while data.count < limit + 1 {
            guard let chunk = try handle.read(upToCount: min(64 * 1024, limit + 1 - data.count)),
                  !chunk.isEmpty else { break }
            data.append(chunk)
        }
        guard data.count <= limit,
              let previous = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw failure("Boaz's previous preferences are not a valid bounded preference dictionary.")
        }
        for (key, value) in previous where key != marker && current[key] == nil {
            current[key] = value
        }
        defaults.setPersistentDomain(current, forName: domain)
        guard defaults.synchronize() else {
            throw failure("Boaz could not save the imported preferences. The original preferences remain unchanged.")
        }
        current[marker] = true
        defaults.setPersistentDomain(current, forName: domain)
        guard defaults.synchronize() else {
            defaults.removeObject(forKey: marker)
            _ = defaults.synchronize()
            throw failure("Boaz could not record preference import completion. It will retry without replacing existing values.")
        }
    }

    /// Copies each profile's sandboxed WebKit website data (cookies, storage) to the unsandboxed location
    /// `WKWebsiteDataStore(forIdentifier:)` now reads. Existing destinations are never replaced; the source is kept.
    static func importWebKitData() throws {
        let domain = "com.chenkahana.boaz"
        guard Bundle.main.bundleIdentifier == domain,
              Bundle.main.object(forInfoDictionaryKey: "BoazDistributionChannel") as? String == "production" else { return }
        let defaults = UserDefaults.standard
        let marker = "BoazChromiumLegacyWebKitDataImportedV1"
        guard !defaults.bool(forKey: marker) else { return }
        let files = FileManager.default
        let home = files.homeDirectoryForCurrentUser
        let legacy = home.appendingPathComponent(
            "Library/Containers/\(domain)/Data/Library/WebKit/WebsiteDataStore", isDirectory: true)
        let current = home.appendingPathComponent("Library/WebKit/\(domain)/WebsiteDataStore", isDirectory: true)
        let stores: [URL]
        do {
            stores = try files.contentsOfDirectory(at: legacy, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch let error as NSError where error.domain == NSCocoaErrorDomain &&
                    (error.code == NSFileReadNoSuchFileError || error.code == NSFileNoSuchFileError) {
            stores = []
        } catch let error as NSError {
            throw failure("Boaz could not read its previous website data. Check access to the previous Boaz container before continuing.", underlying: error)
        }
        do {
            for store in stores where UUID(uuidString: store.lastPathComponent) != nil {
                let values = try store.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
                let destination = current.appendingPathComponent(store.lastPathComponent, isDirectory: true)
                guard !files.fileExists(atPath: destination.path) else { continue }
                try files.createDirectory(at: current, withIntermediateDirectories: true)
                let staging = current.appendingPathComponent(".\(store.lastPathComponent).importing", isDirectory: true)
                try? files.removeItem(at: staging)
                try files.copyItem(at: store, to: staging)
                try files.moveItem(at: staging, to: destination)
            }
        } catch let error as NSError {
            throw failure("Boaz could not copy its previous website data. The original data remains unchanged; Boaz will retry on next launch.", underlying: error)
        }
        defaults.set(true, forKey: marker)
        guard defaults.synchronize() else {
            throw failure("Boaz could not record website data import completion. It will retry without replacing copied data.")
        }
    }

    /// One-time per profile: imports the previous WebKit cookies into its Chromium profile. Failure retries next launch.
    @MainActor static func importWebKitCookies(runtime: ChromiumRuntime, profile: ChromiumProfile, store: WKWebsiteDataStore) async {
        guard !profile.identity.isPrivate, Bundle.main.bundleIdentifier == "com.chenkahana.boaz",
              Bundle.main.object(forInfoDictionaryKey: "BoazDistributionChannel") as? String == "production" else { return }
        let marker = "BoazChromiumLegacyCookiesImportedV1.\(profile.identity.id)"
        guard !UserDefaults.standard.bool(forKey: marker) else { return }
        let log = Logger(subsystem: "com.chenkahana.boaz", category: "app")
        do {
            let result = try await runtime.importCookies(profile: profile, cookies: await store.httpCookieStore.allCookies())
            UserDefaults.standard.set(true, forKey: marker)
            log.info("Imported \(result.imported) previous cookies, rejected \(result.rejected)")
        } catch {
            log.error("Importing previous cookies failed; next launch retries: \(String(describing: error))")
        }
    }

    static func applicationSupportDirectory() throws -> URL? {
        guard Bundle.main.bundleIdentifier == "com.chenkahana.boaz",
              Bundle.main.object(forInfoDictionaryKey: "BoazDistributionChannel") as? String == "production" else {
            return nil
        }
        let files = FileManager.default
        let legacy = files.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.chenkahana.boaz/Data/Library/Application Support", isDirectory: true)
        let current = try files.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: false)
        let legacyExists = try containsLibrary(legacy, files: files)
        let currentExists = try containsLibrary(current, files: files)
        guard !(legacyExists && currentExists) else {
            throw failure("Boaz found libraries in both its previous sandbox and Application Support. Neither library was changed. Resolve which library to keep before continuing.")
        }
        return legacyExists ? legacy : nil
    }

    private static func containsLibrary(_ base: URL, files: FileManager) throws -> Bool {
        let database = base.appendingPathComponent("Boaz/boaz.sqlite", isDirectory: false)
        do {
            let attributes = try files.attributesOfItem(atPath: database.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw failure("Boaz cannot open this library because its database is not a regular file.")
            }
            return true
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain &&
                (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
                return false
            }
            throw failure("Boaz could not inspect its existing library. Check access to the previous Boaz container and Application Support before continuing.", underlying: error)
        }
    }

    private static func failure(_ message: String, underlying: NSError? = nil) -> NSError {
        var info: [String: Any] = [NSLocalizedDescriptionKey: message]
        if let underlying { info[NSUnderlyingErrorKey] = underlying }
        return NSError(domain: "Boaz.LegacyStore", code: 1, userInfo: info)
    }
}
#endif
