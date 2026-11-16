#if BOAZ_CHROMIUM
import AppKit
import BoazKit
import SwiftUI

@MainActor private var chromiumApplication: ChromiumApplication?

/// `BackgroundPage`'s window for `profileID`.
@MainActor func chromiumBackgroundWindow(profileID: String, at url: URL) async throws -> ChromiumBackgroundWindow {
    guard let chromiumApplication else { throw EnginePageError.unavailable }
    return try await chromiumApplication.backgroundWindow(profileID: profileID, at: url)
}

@MainActor func closeChromiumBackgroundWindows(keeping profileIDs: Set<String>) {
    chromiumApplication?.backgroundWindows.filter { !profileIDs.contains($0.profile.identity.id) }.forEach { $0.close() }
}

@MainActor
private final class ChromiumApplication: NSObject {
    let runtime: ChromiumRuntime
    let model = MacModel.shared
    let legacyDelegate = AppDelegate()
    var windows: [ChromiumAppWindow] = []
    var devToolsWindows: [ChromiumDevToolsWindow] = []
    private var pendingDevToolsWindows: [UInt: ChromiumDevToolsWindow] = [:]
    var quickWindows: [ChromiumQuickWindow] = []
    var backgroundWindows: [ChromiumBackgroundWindow] = []
    private var pendingNativeWindows: [UInt: ChromiumAppWindow] = [:]
    var auxiliaryWindows: [NSWindow] = []
    private var settings: ChromiumSettingsWindow?
    var finished = false
    private var startupWindow: Task<ChromiumAppWindow?, Never>?
    private var defaultsObserver: NSObjectProtocol?
    private var appliedAutomaticPiP: Bool?
    private var appliedPageAssistant: Bool?
    private var appliedMenuShortcuts: [KeyboardShortcut?]?
    private var appliedSearchEngine: SearchEngine?
    private var applicationMenu: ChromiumApplicationMenu?

    init(runtime: ChromiumRuntime) {
        self.runtime = runtime
        super.init()
    }

