import Foundation
import WebKit

/// Per-host choices from the page settings menu: desktop/mobile site and the Website Settings sheet's
/// permissions, pop-ups and content blocking. Remembered like `PageZoom`; Incognito tabs keep their own
/// choices in memory until Incognito ends.
enum PageSettings {
    enum Permission: String, Codable, CaseIterable, Identifiable {
        case ask, allow, deny
        var id: String { rawValue }
        var label: String {
            switch self {
            case .ask: "Ask"
            case .allow: "Allow"
            case .deny: "Deny"
            }
        }
    }

    enum PopupPolicy: String, Codable, CaseIterable, Identifiable {
        case block, allow
        var id: String { rawValue }
        var label: String { self == .block ? "Block" : "Allow" }
    }

    struct HostSettings: Codable, Equatable {
        var desktopSite = false
        var camera: Permission = .ask
        var microphone: Permission = .ask
        /// Allowed by default: a blocked pop-up is often a sign-in window the site can't work without.
        var popups: PopupPolicy = .allow
        var contentBlocking = true

        init() {}

        /// Every field is optional on disk, so a setting added later never wipes the ones already saved.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let defaults = HostSettings()
            desktopSite = try container.decodeIfPresent(Bool.self, forKey: .desktopSite) ?? defaults.desktopSite
            camera = try container.decodeIfPresent(Permission.self, forKey: .camera) ?? defaults.camera
            microphone = try container.decodeIfPresent(Permission.self, forKey: .microphone) ?? defaults.microphone
            popups = try container.decodeIfPresent(PopupPolicy.self, forKey: .popups) ?? defaults.popups
            contentBlocking = try container.decodeIfPresent(Bool.self, forKey: .contentBlocking) ?? defaults.contentBlocking
        }
    }

    /// Matches Mac Safari. `applicationNameForUserAgent` only yields a desktop-shaped user agent when
    /// WebKit itself runs on a Mac, so on iPhone "Request Desktop Website" sets the whole string instead.
    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15"

    private static let defaultsKey = "pageSettingsByHost"
    /// Choices made in Incognito: applied to private tabs only, never written to disk, and forgotten when
    /// Incognito ends. Private tabs fall back to the saved choices; normal tabs never see these.
    private static var unsaved: [String: HostSettings] = [:]

    static func settings(forHost host: String?, isPrivate: Bool) -> HostSettings {
        guard let host else { return HostSettings() }
        if isPrivate, let value = unsaved[host] { return value }
        return saved()[host] ?? HostSettings()
    }

    static func settings(for url: URL?, isPrivate: Bool) -> HostSettings {
        settings(forHost: url?.host(), isPrivate: isPrivate)
    }

    static func update(forHost host: String?, isPrivate: Bool, _ change: (inout HostSettings) -> Void) {
        guard let host else { return }
        var value = settings(forHost: host, isPrivate: isPrivate)
        change(&value)
        if isPrivate {
            unsaved[host] = value
        } else {
            var all = saved()
            all[host] = value
            save(all)
        }
    }

    /// Called when Incognito ends.
    static func forgetPrivateChoices() { unsaved = [:] }

    /// The user agent for a main-frame load of `host`: Mac Safari's for a desktop-site host, otherwise WebKit's own.
    static func userAgent(forHost host: String?, isPrivate: Bool) -> String? {
        settings(forHost: host, isPrivate: isPrivate).desktopSite ? desktopUserAgent : nil
    }

    /// Combines camera + microphone for `WKMediaCaptureType.cameraAndMicrophone`: denies if either is
    /// denied, otherwise asks if either still asks, otherwise allows.
    private static func combined(_ a: Permission, _ b: Permission) -> Permission {
        if a == .deny || b == .deny { return .deny }
        if a == .ask || b == .ask { return .ask }
        return .allow
    }

    /// The `WebPage.Configuration.deviceSensorAuthorization` decision for a camera/microphone request.
    /// WebPage has no such hook for geolocation, so there is no per-site Location setting.
    static func mediaCaptureDecision(_ type: WKMediaCaptureType, host: String?, isPrivate: Bool) -> WKPermissionDecision {
        let settings = settings(forHost: host, isPrivate: isPrivate)
        let permission: Permission = switch type {
        case .camera: settings.camera
        case .microphone: settings.microphone
        case .cameraAndMicrophone: combined(settings.camera, settings.microphone)
        @unknown default: .ask
        }
        return switch permission {
        case .allow: .grant
        case .deny: .deny
        case .ask: .prompt
        }
    }

    private static func saved() -> [String: HostSettings] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: HostSettings].self, from: data)) ?? [:]
    }

    private static func save(_ all: [String: HostSettings]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
