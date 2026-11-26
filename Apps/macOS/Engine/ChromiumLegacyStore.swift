#if BOAZ_CHROMIUM
import Foundation
import Darwin
import OSLog
import BoazKit
import CryptoKit
import SQLite3
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

    /// The previous Boaz's WebKit cookies, brought into the profile's Chromium profile: its own WebKit store's and,
    /// for the default profile, also those of WebKit's default store, which v0.2.18 used for a page opened before its
    /// library loaded (#188). The profile's own store wins, and a cookie the profile already has is never replaced.
    /// `LegacyCookieImport` decides, launch by launch, when an import has reached the disk; the old data stays put.
    @MainActor static func importWebKitCookies(runtime: ChromiumRuntime, profile: ChromiumProfile, model: MacModel) async {
        guard !profile.identity.isPrivate, Bundle.main.bundleIdentifier == "com.chenkahana.boaz",
              Bundle.main.object(forInfoDictionaryKey: "BoazDistributionChannel") as? String == "production" else { return }
        let id = profile.identity.id
        // A store without an identifier is the new app's own default store, given while the library is still loading.
        let own = model.dataStore(for: id)
        guard own.identifier != nil else { return }
        let destination = chromiumCookieKeys(profileID: id)
        // The profile's own cookies win, so the default store's wait until those could be read.
        guard let winning = await importCookies(from: own, stateKey: "BoazChromiumLegacyCookiesImportV2.\(id)",
                                                oldMarker: "BoazChromiumLegacyCookiesImportedV1.\(id)", excluded: [],
                                                destination: destination, runtime: runtime, profile: profile),
              model.sidebar.profiles.first(where: \.isDefault)?.id == id else { return }
        let stateKey = "BoazChromiumLegacyDefaultCookiesImportedV1"
        guard !LegacyCookieImport.State(stored: UserDefaults.standard.data(forKey: stateKey),
                                        closedByOldMarker: false).isFinished else { return }
        if let store = legacyDefaultCookieStore(stateKey: stateKey) {
            _ = await importCookies(from: store, stateKey: stateKey, oldMarker: nil, excluded: winning,
                                    destination: destination, runtime: runtime, profile: profile)
        }
        if LegacyCookieImport.State(stored: UserDefaults.standard.data(forKey: stateKey), closedByOldMarker: false).isFinished {
            try? await WKWebsiteDataStore.remove(forIdentifier: legacyDefaultStoreID)
        }
    }

    /// Where the default store's cookies are copied, so WebKit reads them without the old store being opened.
    private static let legacyDefaultStoreID = UUID(uuidString: "B0A20DEF-A017-4C00-8000-000000000188")!

    /// A copy of the sandboxed app's default-store cookie file, as a store of its own; nil when there is nothing to
    /// copy (recorded as done) or the copy failed (retried next launch). An existing copy is never replaced.
    private static func legacyDefaultCookieStore(stateKey: String) -> WKWebsiteDataStore? {
        let files = FileManager.default, home = files.homeDirectoryForCurrentUser
        let source = home.appendingPathComponent(
            "Library/Containers/com.chenkahana.boaz/Data/Library/Cookies/Cookies.binarycookies")
        let current = home.appendingPathComponent("Library/WebKit/com.chenkahana.boaz/WebsiteDataStore", isDirectory: true)
        let name = legacyDefaultStoreID.uuidString.lowercased()
        let destination = current.appendingPathComponent(name, isDirectory: true)
        if !files.fileExists(atPath: destination.path) {
            guard let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else {
                UserDefaults.standard.set(LegacyCookieImport.State(phase: .done).stored, forKey: stateKey)
                return nil
            }
            let staging = current.appendingPathComponent(".\(name).importing", isDirectory: true)
            do {
                try? files.removeItem(at: staging)
                try files.createDirectory(at: staging.appendingPathComponent("Cookies"), withIntermediateDirectories: true)
                try files.copyItem(at: source, to: staging.appendingPathComponent("Cookies/Cookies.binarycookies"))
                try files.moveItem(at: staging, to: destination)
            } catch {
                Logger(subsystem: "com.chenkahana.boaz", category: "app").error(
                    "Copying the previous default-store cookies failed; next launch retries: \(String(describing: error))")
                return nil
            }
        }
        return WKWebsiteDataStore(forIdentifier: legacyDefaultStoreID)
    }

    @MainActor private static var importedThisLaunch: Set<String> = []

    /// One launch's step for one source; returns the cookies it read, which win over a later source's, or nil when
    /// it couldn't read or import them.
    @MainActor private static func importCookies(from store: WKWebsiteDataStore, stateKey: String, oldMarker: String?,
                                                 excluded: Set<LegacyCookieImport.Key>,
                                                 destination: Set<LegacyCookieImport.Key>?,
                                                 runtime: ChromiumRuntime, profile: ChromiumProfile) async -> Set<LegacyCookieImport.Key>? {
        // Once a launch: what this launch imported reaches the disk only later, so the check waits for the next one.
        guard importedThisLaunch.insert(stateKey).inserted else { return [] }
        let defaults = UserDefaults.standard
        let state = LegacyCookieImport.State(stored: defaults.data(forKey: stateKey),
                                             closedByOldMarker: oldMarker.map(defaults.bool(forKey:)) ?? false)
        guard !state.isFinished else { return [] }
        let log = Logger(subsystem: "com.chenkahana.boaz", category: "app")
        do {
            guard let cookies = try await readCookies(store) else {
                log.error("Previous cookies were not readable yet; next launch retries")
                return nil
            }
            let keys = cookies.map { LegacyCookieImport.Key(host: $0.domain, name: $0.name, path: $0.path) }
            let (action, next) = LegacyCookieImport.plan(state, source: keys, excluded: excluded, destination: destination)
            if case .importCookies(let picked) = action {
                let result = try await runtime.importCookies(profile: profile, cookies: picked.map { cookies[$0] })
                log.info("Imported \(result.imported) previous cookies, rejected \(result.rejected)")
            }
            defaults.set(next.stored, forKey: stateKey)
            if next.phase == .stopped {
                log.error("Previous cookies never reached the profile's cookie file; Boaz stopped importing them")
            }
            return Set(keys)
        } catch {
            log.error("Importing previous cookies failed; next launch retries: \(String(describing: error))")
            return nil
        }
    }

    /// The store's cookies, or nil when it should have some but WebKit hasn't handed them over yet.
    @MainActor private static func readCookies(_ store: WKWebsiteDataStore) async throws -> [HTTPCookie]? {
        let sites = await store.dataRecords(ofTypes: [WKWebsiteDataTypeCookies])
        var cookies = await store.httpCookieStore.allCookies()
        // WebKit can answer empty, its records included, until a web view has used the store, so the store's
        // cookie file on disk also says whether there are cookies to wait for. One that sees nothing wakes it.
        let file = store.identifier.map { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/WebKit/com.chenkahana.boaz/WebsiteDataStore/\($0.uuidString.lowercased())/Cookies/Cookies.binarycookies") }
        let stored = file.flatMap { try? Data(contentsOf: $0) }.flatMap { WebKitCookieFile.unexpiredCount(in: $0) } ?? 0
        let expected = !sites.isEmpty || stored > 0
        var waker: WKWebView?
        for _ in 0..<20 where cookies.isEmpty && expected {
            if waker == nil {
                let configuration = WKWebViewConfiguration()
                configuration.websiteDataStore = store
                waker = WKWebView(frame: .zero, configuration: configuration)
                waker?.loadHTMLString("", baseURL: nil)
            }
            try await Task.sleep(for: .milliseconds(250))
            cookies = await store.httpCookieStore.allCookies()
        }
        waker = nil
        return !expected || !cookies.isEmpty ? cookies : nil
    }

    /// The cookies in the profile's Chromium cookie file, read-only (Chromium doesn't lock it); none when it doesn't
    /// exist yet, nil when it can't be read.
    private static func chromiumCookieKeys(profileID: String) -> Set<LegacyCookieImport.Key>? {
        let hash = SHA256.hash(data: Data(profileID.utf8)).map { String(format: "%02X", $0) }.joined()
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Application Support/Boaz/Chromium/Boaz-\(hash)/Network/Cookies").path
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        var db: OpaquePointer?, statement: OpaquePointer?
        defer { sqlite3_finalize(statement); sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return nil }
        sqlite3_busy_timeout(db, 1000)
        guard sqlite3_prepare_v2(db, "SELECT host_key, name, path FROM cookies", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        var keys = Set<LegacyCookieImport.Key>()
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                let text = { (column: Int32) in sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
                keys.insert(.init(host: text(0), name: text(1), path: text(2)))
            case SQLITE_DONE: return keys
            default: return nil
            }
        }
    }

    static func applicationSupportDirectory() throws -> URL? {
        // Development builds keep their own library, so running one never adds a second library beside production's.
        if Bundle.main.object(forInfoDictionaryKey: "BoazDistributionChannel") as? String == "development" {
            return try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.chenkahana.boaz.chromium.dev", isDirectory: true)
        }
        guard Bundle.main.bundleIdentifier == "com.chenkahana.boaz",
              Bundle.main.object(forInfoDictionaryKey: "BoazDistributionChannel") as? String == "production" else {
            return nil
        }
        let files = FileManager.default, domain = "com.chenkahana.boaz"
        let legacy = files.homeDirectoryForCurrentUser.appendingPathComponent(
            "Library/Containers/com.chenkahana.boaz/Data/Library/Application Support", isDirectory: true)
        let current = try files.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: false)
        let legacyExists = try containsLibrary(legacy, files: files)
        let currentExists = try containsLibrary(current, files: files)
        // A second library appears whenever another build with this bundle id runs unsandboxed (an unsigned debug
        // build, say). Boaz keeps using the library it chose before and leaves the other one untouched; the first
        // time it sees two, it chooses the one with the user's data in it.
        let defaults = UserDefaults.standard, key = "BoazLibraryLocation"
        let useLegacy: Bool
        switch (legacyExists, currentExists) {
        case (true, false): useLegacy = true
        case (false, _): useLegacy = false
        case (true, true):
            switch defaults.string(forKey: key) {
            case "legacy": useLegacy = true
            case "current": useLegacy = false
            default:
                useLegacy = contentCount(legacy) >= contentCount(current)
                Logger(subsystem: domain, category: "app").notice(
                    "Two libraries found; using the \(useLegacy ? "sandbox" : "Application Support", privacy: .public) one and leaving the other untouched")
            }
        }
        if legacyExists || currentExists { defaults.set(useLegacy ? "legacy" : "current", forKey: key) }
        return useLegacy ? legacy : nil
    }

    /// Tabs, folders, archive and history rows in a library, read-only; an unreadable library counts as empty.
    private static func contentCount(_ base: URL) -> Int {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        let path = base.appendingPathComponent("Boaz/boaz.sqlite").path
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return 0 }
        var total = 0
        for table in ["sidebarItem", "archiveItem", "historyVisit"] {
            var statement: OpaquePointer?
            defer { sqlite3_finalize(statement) }
            guard sqlite3_prepare_v2(db, "SELECT count(*) FROM \(table)", -1, &statement, nil) == SQLITE_OK,
                  sqlite3_step(statement) == SQLITE_ROW else { continue }
            total += Int(sqlite3_column_int64(statement, 0))
        }
        return total
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
