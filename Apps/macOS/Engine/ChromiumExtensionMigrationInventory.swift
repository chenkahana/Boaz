#if BOAZ_CHROMIUM
import Foundation
import BoazKit

@MainActor
enum ChromiumExtensionMigrationInventory {
    enum Kind: String, Sendable { case storeCandidate, developerReinstall }

    struct Item: Identifiable, Sendable {
        let extensionID: String
        let profileID: String
        let name: String
        let enabled: Bool
        let fromWebStore: Bool
        let kind: Kind
        var id: String { "\(profileID)/\(extensionID)" }
    }

    struct Group: Identifiable, Sendable {
        let profileID: String
        let profileName: String
        let items: [Item]
        var id: String { profileID }
    }

    struct Issue: Identifiable, Sendable {
        enum Kind: String, Sendable { case invalidRecord, orphanProfile, duplicateRecord }
        let recordNumber: Int
        let kind: Kind
        var id: Int { recordNumber }
        var message: String {
            switch kind {
            case .invalidRecord: "Extension record \(recordNumber) is invalid."
            case .orphanProfile: "Extension record \(recordNumber) belongs to an unavailable profile."
            case .duplicateRecord: "Extension record \(recordNumber) duplicates another record in its profile."
            }
        }
    }

    struct Inventory: Sendable {
        let groups: [Group]
        let issues: [Issue]
    }

    enum InventoryError: LocalizedError {
        case notRegularFile, tooLarge, invalidManifest, tooManyRecords, duplicateProfiles
        var errorDescription: String? {
            switch self {
            case .notRegularFile: "Choose an installed.json file."
            case .tooLarge: "The extension list exceeds the 1 MiB import limit."
            case .invalidManifest: "The selected file is not a valid extension list."
            case .tooManyRecords: "The extension list exceeds the 1,000-extension import limit."
            case .duplicateProfiles: "The available profiles have conflicting identifiers."
            }
        }
    }

    // Mirrors Extensions.Installed's persisted schema, without importing WebKit.
    private struct LegacyRecord: Decodable {
        let extensionID: String
        let profileID: String
        let contextID: UUID
        let name: String
        let enabled: Bool
        let permissions: [String]
        let matchPatterns: [String]
        let fromWebStore: Bool
    }

    private struct Key: Hashable { let profileID: String; let extensionID: String }

    static func read(from url: URL, profiles: [BoazKit.Profile]) throws -> Inventory {
        guard url.isFileURL,
              try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw InventoryError.notRegularFile
        }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let maximumBytes = 1_048_576
        let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        guard data.count <= maximumBytes else { throw InventoryError.tooLarge }
        guard let objects = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw InventoryError.invalidManifest
        }
        guard objects.count <= 1_000 else { throw InventoryError.tooManyRecords }
        let available = profiles.filter { $0.deletedAt == nil }
        guard Set(available.map(\.id)).count == available.count else { throw InventoryError.duplicateProfiles }
        let profileIDs = Set(available.map(\.id))
        var candidates: [(index: Int, record: LegacyRecord)] = []
        var issues: [Issue] = []
        var counts: [Key: Int] = [:]
        for (index, object) in objects.enumerated() {
            guard let object = object as? [String: Any],
                  let encoded = try? JSONSerialization.data(withJSONObject: object),
                  let record = try? JSONDecoder().decode(LegacyRecord.self, from: encoded),
                  !record.profileID.isEmpty, !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  record.name.utf8.count <= 4096, record.profileID.utf8.count <= 1024,
                  (record.fromWebStore ? validStoreID(record.extensionID) : UUID(uuidString: record.extensionID) != nil) else {
                issues.append(Issue(recordNumber: index + 1, kind: .invalidRecord)); continue
            }
            let key = Key(profileID: record.profileID, extensionID: record.extensionID)
            counts[key, default: 0] += 1
            candidates.append((index, record))
        }
        var items: [Item] = []
        for (index, record) in candidates {
            let key = Key(profileID: record.profileID, extensionID: record.extensionID)
            if counts[key, default: 0] > 1 {
                issues.append(Issue(recordNumber: index + 1, kind: .duplicateRecord)); continue
            }
            guard profileIDs.contains(record.profileID) else {
                issues.append(Issue(recordNumber: index + 1, kind: .orphanProfile)); continue
            }
            items.append(Item(extensionID: record.extensionID, profileID: record.profileID,
                              name: record.name, enabled: record.enabled, fromWebStore: record.fromWebStore,
                              kind: record.fromWebStore ? .storeCandidate : .developerReinstall))
        }
        let groups = available.compactMap { profile -> Group? in
            let matches = items.filter { $0.profileID == profile.id }
            return matches.isEmpty ? nil : Group(profileID: profile.id, profileName: profile.name, items: matches)
        }
        return Inventory(groups: groups, issues: issues.sorted { $0.recordNumber < $1.recordNumber })
    }

    private static func validStoreID(_ id: String) -> Bool {
        id.utf8.count == 32 && id.utf8.allSatisfy { (97...112).contains($0) }
    }
}
#endif
