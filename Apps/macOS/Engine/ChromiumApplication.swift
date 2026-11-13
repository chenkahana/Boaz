#if BOAZ_CHROMIUM
import AppKit
import SwiftUI

@MainActor private var chromiumApplication: ChromiumApplication?

@MainActor
private final class ChromiumApplication: NSObject {
    let runtime: ChromiumRuntime
    let model = MacModel.shared
    let legacyDelegate = AppDelegate()
    var windows: [ChromiumAppWindow] = []
    var quickWindows: [ChromiumQuickWindow] = []
    private var pendingNativeWindows: [UInt: ChromiumAppWindow] = [:]
    var auxiliaryWindows: [NSWindow] = []
    var finished = false
    private var applicationMenu: ChromiumApplicationMenu?

    init(runtime: ChromiumRuntime) {
        self.runtime = runtime
        super.init()
    }

    func start() throws {
        runtime.prepareWindow = { [weak self] profile in
            guard let self, !finished else { return nil }
            do {
                let window = try ChromiumAppWindow(runtime: runtime, profile: profile, model: model,
                    preparedForNativeCreation: true)
                let options = window.makeOptions()
                guard let context = options.context else { return nil }
                pendingNativeWindows[UInt(bitPattern: context)] = window
                return options
            } catch { return nil }
        }
        runtime.windowCreated = { [weak self] handle, context in
            guard let self, let context,
                  let window = pendingNativeWindows.removeValue(forKey: UInt(bitPattern: context)) else { return }
            windows.append(window)
            do { try window.adoptNativeWindow(handle) }
            catch {
                model.showToast(error.localizedDescription)
                _ = runtime.api.close_window?(handle)
            }
        }
        runtime.pageCreated = { [weak self] window, page, active in
            guard let self, let owner = windows.first(where: { $0.handle == window }) else { return }
            do { try owner.browser.adoptChromiumPage(page, active: active) }
            catch { model.showToast(error.localizedDescription) }
        }
        runtime.windowClosed = { [weak self] handle in
            guard let self else { return }
            let profile: ChromiumProfile
            if let index = windows.firstIndex(where: { $0.handle == handle }) {
                let window = windows.remove(at: index)
                profile = window.profile
                window.finishClose()
            } else if let index = quickWindows.firstIndex(where: { $0.handle == handle }) {
                let window = quickWindows.remove(at: index)
                profile = window.profile
                window.finishClose()
            } else { return }
            if !windows.contains(where: { $0.profile == profile }),
               !quickWindows.contains(where: { $0.profile == profile }) {
                do { try runtime.releaseProfile(profile) }
                catch { model.showToast(error.localizedDescription) }
            }
        }
        runtime.pageEvent = { [weak self] handle, event in
            self?.windows.forEach { $0.browser.chromiumPageEvent(handle, event: event) }
            if event == BOAZ_HOST_PAGE_CLOSE_CANCELLED { self?.model.isQuitting = false }
        }
        runtime.shutdownReady = { [self] in
            finished = true
            legacyDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            windows.forEach { $0.finishClose() }
            windows.removeAll()
            quickWindows.forEach { $0.finishClose() }
            quickWindows.removeAll()
            pendingNativeWindows.values.forEach { $0.finishClose() }
            pendingNativeWindows.removeAll()
            auxiliaryWindows.forEach { $0.close() }
            auxiliaryWindows.removeAll()
        }
        runtime.externalURLs = { [weak self] urls in self?.model.openExternal(urls) }
        try runtime.startCallbacks()
        // Chromium retains its AppController delegate and termination machinery.
        NotificationCenter.default.addObserver(self, selector: #selector(willTerminate),
            name: NSApplication.willTerminateNotification, object: nil)
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
        case "little":
            let profileID = (model.sidebar.profiles.first(where: \.isDefault) ?? model.sidebar.profiles.first)?.id ?? "default"
            do {
                let profile = try await runtime.prepareProfile(.init(id: profileID, isPrivate: false))
                guard !finished else { return }
                let window = try ChromiumQuickWindow(runtime: runtime, profile: profile, url: url, model: model)
                quickWindows.append(window)
            } catch { showError(error.localizedDescription) }
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
        let menu = ChromiumApplicationMenu(activeBrowser: { [weak self] in
            self?.windows.first(where: { $0.window.isKeyWindow })?.browser
        }, openScene: { [weak self] id in
            Task { @MainActor in await self?.openScene(id, url: nil) }
        }, quit: { [weak self] in self?.quit() })
        applicationMenu = menu
        menu.install()
    }

    @objc private func willTerminate() {
        guard !finished else { return }
        legacyDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
    }
    @objc private func quit() {
        model.isQuitting = true
        do { try runtime.requestShutdown() }
        catch { model.isQuitting = false; showError(error.localizedDescription) }
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
