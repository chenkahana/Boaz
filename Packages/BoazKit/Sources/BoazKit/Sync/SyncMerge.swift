import Foundation

/// Conflict policy for one record edited on this device (`local`, not yet uploaded) and on another (`server`).
///
/// - With a `base` (the last server version this device saw) the merge is per field: a field changed on one side
///   only keeps that change; a field changed on both sides goes to the newer `modifiedAt`. Fields in
///   `mergeGroups` (parent + position) move together, so a move never splits.
/// - Without a base it is last-writer-wins for the whole record.
/// - Equal `modifiedAt` favours the server, so every device converges on what CloudKit holds.
/// - Tombstones: a delete beats any edit older than it; an edit newer than the delete resurrects the record.
public enum SyncMerge {
    public static func resolve<R: SyncableRecord>(local: R, server: R, base: R? = nil) -> R {
        let localIsNewer = local.modifiedAt > server.modifiedAt
        var merged = (base.flatMap { fieldMerge(local: local, server: server, base: $0, localIsNewer: localIsNewer) })
            ?? (localIsNewer ? local : server)
        merged.modifiedAt = max(local.modifiedAt, server.modifiedAt)

        let newer = localIsNewer ? local : server
        let lastDelete = [local.deletedAt, server.deletedAt].compactMap { $0 }.max()
        if let lastDelete, newer.deletedAt != nil || newer.modifiedAt <= lastDelete {
            merged.deletedAt = lastDelete
        } else {
            merged.deletedAt = nil
        }
        return merged
    }

    private static let bookkeeping: Set<String> = ["id", "modifiedAt", "deletedAt"]

    private static func fieldMerge<R: SyncableRecord>(local: R, server: R, base: R, localIsNewer: Bool) -> R? {
        guard let l = fields(local), let s = fields(server), let b = fields(base) else { return nil }
        let keys = Set(l.keys).union(s.keys).union(b.keys).subtracting(bookkeeping)
        let grouped = Set(R.mergeGroups.joined())
        let units = R.mergeGroups + keys.subtracting(grouped).sorted().map { [$0] }

        var merged = s
        for unit in units {
            let localChanged = unit.contains { !same(l[$0], b[$0]) }
            let serverChanged = unit.contains { !same(s[$0], b[$0]) }
            guard localChanged, !serverChanged || localIsNewer else { continue }
            for key in unit { merged[key] = l[key] }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: merged.compactMapValues { $0 is NSNull ? nil : $0 })
        else { return nil }
        return try? JSONDecoder().decode(R.self, from: data)
    }

    private static func fields<R: Encodable>(_ value: R) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        let a = a is NSNull ? nil : a, b = b is NSNull ? nil : b
        switch (a, b) {
        case (nil, nil): return true
        case let (a?, b?): return (a as AnyObject).isEqual(b)
        default: return false
        }
    }
}
