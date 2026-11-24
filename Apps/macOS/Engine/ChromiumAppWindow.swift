#if BOAZ_CHROMIUM
import AppKit
import SwiftUI

@MainActor
final class ChromiumAppWindow: NSObject, NSWindowDelegate {
    /// One profile's Chromium browser in this window. The window shows the spaces of every profile, as in Arc: each
    /// profile whose space it has shown keeps its own browser here, with its cookies, extensions and pages, and the
    /// current space's is the one in front.
    @MainActor
    final class Host {
        let profile: ChromiumProfile
        let addressField = NSTextField()
        fileprivate var handle: BoazHostWindow = 0
        fileprivate var extensions: ChromiumExtensionActionsModel?
        /// Its extension's side panel, shown while it is in front.
        fileprivate var sidePanel: (view: NSView, title: String)?
        fileprivate weak var owner: ChromiumAppWindow?
        fileprivate init(profile: ChromiumProfile) { self.profile = profile }
    }
    let runtime: ChromiumRuntime
    let browser: BrowserState
    let window: NSWindow
    let contentContainer = NSView()
    private var hosts: [Host]
    /// The browser in front: the current space's profile's, or the private session's.
    private var front: Host
    var profile: ChromiumProfile { front.profile }
    var handle: BoazHostWindow { front.handle }
    /// Chromium's extension side panel at the trailing edge, beside the browser, as Chrome lays it out.
    private let sidePanel = ChromiumExtensionSidePanel()
    private weak var hosting: NSView?
    var onClosed: (() -> Void)?
    private let model: MacModel
    private let initialTabID: String?
    private let restoration: MacModel.NativeWindowRestoration?
    private var installed = false
    private(set) var finished = false
    private var closing = false
    private var layoutQueued = false
    private var appliedSplit: (leading: String, trailing: String)?

