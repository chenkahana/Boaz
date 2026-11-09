import Foundation

/// Any JSON value. Records travel through the sync folder as plain JSON objects.
public enum JSONValue: Codable, Hashable, Sendable {
    case null, bool(Bool), number(Double), string(String), array([JSONValue]), object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    var number: Double? { if case .number(let v) = self { v } else { nil } }
}

/// A record's fields plus a timestamp per field (or per merge group), so devices converge without a server:
/// merging two states keeps, for every field, the side that changed it last. The merge is commutative,
/// associative and idempotent, so every device ends up with the same record whatever order logs arrive in.
///
/// - A local edit stamps the fields it changed with `max(modifiedAt, newest stamp seen + 1 ms)`, so an edit made
///   after seeing another device's change always wins over it.
/// - Groups in `mergeGroups` (parent + position) share one stamp, so a move never splits.
/// - Tombstones: `deletedAt` is a field like any other; a record deleted earlier than another field's last
///   change comes back to life (an edit newer than the delete resurrects it; a delete beats older edits).
public struct RecordState: Codable, Hashable, Sendable {
    public var fields: [String: JSONValue]
    public var stamps: [String: Double]

    public init(fields: [String: JSONValue], stamps: [String: Double]) {
        self.fields = fields; self.stamps = stamps
    }

    // MARK: Model conversion

    public static func fields<R: SyncableRecord>(of value: R) throws -> [String: JSONValue] {
        try JSONDecoder().decode([String: JSONValue].self, from: JSONEncoder().encode(value))
    }

    public func value<R: SyncableRecord>(_: R.Type) throws -> R {
        try JSONDecoder().decode(R.self, from: JSONEncoder().encode(fields.filter { $0.value != .null }))
    }

    // MARK: Stamping and merging

    private static let unstamped: Set<String> = ["id", "modifiedAt"]
    private static let deleted = "deletedAt"

    /// Units of fields that merge together, named by their first key.
    static func units(_ keys: some Sequence<String>, groups: [[String]]) -> [[String]] {
        let grouped = Set(groups.joined())
        let singles = Set(keys).subtracting(grouped).subtracting(unstamped).sorted().map { [$0] }
        return groups + singles
    }

    /// The state after a local write produced `fields`. Changed units get a stamp newer than anything seen.
    public static func stamped(_ fields: [String: JSONValue], over previous: RecordState?, groups: [[String]]) -> RecordState {
        let modifiedAt = fields["modifiedAt"]?.number ?? Date.now.timeIntervalSinceReferenceDate
        var keys = Set(fields.keys)
        if let previous { keys.formUnion(previous.fields.keys); keys.formUnion(previous.stamps.keys) }
        let units = units(keys, groups: groups)
        guard let previous else {
            return RecordState(fields: fields, stamps: Dictionary(uniqueKeysWithValues: units.map { ($0[0], modifiedAt) }))
        }
        let stamp = max(modifiedAt, (previous.stamps.values.max() ?? -.infinity) + 0.001)
        var fields = fields
        // `modifiedAt` only grows, as in `merge`, so a device behind on its clock doesn't pull it backwards.
        if let seen = previous.fields["modifiedAt"]?.number, seen > modifiedAt { fields["modifiedAt"] = .number(seen) }
        var stamps = previous.stamps
        for unit in units where unit.contains(where: { (fields[$0] ?? .null) != (previous.fields[$0] ?? .null) }) {
            stamps[unit[0]] = stamp
        }
        return RecordState(fields: fields, stamps: stamps)
    }

    /// Field-wise last-writer-wins. Ties go to the larger encoded value, so both sides pick the same.
    public static func merge(_ a: RecordState, _ b: RecordState, groups: [[String]]) -> RecordState {
        let keys = Set(a.fields.keys).union(b.fields.keys).union(a.stamps.keys).union(b.stamps.keys)
        var out = RecordState(fields: [:], stamps: [:])
        for unit in units(keys, groups: groups) {
            let name = unit[0]
            let sa = a.stamps[name] ?? -.infinity, sb = b.stamps[name] ?? -.infinity
            let pick = sa != sb ? (sa > sb ? a : b) : (canonical(a, unit) >= canonical(b, unit) ? a : b)
            for key in unit { out.fields[key] = pick.fields[key] }
            out.stamps[name] = pick.stamps[name]
        }
        out.fields["id"] = a.fields["id"] ?? b.fields["id"]
        let modified = [a.fields["modifiedAt"]?.number, b.fields["modifiedAt"]?.number].compactMap { $0 }.max()
        out.fields["modifiedAt"] = modified.map(JSONValue.number)
        return out.normalized()
    }

    /// A delete older than some other field's last change is undone, stamped with that change.
    func normalized() -> RecordState {
        guard let deletedAt = fields[Self.deleted], deletedAt != .null else { return self }
        let deleteStamp = stamps[Self.deleted] ?? -.infinity
        let newest = stamps.filter { $0.key != Self.deleted }.values.max() ?? -.infinity
        guard newest > deleteStamp else { return self }
        var out = self
        out.fields[Self.deleted] = nil
        out.stamps[Self.deleted] = newest
        return out
    }

    private static func canonical(_ state: RecordState, _ unit: [String]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let subset = unit.map { state.fields[$0] ?? .null }
        return (try? encoder.encode(subset)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }
}
