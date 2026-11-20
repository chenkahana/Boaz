import AppKit
import WebKit

/// Native sheets for a page's `alert`/`confirm`/`prompt` and the file picker behind `<input type=file>`.
struct MacDialogs: WebPage.DialogPresenting {
    func handleJavaScriptAlert(message: String, initiatedBy frame: WebPage.FrameInfo) async {
        _ = await run(alert(message, from: frame, buttons: ["OK"]))
    }

    func handleJavaScriptConfirm(message: String, initiatedBy frame: WebPage.FrameInfo) async -> WebPage.JavaScriptConfirmResult {
        await run(alert(message, from: frame, buttons: ["OK", "Cancel"])) == .alertFirstButtonReturn ? .ok : .cancel
    }

    func handleJavaScriptPrompt(message: String, defaultText: String?,
                                initiatedBy frame: WebPage.FrameInfo) async -> WebPage.JavaScriptPromptResult {
        let alert = alert(message, from: frame, buttons: ["OK", "Cancel"])
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return await run(alert) == .alertFirstButtonReturn ? .ok(field.stringValue) : .cancel
    }

    func handleFileInputPrompt(parameters: WKOpenPanelParameters,
                               initiatedBy frame: WebPage.FrameInfo) async -> WebPage.FileInputPromptResult {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        let response = if let window = NSApp.keyWindow { await panel.beginSheetModal(for: window) } else { panel.runModal() }
        return response == .OK ? .selected(panel.urls) : .cancel
    }

    private func alert(_ message: String, from frame: WebPage.FrameInfo, buttons: [String]) -> NSAlert {
        let alert = NSAlert()
        let host = frame.securityOrigin.host
        alert.messageText = host.isEmpty ? "This page says" : "\(host) says"
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert
    }

    private func run(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        if let window = NSApp.keyWindow { await alert.beginSheetModal(for: window) } else { alert.runModal() }
    }
}

/// Links that leave Boaz for another app (`mailto:`, `tel:`, an app's own scheme). WebKit would load one and
/// fail with a raw "Can't Open This Page" error; instead Boaz asks first, like the Chromium build's native
/// dialog, and only then hands the link to the app.
enum ExternalLinkOpener {
    /// Whether `url` names another app's scheme that some app can open. Schemes a page may load in place
    /// (about:, blob:, data:, file:, javascript:) are not.
    static func handles(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return !["about", "blob", "data", "file", "javascript"].contains(scheme)
    }

    /// Asks whether to open `url` in its app, then does. With no app to take it, says so and stays put.
    @MainActor
    static func confirmAndOpen(_ url: URL, from host: String?) async {
        guard let appURL = NSWorkspace.shared.urlForApplication(toOpen: url) else {
            MacModel.shared.showToast("No app is available to open this link.")
            return
        }
        let appName = Bundle(url: appURL)?.infoDictionary?["CFBundleName"] as? String
            ?? appURL.deletingPathExtension().lastPathComponent
        let alert = NSAlert()
        alert.messageText = "Open \(appName)?"
        if let host, !host.isEmpty {
            alert.informativeText = "\(host) wants to open this link in \(appName)."
        } else {
            alert.informativeText = "This page wants to open this link in \(appName)."
        }
        // Return must not launch an app: Open answers only to a click, Cancel is Escape and the default.
        let open = alert.addButton(withTitle: "Open \(appName)")
        open.keyEquivalent = ""
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\u{1B}"
        alert.window.defaultButtonCell = nil
        alert.window.makeFirstResponder(cancel)
        let answer: NSApplication.ModalResponse = if let window = NSApp.keyWindow {
            await alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
        if answer == .alertFirstButtonReturn, !NSWorkspace.shared.open(url) {
            MacModel.shared.showToast("No app is available to open this link.")
        }
    }
}

/// Files a page can't display (or marks as attachments) go to ~/Downloads instead.
enum PageDownloads {
    /// Whether a response should be saved rather than shown.
    static func shouldDownload(_ response: WebPage.NavigationResponse) -> Bool {
        if !response.canShowMimeType { return true }
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
        return disposition?.lowercased().hasPrefix("attachment") == true
    }

    /// Fetches `url` with the page's cookies, saves it to ~/Downloads and says so.
    static func start(_ url: URL, store: WKWebsiteDataStore) {
        let model = MacModel.shared
        model.showToast("Downloading \(url.lastPathComponent.isEmpty ? url.host() ?? "file" : url.lastPathComponent)…")
        Task {
            do {
                let (file, name) = try await Downloads.save(url, dataStore: store)
                // Bounces the Downloads stack in the Dock, as Safari does.
                DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: file.path)
                model.showToast("Downloaded \(name)")
            } catch {
                model.showToast("Download failed")
            }
        }
    }
}

/// WebKit's own Download Linked File starts a download that `WebPage` never hands over, so it did nothing. The item
/// instead runs the menu's Open Link in New Window, and the request for that new window is saved as a download
/// (`takeRequest`), with the link's address and the page's cookies as WebKit resolved them.
enum LinkDownloadMenu {
    private static var requestedAt: Date?

    static func install() {
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil,
                                               queue: .main) { note in
            // Posted on the main queue, where menus live.
            nonisolated(unsafe) let menu = note.object as? NSMenu
            MainActor.assumeIsolated {
                guard let menu, let download = item("DownloadLinkedFile", in: menu),
                      let open = item("OpenLinkInNewWindow", in: menu) else { return }
                download.target = Trampoline.shared
                download.action = #selector(Trampoline.download(_:))
                download.representedObject = open
            }
        }
    }

    /// Whether this new-window request is the link a Download Linked File asked for. Asked once per request.
    static func takeRequest() -> Bool {
        defer { requestedAt = nil }
        return requestedAt.map { Date.now.timeIntervalSince($0) < 2 } ?? false
    }

    private static func item(_ name: String, in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.identifier?.rawValue == "WKMenuItemIdentifier" + name }
    }

    private final class Trampoline: NSObject {
        static let shared = Trampoline()

        @objc func download(_ sender: NSMenuItem) {
            guard let open = sender.representedObject as? NSMenuItem, let action = open.action else { return }
            requestedAt = .now
            NSApp.sendAction(action, to: open.target, from: open)
        }
    }
}