    init(runtime: ChromiumRuntime, profile: ChromiumProfile, model: MacModel,
         preparedForNativeCreation: Bool = false,
         restoration: MacModel.NativeWindowRestoration? = nil, initialTabID: String? = nil) throws {
        self.model = model
        self.initialTabID = initialTabID
        self.restoration = restoration
        self.runtime = runtime
        front = Host(profile: profile)
        hosts = [front]
        browser = BrowserState(incognito: profile.identity.isPrivate)
        if !profile.identity.isPrivate {
            let savedSpace = model.space(restoration?.saved?.spaceID)
            browser.currentSpaceID = savedSpace?.profileID == profile.identity.id
                ? savedSpace?.id : model.sidebar.spaces.first(where: { $0.profileID == profile.identity.id })?.id
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = profile.identity.isPrivate ? "Boaz — Private" : "Boaz"
        window.delegate = self
        window.contentView = contentContainer
        attach(front)
        browser.chromiumProfileIdentity = profile.identity
        browser.chromiumAddressField = front.addressField
        browser.chromiumSpaceChanged = { [weak self] in self?.showCurrentProfile() }
        browser.activateChromiumPage = { [weak self] page in
            guard let self, self.browser.peek?.nativePage == nil,
                  let adapter = page.adapter as? ChromiumEnginePageAdapter,
                  let activate = runtime.api.activate_page else { return }
            let result = activate(adapter.handle, 1)
            if result != BOAZ_HOST_OK { window.subtitle = "Could not activate page (\(result.rawValue))." }
        }
        browser.updateChromiumExternalTabCount = { [weak self] count in
            guard let self, !finished, let update = runtime.api.set_external_tab_count else { return false }
            // Another profile's live pages keep a profile's browser open, as the window's WebKit pages do.
            return hosts.filter { host in
                let others = UInt32(browser.chromiumPageCount(outside: host.profile.identity))
                return host.handle == 0 || update(host.handle, count + others) != BOAZ_HOST_OK
            }.isEmpty
        }
        browser.chromiumLayoutChanged = { [weak self] in self?.queueLayout() }
        browser.createChromiumPage = { [weak self] tab in
            guard let self, !self.finished, self.handle != 0 else { throw EnginePageError.closed }
            // A tab opens in its own profile's browser, which `BrowserState` opens before it shows the tab.
            guard let host = self.profile.identity.isPrivate ? self.front
                    : self.hosts.first(where: { $0.profile.identity.id == tab.profileID }), host.handle != 0 else {
                throw EnginePageError.invalidRequest
            }
            return try self.runtime.createPage(window: host.handle,
                url: tab.url ?? URL(string: "about:blank")!, profile: host.profile.identity,
                javaScriptDisabled: self.browser.devTools[tab.id].javaScriptDisabled)
        }
        browser.createChromiumPeekPage = { [weak self] url in
            guard let self, !finished, handle != 0 else { throw EnginePageError.closed }
            return try runtime.createPage(window: handle, url: url, profile: self.profile.identity)
        }
        browser.createChromiumSnapshotPage = { [weak self] tab, url in
            guard let self, !finished, handle != 0 else { throw EnginePageError.closed }
            guard !profile.identity.isPrivate,
                  let host = hosts.first(where: { $0.profile.identity.id == tab.profileID }), host.handle != 0 else {
                throw EnginePageError.invalidRequest
            }
            return try runtime.createPage(window: host.handle, url: url, profile: host.profile.identity,
                                          javaScriptDisabled: true)
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
        front.handle = handle
        installed = true
        browser.manageChromiumExtensions = { [weak self] in
            guard let self, !finished, !profile.identity.isPrivate else { return }
            if let open = browser.cycleTabs.first(where: { $0.url?.scheme == "chrome" && $0.url?.host() == "extensions" }) {
                browser.activate(open)
            } else if let url = URL(string: "chrome://extensions") {
                browser.openTab(url, engine: .chromium)
            }
        }
        browser.reviewPreviousChromiumExtensions = { [weak self] in
            guard let self, !finished, !profile.identity.isPrivate else { return }
            ChromiumExtensionMigration.present(window: window, profileID: profile.identity.id,
                profiles: model.sidebar.profiles, openStore: { [weak self] url in
                    guard let self, !finished else { return }
                    browser.openTab(url, engine: .chromium)
                }, openExtensions: { [weak self] in
                    guard let self, !finished else { return }
                    browser.manageChromiumExtensions?()
                })
        }
        browser.restoreChromiumDockPreferences = { [weak self] current, last in
            guard let self, !finished else { return }
            do {
                for host in hosts {
                    try runtime.restoreDevToolsDockPreferences(window: host.handle, current: current, last: last)
                }
            } catch { model.showToast(error.localizedDescription) }
        }
        front.extensions = makeExtensions(for: front)
        browser.chromiumExtensions = front.extensions
        let hosting = NSHostingView(rootView: BrowserWindow(browser: browser, nativeRestoration: restoration, initialTabID: initialTabID)
            .environment(model).task { await self.model.start() })
        hosting.frame = contentContainer.bounds
        hosting.autoresizingMask = [.width, .height]
        contentContainer.addSubview(hosting)
        self.hosting = hosting
        sidePanel.isHidden = true
        sidePanel.autoresizingMask = [.minXMargin, .height]
        sidePanel.close = { [weak self] in
            guard let self, !finished, handle != 0, let close = runtime.api.close_extension_side_panel else { return }
            _ = close(handle)
        }
        sidePanel.resized = { [weak self] in self?.layoutSidePanel() }
        contentContainer.addSubview(sidePanel)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func attach(_ host: Host) {
        host.owner = self
        host.addressField.isHidden = true
        host.addressField.setAccessibilityLabel("Address")
        contentContainer.addSubview(host.addressField)
    }

    private func makeExtensions(for host: Host) -> ChromiumExtensionActionsModel {
        ChromiumExtensionActionsModel(api: runtime.api, window: host.handle, activePage: { [weak browser = browser] in
            browser?.activeEnginePage?.adapter as? ChromiumEnginePageAdapter
        })
    }

    func hasBrowser(for profileID: String) -> Bool { hosts.contains { $0.profile.identity.id == profileID } }
    func uses(_ profile: ChromiumProfile) -> Bool { hosts.contains { $0.profile == profile } }
    func owns(_ handle: BoazHostWindow) -> Bool { hosts.contains { $0.handle == handle } }

    /// Opens `profile`'s browser in this window, behind the one in front, before the first of its spaces shows here.
    func open(_ profile: ChromiumProfile) throws {
        guard !finished, installed, !self.profile.identity.isPrivate, !profile.identity.isPrivate,
              !hasBrowser(for: profile.identity.id) else { throw EnginePageError.invalidRequest }
        let host = Host(profile: profile)
        attach(host)
        hosts.append(host)
        var options = makeOptions(host)
        do { host.handle = try runtime.createWindow(profile: profile, options: &options) }
        catch {
            hosts.removeAll { $0 === host }
            host.addressField.removeFromSuperview()
            throw error
        }
        host.extensions = makeExtensions(for: host)
        try? runtime.restoreDevToolsDockPreferences(window: host.handle, current: browser.devToolsDockSide,
                                                    last: browser.devToolsLastDockSide)
        browser.reportExternalTabs()
        showCurrentProfile()
    }

    /// Puts the current space's profile in front: its browser, toolbar extensions, side panel and address field.
    private func showCurrentProfile() {
        guard !finished, let id = browser.currentSpace?.profileID,
              let host = hosts.first(where: { $0.profile.identity.id == id }), host !== front else { return }
        bringForward(host)
    }

    private func bringForward(_ host: Host) {
        front = host
        _ = runtime.api.bring_window_forward?(host.handle)
        browser.chromiumProfileIdentity = host.profile.identity
        browser.chromiumAddressField = host.addressField
        browser.chromiumExtensions = host.extensions
        sidePanel.show(host.sidePanel?.view, title: host.sidePanel?.title ?? "")
        layoutSidePanel()
    }

    /// A profile's browser closed. A browser behind (an extension closed it, say) just leaves; the one in front
    /// takes the window with it: the other profiles' browsers close one at a time, each in front as it does so a
    /// page that asks before closing is seen. Returns the closed browser's profile.
    func browserClosed(_ handle: BoazHostWindow) -> ChromiumProfile? {
        guard let index = hosts.firstIndex(where: { $0.handle == handle }) else { return nil }
        let host = hosts.remove(at: index)
        host.addressField.removeFromSuperview()
        guard let next = hosts.first else { finishClose(); return host.profile }
        guard host === front else { browser.reportExternalTabs(); return host.profile }
        bringForward(next)
        _ = runtime.api.close_window?(front.handle)
        return host.profile
    }

    func makeOptions() -> BoazHostWindowOptions { makeOptions(front) }

    private func makeOptions(_ host: Host) -> BoazHostWindowOptions {
        var options = BoazHostWindowOptions()
        options.size = MemoryLayout<BoazHostWindowOptions>.size
        options.native_nswindow = Unmanaged.passUnretained(window).toOpaque()
        options.context = Unmanaged.passUnretained(host).toOpaque()
        options.content_view = { context in
            let bits: UInt? = MainActor.assumeIsolated {
                guard let context, let owner = Unmanaged<Host>.fromOpaque(context).takeUnretainedValue().owner else { return nil }
                return UInt(bitPattern: Unmanaged.passUnretained(owner.contentContainer).toOpaque())
            }
            return bits.flatMap { UnsafeMutableRawPointer(bitPattern: $0) }
        }
        options.address_field = { context in
            let bits: UInt? = MainActor.assumeIsolated {
                guard let context else { return nil }
                let host = Unmanaged<Host>.fromOpaque(context).takeUnretainedValue()
                return UInt(bitPattern: Unmanaged.passUnretained(host.addressField).toOpaque())
            }
            return bits.flatMap { UnsafeMutableRawPointer(bitPattern: $0) }
        }
        options.focus_address = { context in
            MainActor.assumeIsolated {
                guard let context else { return }
                let host = Unmanaged<Host>.fromOpaque(context).takeUnretainedValue()
                guard let owner = host.owner, owner.front === host else { return }
                owner.queue { $0.browser.commandMode = .currentTab }
            }
        }
        options.focus_toolbar = options.focus_address
        options.handle_key = { context, event in
            MainActor.assumeIsolated {
                guard let context, let event,
                      let owner = Unmanaged<Host>.fromOpaque(context).takeUnretainedValue().owner else { return 0 }
                let key = Unmanaged<NSEvent>.fromOpaque(event).takeUnretainedValue()
                return owner.handleKey(key) ? 1 : 0
            }
        }
        options.exclusive_access_notice = { context, text, visible in
            MainActor.assumeIsolated {
                guard let context, let owner = Unmanaged<Host>.fromOpaque(context).takeUnretainedValue().owner else { return }
                let copied = visible != 0 ? text.map { String(cString: $0) } ?? "" : ""
                owner.queue { $0.window.subtitle = copied }
            }
        }
        options.extension_anchor = { context, id, view, bounds in
            MainActor.assumeIsolated {
                guard let context, let view, let bounds else { return 0 }
                let host = Unmanaged<Host>.fromOpaque(context).takeUnretainedValue()
                guard host.owner?.finished == false, let anchor = host.extensions?.anchor(for: id.map { String(cString: $0) })
                else { return 0 }
                view.pointee = Unmanaged.passUnretained(anchor).toOpaque()
                let rect = anchor.bounds
                bounds[0] = rect.minX; bounds[1] = rect.minY; bounds[2] = rect.width; bounds[3] = rect.height
                return 1
            }
        }
        options.extension_side_panel = { context, view, title in
            MainActor.assumeIsolated {
                guard let context else { return }
                let host = Unmanaged<Host>.fromOpaque(context).takeUnretainedValue()
                guard let owner = host.owner, !owner.finished else { return }
                owner.showSidePanel(view.map { Unmanaged<NSView>.fromOpaque($0).takeUnretainedValue() },
                                    title: title.map { String(cString: $0) } ?? "", of: host)
            }
        }
        options.menu_features = BOAZ_MENU_FEATURE_SPLIT.rawValue | BOAZ_MENU_FEATURE_INCOGNITO.rawValue
            | (browser.isIncognito ? 0 : BOAZ_MENU_FEATURE_SEND_TO_DEVICES.rawValue)
        return options
    }

    private func showSidePanel(_ view: NSView?, title: String, of host: Host) {
        host.sidePanel = view.map { ($0, title) }
        guard host === front else { return }
        sidePanel.show(view, title: title)
        layoutSidePanel()
        if let view { window.makeFirstResponder(view) }
    }

    /// The browser keeps the leading part of the window; the panel takes its width, within Chrome's limits.
    private func layoutSidePanel() {
        let bounds = contentContainer.bounds
        let width = sidePanel.isHidden ? 0 : min(max(sidePanel.preferredWidth, ChromiumExtensionSidePanel.minimumWidth),
                                                 max(bounds.width * 2 / 3, ChromiumExtensionSidePanel.minimumWidth))
        if width > 0 { sidePanel.preferredWidth = width }
        hosting?.frame = NSRect(x: 0, y: 0, width: bounds.width - width, height: bounds.height)
        sidePanel.frame = NSRect(x: bounds.width - width, y: 0, width: width, height: bounds.height)
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
        showCurrentProfile()
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
                else { window.subtitle = "Could not update the split view." }
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
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "r" {
            queue { $0.browser.hardReload() }
            return true
        }
        guard modifiers == .command else { return false }
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
        alert.messageText = "Close this window?"
        alert.informativeText = "Some pages in this window may have unsaved changes."
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
        if let restoration { model.finishNativeRestoration(restoration, succeeded: false) }
        browser.chromiumExtensions = nil
        sidePanel.show(nil, title: "")
        browser.createChromiumPeekPage = nil
        browser.createChromiumSnapshotPage = nil
        browser.createChromiumPage = nil
        browser.openChromiumProfile = nil
        browser.chromiumSpaceChanged = nil
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

/// Chromium's extension side panel: the extension's page under its name and a close button. Drag its leading edge
/// to resize it.
@MainActor
final class ChromiumExtensionSidePanel: NSView {
    static let minimumWidth: CGFloat = 320
    static let headerHeight: CGFloat = 32
    var preferredWidth: CGFloat = 360
    var close: (() -> Void)?
    var resized: (() -> Void)?
    private let titleLabel = NSTextField(labelWithString: "")
    private let closeButton = NSButton()
    private weak var content: NSView?
    private var dragStart: (x: CGFloat, width: CGFloat)?

    init() {
        super.init(frame: .zero)
        identifier = NSUserInterfaceItemIdentifier("screen.extensionSidePanel")
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close Side Panel")
        closeButton.isBordered = false
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.toolTip = "Close Side Panel"
        closeButton.setAccessibilityIdentifier("control.extensionSidePanel.close")
        addSubview(titleLabel)
        addSubview(closeButton)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        // Below the title bar's buttons, which the full-size content view extends under.
        let top = window.map { $0.frame.height - $0.contentLayoutRect.height } ?? 0
        titleLabel.frame = NSRect(x: 12, y: top + 8, width: max(0, bounds.width - 52), height: 16)
        closeButton.frame = NSRect(x: bounds.width - 32, y: top + 4, width: 24, height: 24)
        content?.frame = NSRect(x: 1, y: top + Self.headerHeight, width: max(0, bounds.width - 1),
                                height: max(0, bounds.height - top - Self.headerHeight))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
    }

    /// Shows the extension's page, or hides the panel when `view` is nil.
    func show(_ view: NSView?, title: String) {
        if content !== view {
            content?.removeFromSuperview()
            if let view { addSubview(view) }
            content = view
        }
        titleLabel.stringValue = title
        setAccessibilityLabel(title)
        isHidden = view == nil
        needsLayout = true
    }

    // The leading 4 points resize the panel, over the page's own leading edge too.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let superview, frame.contains(point) else { return super.hitTest(point) }
        return convert(point, from: superview).x <= 4 ? self : super.hitTest(point)
    }
    // The edge works on the first click, as the page beside it does.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() {
        addCursorRect(NSRect(x: 0, y: 0, width: 4, height: bounds.height), cursor: .resizeLeftRight)
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point.x <= 4 ? (event.locationInWindow.x, bounds.width) : nil
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        preferredWidth = max(Self.minimumWidth, start.width - (event.locationInWindow.x - start.x))
        resized?()
    }
    override func mouseUp(with event: NSEvent) { dragStart = nil }

    @objc private func closeClicked() { close?() }
}
#endif
