import CloudKit
import CryptoKit
import Foundation
import GRDB

/// The synced tables. History and incognito tabs never reach CloudKit.
public enum SyncRecordType: String, CaseIterable, Sendable {
    case profile = "Profile"
    case space = "Space"
    case sidebarItem = "SidebarItem"
    case archiveItem = "ArchiveItem"

    var tableName: String {
        switch self {
        case .profile: Profile.databaseTableName
        case .space: Space.databaseTableName
        case .sidebarItem: SidebarItem.databaseTableName
        case .archiveItem: ArchiveItem.databaseTableName
        }
    }

    var recordType: any SyncableRecord.Type {
        switch self {
        case .profile: Profile.self
        case .space: Space.self
        case .sidebarItem: SidebarItem.self
        case .archiveItem: ArchiveItem.self
        }
    }
}

/// A store record that maps onto one `CKRecord`.
public protocol SyncableRecord: Codable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    static var syncType: SyncRecordType { get }
    /// Fields that only make sense together (a move is parent + position) and merge as one unit.
    static var mergeGroups: [[String]] { get }
    var id: String { get }
    var modifiedAt: Date { get set }
    var deletedAt: Date? { get set }
    /// Writes every field into `record`. URLs and titles go into `encryptedValues`.
    func write(to record: CKRecord)
    init(cloudRecord record: CKRecord) throws
    /// Copies fields that belong to this device only (never synced) from the local row onto an incoming copy.
    mutating func keepDeviceLocalFields(from local: Self)
}

extension SyncableRecord {
    public static var mergeGroups: [[String]] { [] }
    public mutating func keepDeviceLocalFields(from local: Self) {}

    /// Whether the row reads back once stored. Dates are stored as text for years 1–9999 only; a row outside that
    /// can't be decoded, which breaks every read of its table. Checked on records from other devices.
    var survivesStorage: Bool { (try? Self(row: Row(databaseDictionary))) != nil }
}

public enum SyncMappingError: Error, Equatable {
    case wrongRecordType(String)
    case badRecordName(String)
    case missingField(String)
}

/// Pure CKRecord <-> store record conversions.
public enum SyncMapping {
    public static let zoneName = "Boaz"
    public static var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName) }

    /// Record names are "<Type>:<id>" so a pending change identifies its table.
    public static func recordID(_ type: SyncRecordType, _ id: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(type.rawValue):\(id)", zoneID: zoneID)
    }

    public static func parse(_ recordID: CKRecord.ID) -> (type: SyncRecordType, id: String)? {
        let name = recordID.recordName
        guard let colon = name.firstIndex(of: ":"),
              let type = SyncRecordType(rawValue: String(name[..<colon])) else { return nil }
        return (type, String(name[name.index(after: colon)...]))
    }

    /// Builds the record to upload. `systemFields` (from a previous server round trip) carries the change tag.
    public static func record<R: SyncableRecord>(for value: R, systemFields: Data? = nil) -> CKRecord {
        let id = recordID(R.syncType, value.id)
        let record = systemFields.flatMap(decodeSystemFields).flatMap { $0.recordID == id ? $0 : nil }
            ?? CKRecord(recordType: R.syncType.rawValue, recordID: id)
        value.write(to: record)
        return record
    }

    public static func value<R: SyncableRecord>(_ type: R.Type, from record: CKRecord) throws -> R {
        try R(cloudRecord: record)
    }

    public static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    public static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: Field helpers

    static func check<R: SyncableRecord>(_ record: CKRecord, is type: R.Type) throws -> String {
        guard record.recordType == R.syncType.rawValue else { throw SyncMappingError.wrongRecordType(record.recordType) }
        guard let parsed = parse(record.recordID), parsed.type == R.syncType else {
            throw SyncMappingError.badRecordName(record.recordID.recordName)
        }
        return parsed.id
    }
}

extension CKRecord {
    func required<T>(_ key: String, _ value: T?) throws -> T {
        guard let value else { throw SyncMappingError.missingField(key) }
        return value
    }
    func string(_ key: String) -> String? { self[key] as? String }
    func date(_ key: String) -> Date? { self[key] as? Date }
    /// Finite values only: SQLite stores NaN as NULL, which a NOT NULL column rejects.
    func double(_ key: String) -> Double? { (self[key] as? NSNumber).map(\.doubleValue).flatMap { $0.isFinite ? $0 : nil } }
    func bool(_ key: String) -> Bool? { (self[key] as? NSNumber)?.boolValue }
    func secretString(_ key: String) -> String? { encryptedValues[key] as? String }
    func secretData(_ key: String) -> Data? { encryptedValues[key] as? Data }
}

// MARK: - Conformances

extension Profile: SyncableRecord {
    public static var syncType: SyncRecordType { .profile }

    // `dataStoreID` names this device's WebKit store (its logins), so it is device-local and never synced.
    // Older records may still carry a "dataStoreID" field; it is ignored.
    public func write(to record: CKRecord) {
        record.encryptedValues["name"] = name
        record["isDefault"] = isDefault
        record["modifiedAt"] = modifiedAt
        record["deletedAt"] = deletedAt
    }

