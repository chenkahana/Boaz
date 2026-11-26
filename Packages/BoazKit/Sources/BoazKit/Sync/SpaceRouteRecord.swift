import CloudKit
import Foundation

/// `SpaceRoute` on CloudKit. Host and path are encrypted; the rest is plain. A re-point (space and its profile)
/// merges as one unit; the position merges on its own.
extension SpaceRoute: SyncableRecord {
    public static var syncType: SyncRecordType { .spaceRoute }
    public static var mergeGroups: [[String]] { [["profileID", "spaceID"]] }

    public func write(to record: CKRecord) {
        record.encryptedValues["host"] = host
        record.encryptedValues["pathPrefix"] = pathPrefix
        record["profileID"] = profileID
        record["spaceID"] = spaceID
        record["position"] = position
        record["modifiedAt"] = modifiedAt
        record["deletedAt"] = deletedAt
    }

    public init(cloudRecord r: CKRecord) throws {
        let id = try SyncMapping.check(r, is: SpaceRoute.self)
        try self.init(host: try r.required("host", r.secretString("host")),
                      pathPrefix: r.secretString("pathPrefix"),
                      spaceID: try r.required("spaceID", r.string("spaceID")),
                      profileID: try r.required("profileID", r.string("profileID")),
                      position: r.double("position") ?? 0,
                      modifiedAt: try r.required("modifiedAt", r.date("modifiedAt")),
                      deletedAt: r.date("deletedAt"))
        // Host and path were normalized above; a record whose name doesn't belong to them is refused.
        guard self.id == id else { throw SyncMappingError.badRecordName(r.recordID.recordName) }
    }
}
