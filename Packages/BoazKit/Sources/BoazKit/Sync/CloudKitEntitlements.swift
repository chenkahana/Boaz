import Foundation
import MachO
#if os(macOS)
import Security
#endif

/// Creating a `CKContainer` without the iCloud entitlement raises an Objective-C exception that Swift cannot catch,
/// so the entitlement is checked before CloudKit is touched at all.
@_spi(SyncTesting) public enum CloudKitEntitlements {
    static let servicesKey = "com.apple.developer.icloud-services"
    static let containersKey = "com.apple.developer.icloud-container-identifiers"

    /// Nil when this process may use CloudKit with `containerIdentifier`; otherwise the reason it can't.
    public static func missingReason(containerIdentifier: String) -> String? {
        guard services.contains("CloudKit") || services.contains("*") else {
            return "This build isn't signed for iCloud."
        }
        guard containers.contains(containerIdentifier) else {
            return "This build isn't entitled to the iCloud container \(containerIdentifier)."
        }
        return nil
    }

    // Read once: entitlements can't change while the process runs, and views ask on every redraw (`canSyncNow`).
    private static let services = list(value(for: servicesKey))
    private static let containers = list(value(for: containersKey))

    private static func list(_ value: Any?) -> [String] {
        (value as? [String]) ?? (value as? String).map { [$0] } ?? []
    }

    static func value(for key: String) -> Any? {
        #if os(macOS)
        if let task = SecTaskCreateFromSelf(nil) { return SecTaskCopyValueForEntitlement(task, key as CFString, nil) }
        return nil
        #else
        return mainExecutableEntitlements()?[key]
        #endif
    }

    /// Entitlements of the main executable, read from its loaded image: the `__TEXT,__entitlements` section on the
    /// Simulator, else the entitlements blob of the code signature in `__LINKEDIT`.
    @_spi(SyncTesting) public static func mainExecutableEntitlements() -> [String: Any]? {
        guard let image = _dyld_get_image_header(0) else { return nil }
        let slide = _dyld_get_image_vmaddr_slide(0)
        return image.withMemoryRebound(to: mach_header_64.self, capacity: 1) { header -> [String: Any]? in
            var size: UInt = 0
            if let section = getsectiondata(header, "__TEXT", "__entitlements", &size), size > 0 {
                return plist(Data(bytes: section, count: Int(size)))
            }
            var linkedit: (vmaddr: UInt64, fileoff: UInt64)?
            var signature: (offset: UInt32, size: UInt32)?
            var cursor = UnsafeRawPointer(header).advanced(by: MemoryLayout<mach_header_64>.size)
            for _ in 0..<header.pointee.ncmds {
                let command = cursor.loadUnaligned(as: load_command.self)
                if command.cmd == UInt32(LC_SEGMENT_64) {
                    let segment = cursor.loadUnaligned(as: segment_command_64.self)
                    let name = withUnsafeBytes(of: segment.segname) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
                    if name == "__LINKEDIT" { linkedit = (segment.vmaddr, segment.fileoff) }
                } else if command.cmd == UInt32(LC_CODE_SIGNATURE) {
                    let data = cursor.loadUnaligned(as: linkedit_data_command.self)
                    signature = (data.dataoff, data.datasize)
                }
                cursor = cursor.advanced(by: Int(command.cmdsize))
            }
            guard let linkedit, let signature, UInt64(signature.offset) >= linkedit.fileoff,
                  let blob = UnsafeRawPointer(bitPattern: Int(linkedit.vmaddr) + slide
                                              + Int(UInt64(signature.offset) - linkedit.fileoff))
            else { return nil }
            return entitlements(inSuperBlob: blob, size: Int(signature.size))
        }
    }

    private static func entitlements(inSuperBlob blob: UnsafeRawPointer, size: Int) -> [String: Any]? {
        func be32(_ offset: Int) -> UInt32? {
            offset + 4 <= size ? UInt32(bigEndian: blob.loadUnaligned(fromByteOffset: offset, as: UInt32.self)) : nil
        }
        guard be32(0) == 0xFADE_0CC0, let count = be32(8) else { return nil }
        for index in 0..<Int(count) {
            guard let type = be32(12 + index * 8), let offset = be32(16 + index * 8).map(Int.init) else { return nil }
            guard type == 5 else { continue } // CSSLOT_ENTITLEMENTS
            guard be32(offset) == 0xFADE_7171, let length = be32(offset + 4).map(Int.init),
                  length > 8, offset + length <= size else { return nil }
            return plist(Data(bytes: blob.advanced(by: offset + 8), count: length - 8))
        }
        return nil
    }

    private static func plist(_ data: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }
}
