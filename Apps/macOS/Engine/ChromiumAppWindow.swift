#if BOAZ_CHROMIUM
import AppKit
import SwiftUI

@MainActor
final class ChromiumAppWindow: NSObject, NSWindowDelegate {
    let runtime: ChromiumRuntime
    let profile: ChromiumProfile
    let browser: BrowserState
    let window: NSWindow
    let contentContainer = NSView()
    let addressField = NSTextField()
    private(set) var handle: BoazHostWindow = 0
    var onClosed: (() -> Void)?
    private let model: MacModel
    private var installed = false
    private var finished = false
    private var closing = false
    private var layoutQueued = false
    private var appliedSplit: (leading: String, trailing: String)?

    init(runtime: ChromiumRuntime, profile: ChromiumProfile, model: MacModel,
         preparedForNativeCreation: Bool = false) throws {
        self.model = model
        self.runtime = runtime
        self.profile = profile
        browser = BrowserState(incognito: profile.identity.isPrivate)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = profile.identity.isPrivate ? "Boaz — Private" : "Boaz"
        window.delegate = self
        window.contentView = contentContainer
        addressField.isHidden = true
        contentContainer.addSubview(addressField)
        browser.chromiumProfileIdentity = profile.identity
        browser.chromiumAddressField = addressField
        browser.activateChromiumPage = { [weak self] page in
            guard let self, self.browser.peek?.nativePage == nil,
                  let adapter = page.adapter as? ChromiumEnginePageAdapter,
                  let activate = runtime.api.activate_page else { return }
            let result = activate(adapter.handle, 1)
            if result != BOAZ_HOST_OK { window.subtitle = "Could not activate page (\(result.rawValue))." }
        }
        addressField.setAccessibilityLabel("Address")
        browser.updateChromiumExternalTabCount = { [weak self] count in
            guard let self, !finished, handle != 0, let update = runtime.api.set_external_tab_count else { return false }
            return update(handle, count) == BOAZ_HOST_OK
        }
        browser.chromiumLayoutChanged = { [weak self] in self?.queueLayout() }
        browser.createChromiumPage = { [weak self] tab in
            guard let self, !self.finished, self.handle != 0 else { throw EnginePageError.closed }
            guard self.profile.identity.isPrivate || tab.profileID == self.profile.identity.id else {
                throw EnginePageError.invalidRequest
            }
            return try self.runtime.createPage(window: self.handle,
                url: tab.url ?? URL(string: "about:blank")!, profile: self.profile.identity,
                javaScriptDisabled: self.browser.devTools[tab.id].javaScriptDisabled)
        }
        browser.createChromiumPeekPage = { [weak self] url in
            guard let self, !finished, handle != 0 else { throw EnginePageError.closed }
            return try runtime.createPage(window: handle, url: url, profile: profile.identity)
        }
        if preparedForNativeCreation { return }
        var options = makeOptions()
        do {
            let created = try runtime.createWindow(profile: profile, options: &options)
            try adoptNativeWindow(created)
        } catch {
            window.delegate = nil
            window.close()
            throw error
        }
    }

