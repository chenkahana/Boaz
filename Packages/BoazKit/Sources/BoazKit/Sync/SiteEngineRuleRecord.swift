import CloudKit
import CryptoKit
import Foundation
import GRDB

public struct SiteEngineRuleRecord: SyncableRecord, TableRecord {
    public static let databaseTableName = "siteEngineRuleRecord"
    public static var syncType: SyncRecordType { .siteEngineRule }
    public static var mergeGroups: [[String]] { [["profileID", "host", "pathPrefix", "reason"]] }

    public let id: String
    public let profileID: String
    public let host: String
    public let pathPrefix: String
    public let reason: String
    public let engine: String
    public let createdAt: Date
    public var modifiedAt: Date
    public var deletedAt: Date?

    public init(rule: SiteEngineRule, modifiedAt: Date, deletedAt: Date? = nil) {
        profileID = rule.profileID
        host = rule.host
        pathPrefix = rule.pathPrefix ?? ""
        reason = rule.reason.rawValue
        engine = rule.engine.rawValue
        createdAt = rule.createdAt
        self.modifiedAt = modifiedAt
        self.deletedAt = deletedAt
        id = Self.identifier(profileID: profileID, host: host, pathPrefix: pathPrefix, reason: reason)
    }

    // Four UTF-8 fields, each prefixed by its unsigned 64-bit big-endian byte count.
    private static func identifier(profileID: String, host: String, pathPrefix: String, reason: String) -> String {
        var bytes = Data()
        for field in [profileID, host, pathPrefix, reason] {
            let encoded = Data(field.utf8)
            let length = UInt64(encoded.count)
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8(truncatingIfNeeded: length >> shift))
            }
            bytes.append(encoded)
        }
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    public func rule() throws -> SiteEngineRule {
        guard let engine = StoredBrowserEngine(rawValue: engine),
              let reason = SiteEngineRule.Reason(rawValue: reason) else {
            throw SyncMappingError.missingField("engine/reason")
        }
        let rule = try SiteEngineRule(profileID: profileID, host: host,
            pathPrefix: pathPrefix.isEmpty ? nil : pathPrefix, engine: engine, reason: reason, createdAt: createdAt)
        guard rule.host == host, (rule.pathPrefix ?? "") == pathPrefix,
              id == Self.identifier(profileID: profileID, host: host, pathPrefix: pathPrefix, reason: self.reason) else {
            throw SyncMappingError.badRecordName(id)
        }
        return rule
    }

    private enum CodingKeys: String, CodingKey {
        case id, profileID, host, pathPrefix, reason, engine, createdAt, modifiedAt, deletedAt
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        profileID = try values.decode(String.self, forKey: .profileID)
        host = try values.decode(String.self, forKey: .host)
        pathPrefix = try values.decode(String.self, forKey: .pathPrefix)
        reason = try values.decode(String.self, forKey: .reason)
        engine = try values.decode(String.self, forKey: .engine)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        modifiedAt = try values.decode(Date.self, forKey: .modifiedAt)
        deletedAt = try values.decodeIfPresent(Date.self, forKey: .deletedAt)
        _ = try rule()
    }

    public func write(to record: CKRecord) {
        record["profileID"] = profileID
        record.encryptedValues["host"] = host
        record.encryptedValues["pathPrefix"] = pathPrefix
        record["reason"] = reason
        record["engine"] = engine
        record["createdAt"] = createdAt
        record["modifiedAt"] = modifiedAt
        record["deletedAt"] = deletedAt
    }

    public init(cloudRecord record: CKRecord) throws {
        id = try SyncMapping.check(record, is: Self.self)
        profileID = try record.required("profileID", record.string("profileID"))
        host = try record.required("host", record.secretString("host"))
        pathPrefix = try record.required("pathPrefix", record.secretString("pathPrefix"))
        reason = try record.required("reason", record.string("reason"))
        engine = try record.required("engine", record.string("engine"))
        createdAt = try record.required("createdAt", record.date("createdAt"))
        modifiedAt = try record.required("modifiedAt", record.date("modifiedAt"))
        deletedAt = record.date("deletedAt")
        _ = try rule()
    }
}
