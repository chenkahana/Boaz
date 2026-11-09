import Foundation
import WebKit

/// Per-host choices from the page settings menu: desktop/mobile site and the Website Settings sheet's
/// permissions, pop-ups and content blocking. Remembered like `PageZoom`; Incognito tabs apply the same
/// choice to the live page but never write it to disk.
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
        var location: Permission = .ask
        var popups: PopupPolicy = .block
        var contentBlocking = true
    }

    /// Matches Mac Safari. `applicationNameForUserAgent` only yields a desktop-shaped user agent when
    /// WebKit itself runs on a Mac, so on iPhone "Request Desktop Website" sets the whole string instead.
    static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Safari/605.1.15"

    private static let defaultsKey = "pageSettingsByHost"
    /// Set in Incognito: applied to the page, never written to disk.
    private static var unsaved: [String: HostSettings] = [:]

    static func settings(forHost host: String?) -> HostSettings {
        guard let host else { return HostSettings() }
        if let value = unsaved[host] { return value }
        return saved()[host] ?? HostSettings()
    }

    static func settings(for url: URL?) -> HostSettings { settings(forHost: url?.host()) }

    static func update(forHost host: String?, remember: Bool, _ change: (inout HostSettings) -> Void) {
        guard let host else { return }
        var value = settings(forHost: host)
        change(&value)
        if remember {
            var all = saved()
            all[host] = value
            save(all)
            unsaved[host] = nil
        } else {
            unsaved[host] = value
        }
    }

    /// Applies this host's desktop/mobile choice to a live page: the user agent takes effect at once;
    /// `preferredContentMode` is set per navigation by `BoazNavigationDecider`.
    static func applyDesktopSite(to page: WebPage) {
        page.customUserAgent = settings(for: page.url).desktopSite ? desktopUserAgent : nil
    }

    /// Combines camera + microphone for `WKMediaCaptureType.cameraAndMicrophone`: denies if either is
    /// denied, otherwise asks if either still asks, otherwise allows.
    private static func combined(_ a: Permission, _ b: Permission) -> Permission {
        if a == .deny || b == .deny { return .deny }
        if a == .ask || b == .ask { return .ask }
        return .allow
    }

    /// The `WebPage.Configuration.deviceSensorAuthorization` decision for a camera/microphone request.
    /// WebPage has no equivalent hook for geolocation (that's `WKUIDelegate`, which the SwiftUI `WebPage`
    /// API doesn't use), so the Location setting is remembered and shown but can't be enforced here.
    static func mediaCaptureDecision(_ type: WKMediaCaptureType, host: String?) -> WKPermissionDecision {
        let settings = settings(forHost: host)
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
