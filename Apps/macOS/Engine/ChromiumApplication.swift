#if BOAZ_CHROMIUM
import AppKit
import SwiftUI

@MainActor private var chromiumApplication: ChromiumApplication?

@MainActor
private final class ChromiumApplication: NSObject, NSApplicationDelegate {
    let runtime: ChromiumRuntime
    let model = MacModel.shared
    let legacyDelegate = AppDelegate()
    var windows: [ChromiumAppWindow] = []
    var auxiliaryWindows: [NSWindow] = []
    var finished = false

    init(runtime: ChromiumRuntime) {
        self.runtime = runtime
        super.init()
    }

    func start() throws {
        runtime.windowClosed = { [weak self] handle in
            guard let self, let index = windows.firstIndex(where: { $0.handle == handle }) else { return }
            let window = windows.remove(at: index)
            window.finishClose()
            if !windows.contains(where: { $0.profile == window.profile }) {
                do { try runtime.releaseProfile(window.profile) }
                catch { model.showToast(error.localizedDescription) }
            }
        }
        runtime.pageEvent = { [weak self] handle, event in
            self?.windows.forEach { $0.browser.chromiumPageEvent(handle, event: event) }
        }
        runtime.shutdownReady = { [self] in
            finished = true
            legacyDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            windows.forEach { $0.finishClose() }
            windows.removeAll()
            auxiliaryWindows.forEach { $0.close() }
            auxiliaryWindows.removeAll()
        }
        try runtime.startCallbacks()
        NSApp.delegate = self
        installMenu()
        model.registerNativeOpenWindow { [weak self] id, url in
            Task { @MainActor in await self?.openScene(id, url: url) }
        }
        legacyDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        Task { @MainActor in await openScene("main", url: nil) }
    }

    func openScene(_ id: String, url: URL?) async {
        guard !finished else { return }
        await model.start()
        while model.sidebar.spaces.isEmpty && model.loadError == nil {
            guard !finished else { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard !finished else { return }
        if let error = model.loadError { showError(error); return }
        switch id {
        case "settings": present(MacSettingsView().environment(model), title: "Boaz Settings")
        case "history": present(HistoryWindow().environment(model), title: "History")
        case "archive": present(ArchiveWindow().environment(model), title: "Archive")
        case "little": present(QuickWindow(url: url).environment(model), title: "Quick Window")
        default:
            let isPrivate = id == "incognito"
            let identity = EngineProfileIdentity(
                id: isPrivate ? UUID().uuidString : (model.sidebar.spaces.first?.profileID ?? "default"),
                isPrivate: isPrivate)
            do {
                let profile = try await runtime.prepareProfile(identity)
                guard !finished else { return }
                let window = try ChromiumAppWindow(runtime: runtime, profile: profile, model: model)
                windows.append(window)
                if let url { window.browser.openTab(url) }
            } catch { showError(error.localizedDescription) }
        }
    }

    private func present<Content: View>(_ content: Content, title: String) {
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 760, height: 620))
        window.center()
        auxiliaryWindows.append(window)
        window.makeKeyAndOrderFront(nil)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Boaz could not open this window"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func installMenu() {
        let menu = NSMenu()
        let app = NSMenuItem()
        let appMenu = NSMenu(title: "Boaz")
        appMenu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Boaz", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = appMenu
        menu.addItem(app)
        let file = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Window", action: #selector(newWindow), keyEquivalent: "n").target = self
        fileMenu.addItem(withTitle: "New Private Window", action: #selector(newPrivateWindow), keyEquivalent: "").target = self
        fileMenu.addItem(withTitle: "Close", action: #selector(closeTab), keyEquivalent: "w").target = self
        file.submenu = fileMenu
        menu.addItem(file)
        NSApp.mainMenu = menu
    }

    @objc private func settings() { Task { await openScene("settings", url: nil) } }
    @objc private func newWindow() { Task { await openScene("main", url: nil) } }
    @objc private func newPrivateWindow() { Task { await openScene("incognito", url: nil) } }
    @objc private func closeTab() {
        if let window = windows.first(where: { $0.window.isKeyWindow }) { window.browser.closeActive() }
        else { NSApp.keyWindow?.performClose(nil) }
    }

    func application(_ application: NSApplication, open urls: [URL]) { model.openExternal(urls) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if finished { return .terminateNow }
        do { try runtime.requestShutdown() }
        catch { showError(error.localizedDescription) }
        return .terminateCancel
    }
}

@_cdecl("BoazNativeUIStart")
public func boazApplicationStart(_ api: UnsafePointer<BoazHostAPI>?) -> BoazHostResult {
    guard Thread.isMainThread else { return BOAZ_HOST_WRONG_THREAD }
    guard let api else { return BOAZ_HOST_INVALID_ARGUMENT }
    return MainActor.assumeIsolated {
        guard chromiumApplication == nil else { return BOAZ_HOST_UNAVAILABLE }
        do {
            let app = try ChromiumApplication(runtime: ChromiumRuntime(api: api))
            chromiumApplication = app
            try app.start()
            return BOAZ_HOST_OK
        } catch {
            return BOAZ_HOST_UNAVAILABLE
        }
    }
}
#endif
