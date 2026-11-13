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
    var devToolsWindows: [ChromiumDevToolsWindow] = []
    private var pendingDevToolsWindows: [UInt: ChromiumDevToolsWindow] = [:]
    var quickWindows: [ChromiumQuickWindow] = []
    private var pendingNativeWindows: [UInt: ChromiumAppWindow] = [:]
    var auxiliaryWindows: [NSWindow] = []
    var finished = false
    private var startupWindow: Task<ChromiumAppWindow?, Never>?
    private var applicationMenu: ChromiumApplicationMenu?

    init(runtime: ChromiumRuntime) {
        self.runtime = runtime
        super.init()
    }

    func start() throws {
        runtime.prepareWindow = { [weak self] profile, role in
            guard let self, !finished else { return nil }
            if role == BOAZ_WINDOW_DEVTOOLS {
                let window = ChromiumDevToolsWindow(runtime: runtime, profile: profile)
                let options = window.makeOptions()
                guard let context = options.context else { return nil }
                pendingDevToolsWindows[UInt(bitPattern: context)] = window
                return options
            }
            guard role == BOAZ_WINDOW_BROWSING else { return nil }
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
            guard let self, let context else { return }
            if let inspector = pendingDevToolsWindows.removeValue(forKey: UInt(bitPattern: context)) {
                devToolsWindows.append(inspector)
                do { try inspector.adoptNativeWindow(handle) }
                catch { model.showToast(error.localizedDescription); _ = runtime.api.close_window?(handle) }
                return
            }
            guard let window = pendingNativeWindows.removeValue(forKey: UInt(bitPattern: context)) else { return }
            windows.append(window)
            do { try window.adoptNativeWindow(handle) }
            catch {
                model.showToast(error.localizedDescription)
                _ = runtime.api.close_window?(handle)
            }
        }
        runtime.pageActivated = { [weak self] window, page in
            guard let owner = self?.windows.first(where: { $0.handle == window }),
                  owner.browser.peek?.nativePage == nil else { return }
            owner.browser.activateChromiumPageFromEngine(page)
        }
        runtime.pageCreated = { [weak self] window, page, active in
            guard let self else { return }
            if let inspector = devToolsWindows.first(where: { $0.handle == window }) {
                do { try inspector.adoptPage(page) }
                catch { model.showToast(error.localizedDescription) }
                return
            }
            guard let owner = windows.first(where: { $0.handle == window }) else { return }
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
            } else if let index = devToolsWindows.firstIndex(where: { $0.handle == handle }) {
                let window = devToolsWindows.remove(at: index)
                profile = window.profile
                window.finishClose()
            } else { return }
            if !windows.contains(where: { $0.profile == profile }),
               !quickWindows.contains(where: { $0.profile == profile }),
               !devToolsWindows.contains(where: { $0.profile == profile }),
               !pendingDevToolsWindows.values.contains(where: { $0.profile == profile }),
               !pendingNativeWindows.values.contains(where: { $0.profile == profile }) {
                do { try runtime.releaseProfile(profile) }
                catch { model.showToast(error.localizedDescription) }
            }
        }
        runtime.protectedMedia = { [weak self] page, navigation, profile, key in
            self?.windows.forEach {
                $0.browser.protectedMediaRequested(page: page, navigation: navigation, profile: profile, keySystem: key)
            }
        }
        runtime.pageEvent = { [weak self] handle, event in
            self?.windows.forEach { $0.browser.chromiumPageEvent(handle, event: event) }
            if event == BOAZ_HOST_PAGE_CLOSE_CANCELLED { self?.model.isQuitting = false }
        }
        runtime.shutdownReady = { [self] in
            ChromiumAutomation.shared.stop()
            finished = true
            legacyDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            windows.forEach { $0.finishClose() }
            windows.removeAll()
            quickWindows.forEach { $0.finishClose() }
            quickWindows.removeAll()
            devToolsWindows.forEach { $0.finishClose() }
            devToolsWindows.removeAll()
            pendingDevToolsWindows.values.forEach { $0.finishClose() }
            pendingDevToolsWindows.removeAll()
            pendingNativeWindows.values.forEach { $0.finishClose() }
            pendingNativeWindows.removeAll()
            auxiliaryWindows.forEach { $0.close() }
            auxiliaryWindows.removeAll()
        }
        runtime.externalURLs = { [weak self] urls in
            guard let self else { return }
            externalURLBatches.append(urls)
            drainExternalURLs()
        }
        try runtime.startCallbacks()
        ChromiumAutomation.shared.start()
        // Chromium retains its AppController delegate and termination machinery.
        NotificationCenter.default.addObserver(self, selector: #selector(willTerminate),
            name: NSApplication.willTerminateNotification, object: nil)
        installMenu()
        model.registerNativeOpenWindow { [weak self] id, url in
            Task { @MainActor in await self?.openScene(id, url: url) }
        }
        legacyDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        Task { @MainActor in _ = await ensureMainWindow() }
    }

    private func ensureMainWindow() async -> ChromiumAppWindow? {
        if let window = windows.first { return window }
        if let startupWindow { return await startupWindow.value }
        let task = Task { @MainActor [weak self] () -> ChromiumAppWindow? in
            guard let self, !finished else { return nil }
            await openScene("main", url: nil)
            return windows.last
        }
        startupWindow = task
        let window = await task.value
        startupWindow = nil
        return window
    }

    private var externalURLBatches: [[URL]] = []
    private var routingExternalURLs = false

    private func drainExternalURLs() {
        guard !routingExternalURLs else { return }
        routingExternalURLs = true
        Task { @MainActor in
            defer { routingExternalURLs = false }
            while !externalURLBatches.isEmpty && !finished {
                let urls = externalURLBatches.removeFirst()
                for url in urls {
                    guard url.scheme?.lowercased() == "boaz" else {
                        model.openExternal([url])
                        continue
                    }
                    guard let command = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          command.host == "devtools", command.user == nil, command.password == nil,
                          command.port == nil, command.path.isEmpty, command.fragment == nil else { continue }
                    let items = command.queryItems ?? []
                    guard items.count <= 1, items.allSatisfy({ $0.name == "url" }) else { continue }
                    var target: URL?
                    if let item = items.first {
                        guard let value = item.value, let parsed = URL(string: value),
                              ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
                              parsed.host?.isEmpty == false else { continue }
                        target = parsed
                    }
                    var owner = windows.first(where: { $0.window.isKeyWindow }) ?? windows.first
                    if owner == nil {
                        owner = await ensureMainWindow()
                    }
                    guard let owner, !finished else { continue }
                    if let target { owner.browser.openTab(target) }
                    guard let tab = owner.browser.activeTab else {
                        model.showToast("Open a page before opening Developer Tools.")
                        continue
                    }
                    do {
                        let page = try owner.browser.enginePage(for: tab)
                        if let adapter = page.adapter as? ChromiumEnginePageAdapter {
                            try adapter.showDevTools(BOAZ_DEVTOOLS_SHOW)
                        } else {
                            model.showToast("Use the page's Inspect Element action for this WebKit page.")
                        }
                    } catch { model.showToast(error.localizedDescription) }
                    owner.window.makeKeyAndOrderFront(nil)
                }
            }
        }
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
    private var confirmingQuit = false
    @objc private func quit() {
        guard !confirmingQuit else { return }
        confirmingQuit = true
        Task {
            defer { confirmingQuit = false }
            for window in windows {
                guard await window.confirmWebKitClose() else { return }
            }
            model.isQuitting = true
            do { try runtime.requestShutdown() }
            catch { model.isQuitting = false; showError(error.localizedDescription) }
        }
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