    func adoptNativeWindow(_ handle: BoazHostWindow) throws {
        guard !finished, handle != 0, self.handle == 0 || self.handle == handle else {
            throw EnginePageError.invalidRequest
        }
        guard !installed else { return }
        self.handle = handle
        installed = true
        browser.loadChromiumDeveloperExtension = { [weak self] in
            guard let self, !finished, !profile.identity.isPrivate else { return }
            ChromiumExtensionManagement.install(api: runtime.api, handle: handle, window: window, unpacked: true)
        }
        browser.installChromiumExtension = { [weak self] in
            guard let self, !finished, !profile.identity.isPrivate else { return }
            ChromiumExtensionManagement.install(api: runtime.api, handle: handle, window: window)
        }
        browser.manageChromiumExtensions = { [weak self] in
            guard let self, !finished, !profile.identity.isPrivate else { return }
            ChromiumExtensionManagement.present(api: runtime.api, profile: profile.handle, handle: handle, window: window)
        }
        browser.restoreChromiumDockPreferences = { [weak self] current, last in
            guard let self, !finished else { return }
            do { try runtime.restoreDevToolsDockPreferences(window: self.handle, current: current, last: last) }
            catch { model.showToast(error.localizedDescription) }
        }
        browser.chromiumExtensions = ChromiumExtensionActionsModel(api: runtime.api, window: handle,
            activePage: { [weak browser = browser] in
                browser?.activeEnginePage?.adapter as? ChromiumEnginePageAdapter
            })
        let hosting = NSHostingView(rootView: BrowserWindow(browser: browser)
            .environment(model).task { await self.model.start() })
        hosting.frame = contentContainer.bounds
        hosting.autoresizingMask = [.width, .height]
        contentContainer.addSubview(hosting)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func makeOptions() -> BoazHostWindowOptions {
        var options = BoazHostWindowOptions()
        options.size = MemoryLayout<BoazHostWindowOptions>.size
        options.native_nswindow = Unmanaged.passUnretained(window).toOpaque()
        options.context = Unmanaged.passUnretained(self).toOpaque()
        options.content_view = { context in
            let bits: UInt? = MainActor.assumeIsolated {
                guard let context else { return nil }
                let owner = Unmanaged<ChromiumAppWindow>.fromOpaque(context).takeUnretainedValue()
                return UInt(bitPattern: Unmanaged.passUnretained(owner.contentContainer).toOpaque())
            }
            return bits.flatMap { UnsafeMutableRawPointer(bitPattern: $0) }
        }
        options.address_field = { context in
            let bits: UInt? = MainActor.assumeIsolated {
                guard let context else { return nil }
                let owner = Unmanaged<ChromiumAppWindow>.fromOpaque(context).takeUnretainedValue()
                return UInt(bitPattern: Unmanaged.passUnretained(owner.addressField).toOpaque())
            }
            return bits.flatMap { UnsafeMutableRawPointer(bitPattern: $0) }
        }
        options.focus_address = { context in
            MainActor.assumeIsolated {
                guard let context else { return }
                let owner = Unmanaged<ChromiumAppWindow>.fromOpaque(context).takeUnretainedValue()
                owner.queue { $0.browser.commandMode = .currentTab }
            }
        }
        options.focus_toolbar = options.focus_address
        options.handle_key = { context, event in
            MainActor.assumeIsolated {
                guard let context, let event else { return 0 }
                let owner = Unmanaged<ChromiumAppWindow>.fromOpaque(context).takeUnretainedValue()
                let key = Unmanaged<NSEvent>.fromOpaque(event).takeUnretainedValue()
                return owner.handleKey(key) ? 1 : 0
            }
        }
        options.exclusive_access_notice = { context, text, visible in
            MainActor.assumeIsolated {
                guard let context else { return }
                let owner = Unmanaged<ChromiumAppWindow>.fromOpaque(context).takeUnretainedValue()
                let copied = visible != 0 ? text.map { String(cString: $0) } ?? "" : ""
                owner.queue { $0.window.subtitle = copied }
            }
        }
        return options
    }

    private func queueLayout() {
        guard !finished, !layoutQueued else { return }
        layoutQueued = true
        queue { owner in
            owner.layoutQueued = false
            owner.synchronizeLayout()
        }
    }

    private func synchronizeLayout() {
        guard browser.peek?.nativePage == nil else { return }
        guard handle != 0, let getLayout = runtime.api.get_window_layout,
              let setSplit = runtime.api.set_split, let clearSplit = runtime.api.clear_split else {
            window.subtitle = "Chromium split view is unavailable."
            return
        }
        var actual = BoazHostWindowLayout()
        actual.size = MemoryLayout<BoazHostWindowLayout>.size
        var result = getLayout(handle, &actual)
        guard result == BOAZ_HOST_OK else {
            window.subtitle = "Could not read browser layout (\(result.rawValue))."
            return
        }
        if let previous = appliedSplit,
           browser.split?.leading != previous.leading || browser.split?.trailing != previous.trailing {
            let survivor = [previous.leading, previous.trailing].compactMap {
                browser.cachedChromiumPage(for: $0)
            }.first { $0.state.lifecycle == .active }
            let desired = browser.activeTabID.flatMap { browser.cachedChromiumPage(for: $0) }
            if let survivor, let activate = runtime.api.activate_page {
                let switched = actual.active != survivor.handle
                if switched { result = activate(survivor.handle, 0) }
                if result == BOAZ_HOST_OK { result = getLayout(handle, &actual) }
                if result == BOAZ_HOST_OK, actual.second != 0 {
                    if actual.first == survivor.handle || actual.second == survivor.handle {
                        result = clearSplit(handle)
                    } else {
                        result = BOAZ_HOST_UNAVAILABLE
                    }
                }
                let clearResult = result
                if switched, let desired, desired.state.lifecycle == .active {
                    result = activate(desired.handle, 0)
                }
                if clearResult != BOAZ_HOST_OK || result != BOAZ_HOST_OK {
                    window.subtitle = "Could not clear previous split view."
                    return
                }
            } else if [previous.leading, previous.trailing].contains(where: {
                guard let page = browser.cachedChromiumPage(for: $0) else { return false }
                return page.state.lifecycle == .closing
            }) {
                return
            }
            appliedSplit = nil
            result = getLayout(handle, &actual)
            guard result == BOAZ_HOST_OK else {
                window.subtitle = "Could not read updated browser layout (\(result.rawValue))."
                return
            }
        }
        if let split = browser.split {
            guard let first = browser.cachedChromiumPage(for: split.leading),
                  let second = browser.cachedChromiumPage(for: split.trailing),
                  first.state.lifecycle == .active, second.state.lifecycle == .active else {
                if let native = [split.leading, split.trailing].compactMap({ browser.cachedChromiumPage(for: $0) }).first,
                   native.state.lifecycle == .active, let activate = runtime.api.activate_page {
                    result = activate(native.handle, 0)
                    if result == BOAZ_HOST_OK { result = getLayout(handle, &actual) }
                }
                if result == BOAZ_HOST_OK, actual.second != 0 { result = clearSplit(handle) }
                if result == BOAZ_HOST_OK { appliedSplit = nil }
                else { window.subtitle = "Could not update the mixed-engine split view." }
                return
            }
            let ratio = Double(split.fraction)
            if actual.first != first.handle || actual.second != second.handle ||
                actual.vertical != 0 || abs(actual.first_ratio - ratio) > 0.000001 {
                result = setSplit(handle, first.handle, second.handle, 0, ratio)
                if result == BOAZ_HOST_OK, let activeID = browser.activeTabID,
                   let active = browser.cachedChromiumPage(for: activeID),
                   active.handle != first.handle, let activate = runtime.api.activate_page {
                    result = activate(active.handle, 0)
                }
            }
            if result == BOAZ_HOST_OK {
                appliedSplit = (split.leading, split.trailing)
            }
        } else if actual.second != 0 {
            result = clearSplit(handle)
        }
        if result == BOAZ_HOST_OK, let active = browser.activeEnginePage?.adapter as? ChromiumEnginePageAdapter,
           active.state.lifecycle == .active, let activate = runtime.api.activate_page {
            result = activate(active.handle, 0)
        }
        if result != BOAZ_HOST_OK {
            window.subtitle = "Could not update split view (\(result.rawValue))."
        }
    }

    private func queue(_ action: @escaping (ChromiumAppWindow) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.finished else { return }
            action(self)
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "l": queue { $0.browser.commandMode = .currentTab }
        case "t": queue { $0.browser.commandMode = .newTab }
        case "w": queue { $0.browser.closeActive() }
        case "r": queue { $0.browser.reload() }
        case "[": queue { $0.browser.goBack() }
        case "]": queue { $0.browser.goForward() }
        default: return false
        }
        return true
    }