    public init(cloudRecord r: CKRecord) throws {
        let id = try SyncMapping.check(r, is: Profile.self)
        self.init(id: id,
                  name: try r.required("name", r.secretString("name")),
                  dataStoreID: Self.dataStoreID(forNew: id),
                  isDefault: r.bool("isDefault") ?? false,
                  modifiedAt: try r.required("modifiedAt", r.date("modifiedAt")),
                  deletedAt: r.date("deletedAt"))
    }

    public mutating func keepDeviceLocalFields(from local: Profile) { dataStoreID = local.dataStoreID }

    /// The store id for a profile first seen from another device: derived from its id, so it is stable.
    static func dataStoreID(forNew id: String) -> UUID {
        Array(SHA256.hash(data: Data("Profile.dataStoreID:\(id)".utf8))).withUnsafeBufferPointer {
            NSUUID(uuidBytes: $0.baseAddress) as UUID
        }
    }
}

extension Space: SyncableRecord {
    public static var syncType: SyncRecordType { .space }
    public static var mergeGroups: [[String]] { [["profileID", "position"]] }

    public func write(to record: CKRecord) {
        record.encryptedValues["title"] = title
        record.encryptedValues["icon"] = icon
        // Arc `windowTheme` JSON, verbatim. Themes are a few KB, well under the 1 MB record limit.
        record.encryptedValues["themeJSON"] = themeJSON
        record["profileID"] = profileID
        record["position"] = position
        record["modifiedAt"] = modifiedAt
        record["deletedAt"] = deletedAt
    }

    public init(cloudRecord r: CKRecord) throws {
        let id = try SyncMapping.check(r, is: Space.self)
        self.init(id: id,
                  title: r.secretString("title") ?? "",
                  icon: r.secretString("icon"),
                  themeJSON: r.secretData("themeJSON"),
                  profileID: try r.required("profileID", r.string("profileID")),
                  position: r.double("position") ?? 0,
                  modifiedAt: try r.required("modifiedAt", r.date("modifiedAt")),
                  deletedAt: r.date("deletedAt"))
    }
}

extension SidebarItem: SyncableRecord {
    public static var syncType: SyncRecordType { .sidebarItem }
    public static var mergeGroups: [[String]] { [["parentID", "spaceID", "profileID", "position"]] }

    public func write(to record: CKRecord) {
        record["spaceID"] = spaceID
        record["profileID"] = profileID
        record["parentID"] = parentID
        record["kind"] = kind.rawValue
        record["containerKind"] = containerKind?.rawValue
        record.encryptedValues["title"] = title
        record.encryptedValues["url"] = url?.absoluteString
        record["isUnread"] = isUnread
        record["isExpanded"] = isExpanded
        record["position"] = position
        record["createdAt"] = createdAt
        record["lastActiveAt"] = lastActiveAt
        record["modifiedAt"] = modifiedAt
        record["deletedAt"] = deletedAt
    }

    public init(cloudRecord r: CKRecord) throws {
        let id = try SyncMapping.check(r, is: SidebarItem.self)
        self.init(id: id,
                  spaceID: r.string("spaceID"),
                  profileID: try r.required("profileID", r.string("profileID")),
                  parentID: r.string("parentID"),
                  kind: try r.required("kind", r.string("kind").flatMap(Kind.init(rawValue:))),
                  containerKind: r.string("containerKind").flatMap(ContainerKind.init(rawValue:)),
                  title: r.secretString("title"),
                  url: r.secretString("url").flatMap(URL.init(string:)),
                  isUnread: r.bool("isUnread") ?? false,
                  isExpanded: r.bool("isExpanded") ?? true,
                  position: r.double("position") ?? 0,
                  createdAt: r.date("createdAt") ?? r.creationDate ?? .now,
                  lastActiveAt: r.date("lastActiveAt"),
                  modifiedAt: try r.required("modifiedAt", r.date("modifiedAt")),
                  deletedAt: r.date("deletedAt"))
    }
}

extension ArchiveItem: SyncableRecord {
    public static var syncType: SyncRecordType { .archiveItem }

    public func write(to record: CKRecord) {
        record["profileID"] = profileID
        record["spaceID"] = spaceID
        record.encryptedValues["title"] = title
        record.encryptedValues["url"] = url.absoluteString
        record["archivedAt"] = archivedAt
        record["reason"] = reason
        record["modifiedAt"] = modifiedAt
        record["deletedAt"] = deletedAt
    }

    public init(cloudRecord r: CKRecord) throws {
        let id = try SyncMapping.check(r, is: ArchiveItem.self)
        self.init(id: id,
                  profileID: try r.required("profileID", r.string("profileID")),
                  spaceID: r.string("spaceID"),
                  title: r.secretString("title"),
                  url: try r.required("url", r.secretString("url").flatMap(URL.init(string:))),
                  archivedAt: try r.required("archivedAt", r.date("archivedAt")),
                  reason: r.string("reason") ?? "closed",
                  modifiedAt: try r.required("modifiedAt", r.date("modifiedAt")),
                  deletedAt: r.date("deletedAt"))
    }
}
