import AppKit
import Darwin
import MachO

@main
struct BoazCLI {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    @MainActor
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments == ["--help"] || arguments.isEmpty {
                print("Usage: boaz URL... | boaz devtools [URL] | boaz automation | boaz --help")
                return
            }
            let (application, identifier) = try ownApplication()
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.createsNewApplicationInstance = false
            configuration.activates = true
            if arguments.first == "automation" {
                guard arguments.count == 1 else { throw Failure(message: "Usage: boaz automation") }
                guard NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty else {
                    throw Failure(message: "Quit Boaz before enabling automation, then run boaz automation again.")
                }
                configuration.arguments = ["--boaz-automation"]
                _ = try await NSWorkspace.shared.openApplication(at: application, configuration: configuration)
                return
            }
            let urls: [URL]
            if arguments.first == "devtools" {
                guard arguments.count <= 2 else { throw Failure(message: "Usage: boaz devtools [URL]") }
                var components = URLComponents()
                components.scheme = "boaz"
                components.host = "devtools"
                if arguments.count == 2 {
                    let target = try webURL(arguments[1])
                    components.queryItems = [URLQueryItem(name: "url", value: target.absoluteString)]
                }
                guard let url = components.url else { throw Failure(message: "Could not prepare the Developer Tools request.") }
                urls = [url]
            } else {
                urls = try arguments.map(webURL)
            }
            _ = try await NSWorkspace.shared.open(urls, withApplicationAt: application, configuration: configuration)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "Boaz could not complete this request."
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(EXIT_FAILURE)
        }
    }

    static func webURL(_ argument: String) throws -> URL {
        guard !argument.isEmpty, !argument.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              let components = URLComponents(string: argument),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty, let url = components.url else {
            throw Failure(message: "Provide complete http:// or https:// URLs.")
        }
        return url
    }

    static func ownApplication() throws -> (URL, String) {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0 else { throw Failure(message: "Could not locate the bundled Boaz command.") }
        var bytes = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&bytes, &size) == 0 else {
            throw Failure(message: "Could not locate the bundled Boaz command.")
        }
        let executable = URL(fileURLWithPath: String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)).resolvingSymlinksInPath().standardizedFileURL
        let macOS = executable.deletingLastPathComponent()
        let contents = macOS.deletingLastPathComponent()
        let application = contents.deletingLastPathComponent()
        guard macOS.lastPathComponent == "MacOS", contents.lastPathComponent == "Contents",
              application.pathExtension == "app", let bundle = Bundle(url: application),
              bundle.object(forInfoDictionaryKey: "BoazNativeApplication") as? Bool == true,
              let identifier = bundle.bundleIdentifier,
              ["com.chenkahana.boaz", "com.chenkahana.boaz.chromium.dev"].contains(identifier) else {
            throw Failure(message: "This command must be installed from the Boaz Chromium application.")
        }
        return (application, identifier)
    }
}
