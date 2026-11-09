import Foundation
import GRDB

extension Device {
    private static let localIDKey = "localDeviceID"

    /// This install's device id, created on first use. Kept in `defaults` rather than the database, so resetting
    /// sync state never changes which Today tabs are this device's. The iOS app and its extensions pass the App
    /// Group's defaults so they agree.
    public static func localID(in defaults: UserDefaults) -> String {
        if let id = defaults.string(forKey: localIDKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: localIDKey)
        return id
    }
}

extension BoazStore {
    /// Records that this device is in use, under its current name. Apps call this on every activation, so an
    /// unchanged record seen within the last hour is left alone rather than synced again.
    public func registerDevice(id: String, name: String, platform: Device.Platform, at date: Date = .now) async throws {
        try await writer.write { db in
            if let current = try Device.fetchOne(db, key: id), current.deletedAt == nil, current.name == name,
               current.platform == platform, date.timeIntervalSince(current.lastSeenAt) < 60 * 60 {
                return
            }
            try Device(id: id, name: name, platform: platform, lastSeenAt: date, modifiedAt: date).save(db)
        }
    }
}
