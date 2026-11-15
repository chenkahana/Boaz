import AppKit

/// Shows the chosen pretzel (Settings ▸ App Icon) on Boaz's Dock tile while Boaz isn't running. The Dock loads this
/// from Boaz.app/Contents/PlugIns (Info.plist key NSDockTilePlugIn); it reads the app's own preference and listens for
/// the app's change notification. While Boaz runs, the app sets its icon itself.
@MainActor @objc(BoazDockTilePlugIn)
final class BoazDockTilePlugIn: NSObject, @preconcurrency NSDockTilePlugIn {
    private static let selectionKey = "appIcon"
    private static let changed = Notification.Name("com.chenkahana.boaz.appIconChanged")

    private var tile: NSDockTile?
    private var observer: NSObjectProtocol?

    /// Boaz.app, three levels up from Contents/PlugIns/BoazDockTile.docktileplugin.
    private var app: Bundle? {
        Bundle(url: Bundle(for: Self.self).bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent())
    }

    func setDockTile(_ dockTile: NSDockTile?) {
        tile = dockTile
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        guard dockTile != nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(forName: Self.changed, object: nil,
                                                                       queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    private func refresh() {
        guard let tile, let app, let domain = app.bundleIdentifier else { return }
        CFPreferencesAppSynchronize(domain as CFString)
        let id = CFPreferencesCopyAppValue(Self.selectionKey as CFString, domain as CFString) as? String
        guard let id, id != "Classic", let image = icon(named: "AppIcon-\(id)", in: app) else {
            tile.contentView = nil   // The bundle's own icon.
            tile.display()
            return
        }
        let view = NSImageView(image: image)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.frame = NSRect(origin: .zero, size: tile.size)
        tile.contentView = view
        tile.display()
    }

    /// The DMG keeps the icons in Resources/BoazResources.bundle; a plain build keeps them in Resources.
    private func icon(named name: String, in app: Bundle) -> NSImage? {
        let resources = app.resourceURL
        let candidates = [resources?.appendingPathComponent("BoazResources.bundle/Contents/Resources/\(name).icns"),
                          resources?.appendingPathComponent("\(name).icns")]
        return candidates.compactMap { $0 }.lazy.compactMap(NSImage.init(contentsOf:)).first
    }
}
