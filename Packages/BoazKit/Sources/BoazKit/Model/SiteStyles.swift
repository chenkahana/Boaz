import Foundation

/// A user's own CSS for one site in one profile ("Site Styles"). Mac only, kept in UserDefaults, never synced.
public struct SiteStyle: Codable, Hashable, Sendable {
    public var profileID: String
    /// `SiteStyleBook.key(forHost:)`: lowercased, `www.` folded.
    public var host: String
    public var css: String
    public var updatedAt: Date

    public init(profileID: String, host: String, css: String, updatedAt: Date) {
        self.profileID = profileID; self.host = host; self.css = css; self.updatedAt = updatedAt
    }
}

/// Every saved site style, keyed by profile and exact host.
public struct SiteStyleBook: Codable, Hashable, Sendable {
    /// The page receives the CSS as one JSON argument, which the Chromium host caps at 64 KB.
    public static let maxBytes = 32 * 1024
    public static let maxSites = 500

    public enum SaveError: Error, Equatable { case invalidHost, tooLong, tooMany }

    public private(set) var styles: [SiteStyle]

    public init(styles: [SiteStyle] = []) { self.styles = styles }

    /// The host a style is saved under: lowercased, without a trailing dot, and a leading `www.` folded so
    /// `www.nytimes.com` and `nytimes.com` share one. Nil for an empty host.
    public static func key(forHost host: String) -> String? {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasSuffix(".") { value.removeLast() }
        if value.hasPrefix("www."), value.dropFirst(4).contains(".") { value.removeFirst(4) }
        guard !value.isEmpty, !value.contains(" "), !value.contains("/") else { return nil }
        return value
    }

    public static func fits(_ css: String) -> Bool { css.utf8.count <= maxBytes }

    public func style(profileID: String, host: String) -> SiteStyle? {
        guard let key = Self.key(forHost: host) else { return nil }
        return styles.first { $0.profileID == profileID && $0.host == key }
    }

    public func css(profileID: String, host: String) -> String? { style(profileID: profileID, host: host)?.css }

    /// One profile's styles by host, for a page that looks its own host up as it starts.
    public func cssByHost(profileID: String) -> [String: String] {
        Dictionary(styles.filter { $0.profileID == profileID }.map { ($0.host, $0.css) }, uniquingKeysWith: { $1 })
    }

    /// Whether saving a new host would pass the cap; replacing an existing style never does.
    public func isFull(adding host: String, profileID: String) -> Bool {
        style(profileID: profileID, host: host) == nil && styles.count >= Self.maxSites
    }

    /// Saves `css` for the host, replacing what was there. Saving only whitespace deletes the style, so the book
    /// never holds blank ones.
    public mutating func save(_ css: String, profileID: String, host: String, now: Date = .now) throws {
        guard let key = Self.key(forHost: host) else { throw SaveError.invalidHost }
        guard !css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            delete(profileID: profileID, host: key)
            return
        }
        guard Self.fits(css) else { throw SaveError.tooLong }
        if let index = styles.firstIndex(where: { $0.profileID == profileID && $0.host == key }) {
            styles[index].css = css
            styles[index].updatedAt = now
        } else {
            guard styles.count < Self.maxSites else { throw SaveError.tooMany }
            styles.append(SiteStyle(profileID: profileID, host: key, css: css, updatedAt: now))
        }
    }

    public mutating func delete(profileID: String, host: String) {
        guard let key = Self.key(forHost: host) else { return }
        styles.removeAll { $0.profileID == profileID && $0.host == key }
    }

    /// Drops the styles of profiles that no longer exist.
    public mutating func keepProfiles(_ profileIDs: Set<String>) {
        styles.removeAll { !profileIDs.contains($0.profileID) }
    }
}

/// The editor's one-tap starting points: plain CSS added at the end of the text, under a comment naming it.
public enum SiteStylePreset: String, CaseIterable, Identifiable, Sendable {
    case dark, hideCookieBanners, biggerText

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dark: "Dark"
        case .hideCookieBanners: "Hide Cookie Banners"
        case .biggerText: "Bigger Text"
        }
    }

    public var css: String {
        switch self {
        case .dark:
            """
            html { filter: invert(1) hue-rotate(180deg); background-color: #fff !important; }
            img, picture, video, canvas, iframe, embed, object, svg image, [style*="background-image"] {
              filter: invert(1) hue-rotate(180deg);
            }
            """
        case .hideCookieBanners:
            """
            #onetrust-consent-sdk, #onetrust-banner-sdk, #CybotCookiebotDialog, #usercentrics-root, #didomi-host,
            #qc-cmp2-container, .qc-cmp2-container, .fc-consent-root, #truste-consent-track, .truste_box_overlay,
            [id^="sp_message_container"], .cc-window, .cc-banner, #cookie-banner, #cookie-notice, #cookieConsent,
            #cookie-consent, .cookie-banner, .cookie-notice, .cookie-consent, [aria-label="cookieconsent"] {
              display: none !important;
            }
            """
        case .biggerText:
            "html { font-size: 112.5% !important; }"
        }
    }

    /// What a tap adds: the comment and the CSS.
    public var block: String { "/* \(title) */\n\(css)" }

    /// A preset's button is off while its exact block is already in the text.
    public func isApplied(in text: String) -> Bool { text.contains(block) }

    /// What a tap adds to `text`, so the text becomes `text + addition`: a blank line before the block unless the
    /// text is empty, and a closing newline.
    public func addition(to text: String) -> String {
        if text.isEmpty { return block + "\n" }
        return (text.hasSuffix("\n\n") ? "" : text.hasSuffix("\n") ? "\n" : "\n\n") + block + "\n"
    }
}