    func confirmWebKitClose() async -> Bool {
        guard browser.hasWebKitPages else { return true }
        guard window.attachedSheet == nil else { return false }
        let alert = NSAlert()
        alert.messageText = "Close WebKit pages?"
        alert.informativeText = "This window contains WebKit pages. Closing it may lose unsaved changes."
        alert.addButton(withTitle: "Keep Window Open")
        alert.addButton(withTitle: "Close Window")
        return await alert.beginSheetModal(for: window) == .alertSecondButtonReturn
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !finished else { return true }
        if !closing {
            closing = true
            Task { [weak self] in
                guard let self else { return }
                defer { closing = false }
                guard await confirmWebKitClose(), !finished else { return }
                let result = runtime.api.close_window!(handle)
                if result != BOAZ_HOST_OK { window.subtitle = "Could not close window (\(result.rawValue))." }
            }
        }
        return false
    }

    func finishClose() {
        guard !finished else { return }
        finished = true
        browser.chromiumExtensions = nil
        browser.createChromiumPeekPage = nil
        browser.createChromiumPage = nil
        browser.activateChromiumPage = nil
        browser.updateChromiumExternalTabCount = nil
        browser.chromiumLayoutChanged = nil
        browser.chromiumAddressField = nil
        window.delegate = nil
        window.orderOut(nil)
        window.close()
        onClosed?()
    }
}
#endif
