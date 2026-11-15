import AppKit
import BoazKit

/// Share… and Send to Your Devices from a page's context menu, shown at the pointer: the menu just closed there.
@MainActor
enum PageSharing {
    /// The sharing picker (AirDrop, Messages, Mail, Notes…) for an address, or for the image at `url`.
    static func share(_ url: URL, image: Bool, in window: NSWindow) {
        guard let anchor = pointer(in: window) else { return }
        guard image else { return show([url], at: anchor) }
        Task {
            // An image that doesn't load without the page's cookies is shared by its address.
            if let file = await imageFile(url) { show([file], at: anchor) }
            else if url.scheme == "http" || url.scheme == "https" { show([url], at: anchor) }
        }
    }

    /// The user's other devices; choosing one sends the page there (`MacModel.send`).
    static func sendToDevices(_ url: URL, title: String, in spaceID: String?, window: NSWindow, model: MacModel) {
        guard let (view, point) = pointer(in: window) else { return }
        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: "Send to Your Devices"))
        let devices = model.otherDevices
        if devices.isEmpty { menu.addItem(NSMenuItem(title: "No Other Devices", action: nil, keyEquivalent: "")) }
        for device in devices {
            let action = MenuAction { model.send(url, title: title, in: spaceID, to: device) }
            let item = NSMenuItem(title: device.name, action: #selector(MenuAction.run(_:)), keyEquivalent: "")
            item.image = NSImage(systemSymbolName: device.symbolName, accessibilityDescription: nil)
            item.target = action
            item.representedObject = action
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: point, in: view)
    }

    /// Kept inside the window: a menu opened from the keyboard or VoiceOver leaves the pointer anywhere.
    private static func pointer(in window: NSWindow) -> (view: NSView, point: NSPoint)? {
        guard let view = window.contentView else { return nil }
        let point = view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return (view, NSPoint(x: min(max(point.x, view.bounds.minX), view.bounds.maxX),
                              y: min(max(point.y, view.bounds.minY), view.bounds.maxY)))
    }

    private static func show(_ items: [Any], at anchor: (view: NSView, point: NSPoint)) {
        guard anchor.view.window != nil else { return }
        NSSharingServicePicker(items: items).show(relativeTo: NSRect(origin: anchor.point, size: NSSize(width: 1, height: 1)),
                                                  of: anchor.view, preferredEdge: .minY)
    }

    /// The image (a data: image too) in a temporary file named as the site names it, or nil when it doesn't load.
    /// Ephemeral, so the download leaves no cookies or cache behind, as an Incognito page needs.
    private static func imageFile(_ url: URL) async -> URL? {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              response.mimeType?.hasPrefix("image/") == true else { return nil }
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            .appending(path: response.suggestedFilename ?? "Image")
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
            return file
        } catch {
            return nil
        }
    }
}

/// A menu item's action; the item keeps it as its represented object.
private final class MenuAction: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run(_ sender: NSMenuItem) { action() }
}

extension Device {
    /// Boaz records only iOS or macOS, so an iPad is known by its name.
    var symbolName: String {
        switch platform {
        case .iOS: name.localizedCaseInsensitiveContains("iPad") ? "ipad" : "iphone"
        case .macOS: "laptopcomputer"
        }
    }
}