    func start() throws {
        runtime.prepareWindow = { [weak self] profile, role in
            guard let self, !finished else { return nil }
            // Chrome's popup windows (windows.create({type: "popup"}), window.open with features) have one page and
            // no sidebar, with a read-only location field (DevTools' window has none).
            if role == BOAZ_WINDOW_DEVTOOLS || role == BOAZ_WINDOW_POPUP {
                let window = ChromiumDevToolsWindow(runtime: runtime, profile: profile,
                                                    showsLocation: role == BOAZ_WINDOW_POPUP)
                if role == BOAZ_WINDOW_POPUP {
                    window.window.title = ""
                    window.window.identifier = NSUserInterfaceItemIdentifier("screen.popupWindow")
                }
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
                // A popup keeps the frame its opener asked for; adopting centers DevTools' window.
                let requested = inspector.window.identifier?.rawValue == "screen.popupWindow" ? inspector.window.frame : nil
                do {
                    try inspector.adoptNativeWindow(handle)
                    if let requested { inspector.window.setFrame(requested, display: true) }
                }
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
            ChromiumPasswordSuggestions.shared.dismiss()
            ChromiumPasswordSave.shared.dismiss()
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
            // A background window shows nothing of its own, but Chromium can still route a foreign page into it
            // (an extension's clients.openWindow, chrome.tabs.create, a focused windows.update): open it where
            // someone can see it instead of silently dropping it.
            if let background = backgroundWindows.first(where: { $0.handle == window }) {
                Task { [weak self] in await self?.adoptForeignBackgroundPage(page, profile: background.profile) }
                return
            }
            guard let owner = windows.first(where: { $0.handle == window }) else { return }
            do { try owner.browser.adoptChromiumPage(page, active: active) }
            catch { model.showToast(error.localizedDescription) }
        }
        runtime.windowClosed = { [weak self] handle in
            ChromiumPasswordSuggestions.shared.dismiss()
            ChromiumPasswordSave.shared.dismiss()
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
            } else if let index = backgroundWindows.firstIndex(where: { $0.handle == handle }) {
                let window = backgroundWindows.remove(at: index)
                profile = window.profile
                window.finishClose()
            } else { return }
            releaseProfileIfUnused(profile)
        }
        runtime.devToolsDockChanged = { [weak self] handle, current, last in
            guard let self, let owner = windows.first(where: { $0.handle == handle }) else { return }
            owner.browser.devToolsDockSide = current
            owner.browser.devToolsLastDockSide = last
            if !owner.browser.isIncognito { model.saveOpenWindows() }
        }
        runtime.passwordSubmission = { [weak self] page, target, origin, username, password in
            let mainWindow = self?.windows.first(where: {
                ($0.browser.activeEnginePage?.adapter as? ChromiumEnginePageAdapter)?.handle == page.handle
                    && $0.window.isKeyWindow
            })?.window
            let quickWindow = self?.quickWindows.first(where: {
                $0.chromiumPageHandle == page.handle && $0.window.isKeyWindow
            })?.window
            guard let window = mainWindow ?? quickWindow else { target.release(); return }
            ChromiumPasswordSave.shared.offer(on: page, target: target, sourceOrigin: origin,
                username: username, password: password, window: window)
        }
        runtime.passwordFocus = { [weak self] page, sequence, target, bounds in
            let mainWindow = self?.windows.first(where: {
                ($0.browser.activeEnginePage?.adapter as? ChromiumEnginePageAdapter)?.handle == page.handle
                    && $0.window.isKeyWindow
            })?.window
            let quickWindow = self?.quickWindows.first(where: {
                $0.chromiumPageHandle == page.handle && $0.window.isKeyWindow
            })?.window
            guard let window = mainWindow ?? quickWindow else {
                target?.release()
                ChromiumPasswordSuggestions.shared.dismiss(page: page.handle)
                return
            }
            ChromiumPasswordSuggestions.shared.focus(page: page, sequence: sequence,
                target: target, screenBounds: bounds, window: window)
        }
        runtime.protectedMedia = { [weak self] page, navigation, profile, key in
            self?.windows.forEach {
                $0.browser.protectedMediaRequested(page: page, navigation: navigation, profile: profile, keySystem: key)
            }
        }
        runtime.pageEvent = { [weak self] handle, event in
            ChromiumPasswordSave.shared.invalidate(page: handle)
            if event == BOAZ_HOST_PAGE_CLOSING || event == BOAZ_HOST_PAGE_CLOSED ||
                event == BOAZ_HOST_PAGE_RENDERER_FAILED || event == BOAZ_HOST_PAGE_VIEW_WILL_CHANGE {
                ChromiumPasswordSuggestions.shared.dismiss(page: handle)
            }
            self?.windows.forEach { $0.browser.chromiumPageEvent(handle, event: event) }
            if event == BOAZ_HOST_PAGE_CLOSE_CANCELLED { self?.model.isQuitting = false }
        }
        runtime.shutdownReady = { [self] in
            ChromiumPasswordSuggestions.shared.dismiss()
            ChromiumPasswordSave.shared.dismiss()
            ChromiumAutomation.shared.stop()
            finished = true
            if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
            defaultsObserver = nil
            legacyDelegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            windows.forEach { $0.finishClose() }
            windows.removeAll()
            quickWindows.forEach { $0.finishClose() }
            quickWindows.removeAll()
            devToolsWindows.forEach { $0.finishClose() }
            devToolsWindows.removeAll()
            backgroundWindows.forEach { $0.finishClose() }
            backgroundWindows.removeAll()
            pendingDevToolsWindows.values.forEach { $0.finishClose() }
            pendingDevToolsWindows.removeAll()
            pendingNativeWindows.values.forEach { $0.finishClose() }
            pendingNativeWindows.removeAll()
            auxiliaryWindows.forEach { $0.close() }
            settings?.close()
            auxiliaryWindows.removeAll()
        }
        runtime.reopenRequested = { [weak self] in
            Task { @MainActor in await self?.reopen() }
        }
        runtime.askAboutPage = { [weak self] page, selection in
            self?.windows.forEach { $0.browser.askAboutPage(page, selection: selection) }
        }
        runtime.menuCommand = { [weak self] page, command, url, title in
            self?.runMenuCommand(command, page: page, url: url, title: title)
        }
        runtime.externalURLs = { [weak self] urls in
            guard let self else { return }
            externalURLBatches.append(urls)
            drainExternalURLs()
        }
        try runtime.startCallbacks()
        try applyAutomaticPiPPreference()
        applyPageAssistantPreference()
        applyMenuShortcuts()
        applySearchEngine()
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.defaultsChanged() }
            }
        ChromiumAutomation.shared.start()
        // Chromium retains its AppController delegate and termination machinery.
        NotificationCenter.default.addObserver(self, selector: #selector(willTerminate),
            name: NSApplication.willTerminateNotification, object: nil)
        installMenu()
        model.registerNativeOpenWindow({ [weak self] id, url in
            Task { @MainActor in await self?.openScene(id, url: url) }
        }, openTab: { [weak self] tabID in
            Task { @MainActor in await self?.openScene("main", url: nil, tabID: tabID) }
        })
        legacyDelegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        Task { @MainActor in _ = await ensureMainWindow() }
    }

    /// `profileID`'s `ChromiumBackgroundWindow`, opened at `url` on first use.
    func backgroundWindow(profileID: String, at url: URL) async throws -> ChromiumBackgroundWindow {
        func open() -> ChromiumBackgroundWindow? {
            backgroundWindows.first { $0.profile.identity.id == profileID && !$0.isClosing }
        }
        if let window = open() { return window }
        try await runtime.prepareBlockingAssets()
        let profile = try await runtime.prepareProfile(.init(id: profileID, isPrivate: false))
        guard !finished, !model.isQuitting else { throw EnginePageError.unavailable }
        if let window = open() { return window }
        let window: ChromiumBackgroundWindow
        do { window = try ChromiumBackgroundWindow(runtime: runtime, profile: profile) }
        catch {
            // Nothing holds this profile now that the window itself never came to be.
            releaseProfileIfUnused(profile)
            throw error
        }
        window.closeFailed = { [weak self, weak window] in
            guard let self, let window else { return }
            forgetBackgroundWindow(window)
        }
        backgroundWindows.append(window)
        do { try window.load(url) } catch { window.close(); throw error }
        return window
    }

    /// A page Chromium routed into `profile`'s background window despite it showing nothing of its own: opened in
    /// a real window of that profile if one is open, else the frontmost window (and said so), then closed here.
    private func adoptForeignBackgroundPage(_ page: EnginePage, profile: ChromiumProfile) async {
        defer { _ = try? page.close() }
        var url = page.state.url
        var waited = 0
        while url == nil, page.state.lifecycle == .active, waited < 50 {
            try? await Task.sleep(for: .milliseconds(100))
            url = page.state.url
            waited += 1
        }
        guard let url, !finished else { return }
        if let owner = windows.first(where: { $0.profile == profile }) {
            owner.browser.openTab(url)
        } else if let owner = windows.first(where: { $0.window.isKeyWindow }) ?? windows.first {
            owner.browser.openTab(url)
            model.showToast("Opened a page in another window: none of its profile was open.")
        }
    }

    /// `profile` is released once no window, pending or adopted, still uses it.
    private func releaseProfileIfUnused(_ profile: ChromiumProfile) {
        guard !windows.contains(where: { $0.profile == profile }),
              !quickWindows.contains(where: { $0.profile == profile }),
              !devToolsWindows.contains(where: { $0.profile == profile }),
              !backgroundWindows.contains(where: { $0.profile == profile }),
              !pendingDevToolsWindows.values.contains(where: { $0.profile == profile }),
              !pendingNativeWindows.values.contains(where: { $0.profile == profile }) else { return }
        do { try runtime.releaseProfile(profile) }
        catch { model.showToast(error.localizedDescription) }
    }

    /// Drops `window` from `backgroundWindows` and forgets its handle in the runtime, for the path where
    /// `close_window` itself failed and the host will never confirm the close through `windowClosed`.
    private func forgetBackgroundWindow(_ window: ChromiumBackgroundWindow) {
        guard let index = backgroundWindows.firstIndex(where: { $0 === window }) else { return }
        backgroundWindows.remove(at: index)
        runtime.forgetWindowProfile(window.handle)
        releaseProfileIfUnused(window.profile)
    }

    private func reopen() async {
        guard !finished, !model.isQuitting else { return }
        let candidates = windows.map(\.window) + quickWindows.map(\.window)
        let existing = NSApp.orderedWindows.first { candidate in
            candidates.contains { $0 === candidate }
        } ?? candidates.last
        let window: NSWindow?
        if let existing { window = existing }
        else { window = await ensureMainWindow()?.window }
        guard !finished, !model.isQuitting, let window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
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
                            model.showToast("Developer tools aren't available on this page.")
                        }
                    } catch { model.showToast(error.localizedDescription) }
                    owner.window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }

    func openScene(_ id: String, url: URL?, tabID: String? = nil) async {
        guard !finished else { return }
        var explicitProfileID: String?
        if let tabID {
            guard id == "main", let tab = model.item(tabID), tab.kind == .tab,
                  model.sidebar.profiles.contains(where: { $0.id == (tab.profileID ?? "default") }) else {
                showError("This tab or its profile is no longer available.")
                return
            }
            explicitProfileID = tab.profileID ?? "default"
        }
        await model.start()
        while model.sidebar.spaces.isEmpty && model.loadError == nil {
            guard !finished else { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard !finished else { return }
        if let error = model.loadError { showError(error); return }
        switch id {
        case "settings":
            let controller = settings ?? ChromiumSettingsWindow(model: model)
            settings = controller
            controller.showWindow(nil)
        case "history": present(HistoryWindow().environment(model), title: "History")
        case "archive": present(ArchiveWindow().environment(model), title: "Archive")
        case "little":
            let ruleProfileID = url.flatMap(model.ruleSpace(for:))?.profileID
            let profileID = ruleProfileID
                ?? (model.sidebar.profiles.first(where: \.isDefault) ?? model.sidebar.profiles.first)?.id ?? "default"
            do {
                try await runtime.prepareBlockingAssets()
                guard !finished else { return }
                let profile = try await runtime.prepareProfile(.init(id: profileID, isPrivate: false))
                await ChromiumLegacyStore.importWebKitCookies(runtime: runtime, profile: profile, store: model.dataStore(for: profileID))
                guard !finished else { return }
                let window = try ChromiumQuickWindow(runtime: runtime, profile: profile, url: url, model: model)
                quickWindows.append(window)
            } catch { showError(error.localizedDescription) }
        default:
            let isPrivate = id == "incognito"
            if let explicitProfileID, !model.sidebar.profiles.contains(where: { $0.id == explicitProfileID }) {
                showError("This tab or its profile is no longer available.")
                return
            }
            let restoration = isPrivate || tabID != nil || url != nil ? nil : model.claimNativeSavedWindow()
            var created = false
            defer {
                if !created, let restoration { model.finishNativeRestoration(restoration, succeeded: false) }
            }
            let saved = restoration?.saved
            let savedSpaceProfile = model.space(saved?.spaceID)?.profileID
            let savedTabProfile = model.item(saved?.tabID).map { $0.profileID ?? "default" }
            let fallback = model.sidebar.spaces.first?.profileID
                ?? model.sidebar.profiles.first(where: \.isDefault)?.id ?? "default"
            let candidates = [explicitProfileID, savedSpaceProfile, savedTabProfile, fallback].compactMap { $0 }
            let profileID = candidates.first(where: { candidate in
                model.sidebar.profiles.contains { $0.id == candidate }
            }) ?? fallback
            // A private window is its profile's off-the-record session, shared by that profile's private
            // windows (as Chrome's incognito), so the profile itself opens first.
            let identity = EngineProfileIdentity(id: profileID, isPrivate: isPrivate)
            do {
                try await runtime.prepareBlockingAssets()
                guard !finished else { return }
                if isPrivate { _ = try await runtime.prepareProfile(.init(id: profileID, isPrivate: false)) }
                let profile = try await runtime.prepareProfile(identity)
                if !isPrivate, model.sidebar.profiles.contains(where: { $0.id == profile.identity.id }) {
                    await ChromiumLegacyStore.importWebKitCookies(runtime: runtime, profile: profile, store: model.dataStore(for: profile.identity.id))
                }
                guard !finished else { return }
                if let tabID {
                    guard let tab = model.item(tabID), tab.kind == .tab, (tab.profileID ?? "default") == profile.identity.id,
                          model.sidebar.profiles.contains(where: { $0.id == profile.identity.id }) else {
                        showError("This tab or its profile is no longer available.")
                        return
                    }
                }
                let window = try ChromiumAppWindow(runtime: runtime, profile: profile, model: model,
                                                    restoration: restoration, initialTabID: tabID)
                windows.append(window)
                created = true
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

    private func applyAutomaticPiPPreference() throws {
        let enabled = PictureInPicture.floatsWhenLeaving
        guard appliedAutomaticPiP != enabled else { return }
        guard let update = runtime.api.set_automatic_picture_in_picture_enabled,
              update(enabled ? 1 : 0) == BOAZ_HOST_OK else { throw EnginePageError.unavailable }
        appliedAutomaticPiP = enabled
    }
    /// The context menu offers Explain/Ask About This Page when the AI features are shown.
    private func applyPageAssistantPreference() {
        let enabled = AIFeatures.showsEntryPoints(
            preference: UserDefaults.standard.object(forKey: AIFeatures.preferenceKey) as? Bool ?? true)
        guard appliedPageAssistant != enabled, let update = runtime.api.set_page_assistant_enabled,
              update(enabled ? 1 : 0) == BOAZ_HOST_OK else { return }
        appliedPageAssistant = enabled
    }
    /// The context menu shows the rebindable shortcuts for Back, Forward, Reload, View Source and Picture in
    /// Picture. Key binding changes are saved to user defaults, which calls this again.
    private func applyMenuShortcuts() {
        let commands: [(BrowserCommand, BoazHostMenuShortcutCommand)] = [
            (.goBack, BOAZ_MENU_SHORTCUT_BACK), (.goForward, BOAZ_MENU_SHORTCUT_FORWARD),
            (.reload, BOAZ_MENU_SHORTCUT_RELOAD), (.viewSource, BOAZ_MENU_SHORTCUT_VIEW_SOURCE),
            (.pictureInPicture, BOAZ_MENU_SHORTCUT_PICTURE_IN_PICTURE),
        ]
        let bindings = commands.map { model.keyBindings.shortcut($0.0) }
        guard appliedMenuShortcuts != bindings, let update = runtime.api.set_menu_shortcuts else { return }
        let shortcuts = zip(commands, bindings).compactMap { command, binding -> BoazHostMenuShortcut? in
            guard let binding, let key = String(binding.key.character).utf16.first else { return nil }
            return BoazHostMenuShortcut(command: command.1, key: key, modifiers: UInt64(binding.modifierFlags.rawValue))
        }
        guard shortcuts.withUnsafeBufferPointer({ update($0.baseAddress, $0.count) }) == BOAZ_HOST_OK else { return }
        appliedMenuShortcuts = bindings
    }
    /// The context menu's "Search <engine> for …" follows Boaz's search engine, made every profile's default search
    /// provider. Changing it in Settings saves user defaults, which calls this again.
    private func applySearchEngine() {
        let engine = Preferences.searchEngine
        guard appliedSearchEngine != engine, let update = runtime.api.set_default_search_provider,
              let host = URL(string: engine.template)?.host() else { return }
        // Chromium's keyword for the engine: duckduckgo.com, google.com, search.brave.com, ...
        let keyword = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let template = engine.template.replacingOccurrences(of: "%@", with: "{searchTerms}")
        guard update(engine.name, keyword, template) == BOAZ_HOST_OK else { return }
        appliedSearchEngine = engine
    }
    /// Context-menu commands Boaz runs instead of Chromium, whose Incognito and split view aren't Boaz's, and Boaz's
    /// own Share… and Send to Your Devices.
    private func runMenuCommand(_ command: BoazHostMenuCommand, page: BoazHostPage, url: URL, title: String) {
        let owner = windows.first { $0.browser.showsChromiumPage(page) }
        let window = owner?.window ?? quickWindows.first(where: { $0.chromiumPageHandle == page })?.window
        switch command {
        case BOAZ_MENU_OPEN_INCOGNITO:
            Task { @MainActor in await openScene("incognito", url: url) }
        case BOAZ_MENU_OPEN_SPLIT:
            owner?.browser.openLinkInSplit(url, from: page)
        case BOAZ_MENU_QR_CODE:
            guard let window else { return }
            QRCodeSheet.present(url, title: title, on: window)
        case BOAZ_MENU_SHARE, BOAZ_MENU_SHARE_IMAGE:
            guard let window else { return }
            PageSharing.share(url, image: command == BOAZ_MENU_SHARE_IMAGE, in: window)
        case BOAZ_MENU_SEND_TO_DEVICES:
            guard let owner else { return }
            PageSharing.sendToDevices(url, title: title, in: owner.browser.spaceID, window: owner.window, model: model)
        default:
            break
        }
    }
    private func defaultsChanged() {
        guard !finished else { return }
        applyPageAssistantPreference()
        applyMenuShortcuts()
        applySearchEngine()
        do { try applyAutomaticPiPPreference() }
        catch { model.showToast("The automatic Picture in Picture preference could not be applied.") }
        do { try runtime.applyBlockingPreference(Preferences.blockTrackers) }
        catch { model.showToast("The tracker-blocking preference could not be applied to every profile.") }
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
            try ChromiumLegacyStore.importMissingPreferences()
            try ChromiumLegacyStore.importWebKitData()
            let app = try ChromiumApplication(runtime: ChromiumRuntime(api: api))
            chromiumApplication = app
            try app.start()
            return BOAZ_HOST_OK
        } catch {
            let alert = NSAlert()
            alert.messageText = "Boaz could not start"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Quit")
            alert.runModal()
            return BOAZ_HOST_UNAVAILABLE
        }
    }
}
#endif
