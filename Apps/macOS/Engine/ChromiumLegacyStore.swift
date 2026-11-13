#if BOAZ_CHROMIUM
import Foundation

/// Selects the existing library in place; GRDB still owns opening and migration.
enum ChromiumLegacyStore {
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
