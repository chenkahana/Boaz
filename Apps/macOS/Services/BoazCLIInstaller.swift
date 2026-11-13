#if BOAZ_CHROMIUM
import Foundation

@MainActor
enum BoazCLIInstaller {
    enum InstallError: LocalizedError {
        case unavailable, conflictingDestination, invalidDirectory
        var errorDescription: String? {
            switch self {
            case .unavailable: "This copy of Boaz does not contain an executable command-line tool."
            case .conflictingDestination: "Another file or link already exists at ~/.local/bin/boaz. Move it yourself before installing Boaz’s command-line tool."
            case .invalidDirectory: "The ~/.local and ~/.local/bin locations must be ordinary directories, not links or files."
            }
        }
    }

    static func install() throws {
        let manager = FileManager.default
        let executable = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/boaz")
        guard let attributes = try? manager.attributesOfItem(atPath: executable.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              manager.isExecutableFile(atPath: executable.path) else {
            throw InstallError.unavailable
        }
        let local = manager.homeDirectoryForCurrentUser.appendingPathComponent(".local", isDirectory: true)
        let bin = local.appendingPathComponent("bin", isDirectory: true)
        for directory in [local, bin] {
            do {
                try manager.createDirectory(at: directory, withIntermediateDirectories: false)
            } catch {
                guard let attributes = try? manager.attributesOfItem(atPath: directory.path),
                      attributes[.type] as? FileAttributeType == .typeDirectory else {
                    throw InstallError.invalidDirectory
                }
            }
            let attributes = try manager.attributesOfItem(atPath: directory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw InstallError.invalidDirectory
            }
        }
        let destination = bin.appendingPathComponent("boaz")
        do {
            try manager.createSymbolicLink(atPath: destination.path, withDestinationPath: executable.path)
        } catch {
            if let target = try? manager.destinationOfSymbolicLink(atPath: destination.path) {
                guard target == executable.path else { throw InstallError.conflictingDestination }
                return
            }
            if (try? manager.attributesOfItem(atPath: destination.path)) != nil {
                throw InstallError.conflictingDestination
            }
            throw error
        }
    }
}
#endif
