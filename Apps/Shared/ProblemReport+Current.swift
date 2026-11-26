import BoazKit
import Foundation

extension ProblemReport {
    /// This build, device and OS; nothing the user browsed.
    static func current(dark: Bool) -> ProblemReport {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(os.majorVersion).\(os.minorVersion)" + (os.patchVersion > 0 ? ".\(os.patchVersion)" : "")
        #if os(macOS)
        let app = App.mac, system = "macOS \(osVersion)"
        #else
        let app = App.iPhone, system = "iOS \(osVersion)"
        #endif
        return ProblemReport(app: app, version: info["CFBundleShortVersionString"] as? String ?? "",
                             build: info["CFBundleVersion"] as? String ?? "",
                             channel: info["BoazDistributionChannel"] as? String,
                             commit: info["BoazCommit"] as? String, engine: engine, model: model,
                             system: system, dark: dark)
    }

    /// The DMG names Chromium even while the WebKit fallback shows a page (must-have #1).
    private static var engine: String {
        #if BOAZ_CHROMIUM
        let framework = Bundle.main.privateFrameworksURL?.appending(path: "Chromium Framework.framework")
        let version = framework.flatMap(Bundle.init(url:))?.object(forInfoDictionaryKey: "CFBundleShortVersionString")
        return (version as? String).map { "Chromium \($0)" } ?? "Chromium"
        #else
        return "WebKit"
        #endif
    }

    private static var model: String {
        #if os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var value = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &value, &size, nil, 0)
        return String(decoding: value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        #else
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: system.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        #endif
    }
}
