import AppKit
import SwiftUI

@MainActor private var session: HostSession?

private struct PageUpdate {
    let page: UInt64
    let window: UInt64
    let title: String
    let url: String
    let active: Bool
    let back: Bool
    let forward: Bool
    let loading: Bool

    init(_ state: BoazHostPageState) {
        page = state.page
        window = state.window
        title = state.title.map { String(cString: $0) } ?? ""
        url = state.url.map { String(cString: $0) } ?? ""
        active = state.active != 0
        back = state.can_go_back != 0
        forward = state.can_go_forward != 0
        loading = state.loading != 0
    }
}

@MainActor private final class ExtensionSnapshot {
    var actions: [(id: String, name: String)] = []
}

@MainActor private final class Page: Identifiable {
    let id: UInt64
    var title = "New tab"
    var url = ""
    var back = false
    var forward = false
    var loading = false
    weak var view: NSView?
    init(_ id: UInt64) { self.id = id }
}

@MainActor private final class HostSession {
    let api: BoazHostAPI
    var windows: [HostWindow] = []
    var stopped = false

    init(_ api: BoazHostAPI) { self.api = api }

    func start() -> BoazHostResult {
        var callbacks = BoazHostCallbacks()
        callbacks.size = MemoryLayout<BoazHostCallbacks>.size
        callbacks.context = Unmanaged.passUnretained(self).toOpaque()
        callbacks.page_event = { context, event, state in
            guard let context, let state, state.pointee.size >= MemoryLayout<BoazHostPageState>.size else { return }
            MainActor.assumeIsolated {
                let owner = Unmanaged<HostSession>.fromOpaque(context).takeUnretainedValue()
                let value = state.pointee
                if event == BOAZ_HOST_PAGE_CLOSING || event == BOAZ_HOST_PAGE_VIEW_WILL_CHANGE {
                    owner.windows.first { $0.handle == value.window }?.detach(value.page)
                    return
                }
                let copied = PageUpdate(value)
                DispatchQueue.main.async { [weak owner] in
                    guard let owner, !owner.stopped else { return }
                    owner.windows.first { $0.handle == copied.window }?.update(event, copied)
                }
            }
        }
        callbacks.prepare_window = { context, options in
            guard Thread.isMainThread, let context, let options else { return BOAZ_HOST_INVALID_ARGUMENT }
            return MainActor.assumeIsolated {
                guard let owner = session, !owner.stopped,
                      Unmanaged.passUnretained(owner).toOpaque() == context else { return BOAZ_HOST_INVALID_ARGUMENT }
                let window = HostWindow(owner)
                owner.windows.append(window)
                options.pointee = window.makeOptions()
                return BOAZ_HOST_OK
            }
        }
        callbacks.window_created = { context, handle, windowContext in
            guard let context, let windowContext else { return }
            MainActor.assumeIsolated {
                guard let owner = session, !owner.stopped,
                      Unmanaged.passUnretained(owner).toOpaque() == context else { return }
                let contextBits = UInt(bitPattern: windowContext)
                DispatchQueue.main.async { [weak owner] in
                    guard let owner, !owner.stopped,
                          let window = owner.windows.first(where: {
                              UInt(bitPattern: Unmanaged.passUnretained($0).toOpaque()) == contextBits
                          }) else { return }
                    _ = owner.bind(window, to: handle)
                }
            }
        }
        callbacks.window_closed = { context, handle in
            guard let context else { return }
            MainActor.assumeIsolated {
                let owner = Unmanaged<HostSession>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { [weak owner] in owner?.didClose(handle) }
            }
        }
        callbacks.shutdown_ready = { context in
            guard let context else { return }
            MainActor.assumeIsolated {
                let owner = Unmanaged<HostSession>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async {
                    owner.stopped = true
                    for window in owner.windows { window.finishClose() }
                    owner.windows.removeAll()
                    session = nil
                }
            }
        }
        let result = api.set_callbacks!(&callbacks)
        guard result == BOAZ_HOST_OK else { return result }
        let window = HostWindow(self)
        windows.append(window)
        let created = window.create()
        if created != BOAZ_HOST_OK && !window.engineAccepted {
            window.finishClose()
            windows.removeAll { $0 === window }
        }
        return created
    }

    func bind(_ window: HostWindow, to handle: UInt64) -> Bool {
        guard handle != 0, windows.contains(where: { $0 === window }),
              window.handle == 0 || window.handle == handle,
              !windows.contains(where: { $0 !== window && $0.handle == handle }) else {
            window.message = "Invalid browser window binding."
            return false
        }
        if window.handle == handle { return true }
        window.engineAccepted = true
        window.handle = handle
        window.window.makeKeyAndOrderFront(nil)
        return true
    }

    func didClose(_ handle: UInt64) {
        guard let window = windows.first(where: { $0.handle == handle }) else { return }
        window.finishClose()
        windows.removeAll { $0 === window }
    }

    func queue(_ operation: @escaping (BoazHostAPI) -> BoazHostResult) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stopped else { return }
            let result = operation(self.api)
            if result != BOAZ_HOST_OK {
                self.windows.forEach { $0.message = "Browser request failed (\(result.rawValue))." }
            }
        }
    }
}

@MainActor private final class HostWindow: NSObject, ObservableObject, NSWindowDelegate, NSTextFieldDelegate {
    unowned let owner: HostSession
    let window: NSWindow
    let viewport = NSView()
    let address = NSTextField()
    let addButton = NSButton(title: "+", target: nil, action: nil)
    let extensionsButton = NSButton(title: "Extensions", target: nil, action: nil)
    private var selectedExtension: String?
    var handle: UInt64 = 0
    var engineAccepted = false
    var allowClose = false
    var keyMonitor: Any?
    @Published var pages: [Page] = []
    @Published var active: UInt64 = 0
    @Published var notice = ""
    @Published var message = ""

    init(_ owner: HostSession) {
        self.owner = owner
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.title = "Boaz Chromium prototype"
        viewport.setAccessibilityLabel("Web page")
        address.placeholderString = "Address"
        address.setAccessibilityLabel("Address")
        address.delegate = self
        address.target = self
        address.action = #selector(submitAddress)
        addButton.target = self
        addButton.action = #selector(addTab)
        addButton.setAccessibilityLabel("New tab")
        extensionsButton.target = self
        extensionsButton.action = #selector(showExtensions)
        extensionsButton.setAccessibilityLabel("Extensions")
        extensionsButton.toolTip = "Show installed extension actions"
        window.contentView = NSHostingView(rootView: WindowContent(model: self))
        window.center()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, event.window === self.window else { return false }
                return self.handleKey(event)
            }
            return consumed ? nil : event
        }
    }

    func makeOptions() -> BoazHostWindowOptions {
        window.contentView?.layoutSubtreeIfNeeded()
        var options = BoazHostWindowOptions()
        options.size = MemoryLayout<BoazHostWindowOptions>.size
        options.native_nswindow = Unmanaged.passUnretained(window).toOpaque()
        options.context = Unmanaged.passUnretained(self).toOpaque()
        options.content_view = { context in
            let bits: UInt = MainActor.assumeIsolated {
                guard let context else { return 0 }
                let model = Unmanaged<HostWindow>.fromOpaque(context).takeUnretainedValue()
                return UInt(bitPattern: Unmanaged.passUnretained(model.viewport).toOpaque())
            }
            return UnsafeMutableRawPointer(bitPattern: bits)
        }
        options.address_field = { context in
            let bits: UInt = MainActor.assumeIsolated {
                guard let context else { return 0 }
                let model = Unmanaged<HostWindow>.fromOpaque(context).takeUnretainedValue()
                return UInt(bitPattern: Unmanaged.passUnretained(model.address).toOpaque())
            }
            return UnsafeMutableRawPointer(bitPattern: bits)
        }
        options.focus_address = { context in
            MainActor.assumeIsolated {
                guard let context else { return }
                Unmanaged<HostWindow>.fromOpaque(context).takeUnretainedValue().focusAddress()
            }
        }
        options.focus_toolbar = { context in
            MainActor.assumeIsolated {
                guard let context else { return }
                let model = Unmanaged<HostWindow>.fromOpaque(context).takeUnretainedValue()
                model.window.makeFirstResponder(model.addButton)
            }
        }
        options.handle_key = { context, event in
            MainActor.assumeIsolated {
                guard let context, let event else { return 0 }
                let model = Unmanaged<HostWindow>.fromOpaque(context).takeUnretainedValue()
                let key = Unmanaged<NSEvent>.fromOpaque(event).takeUnretainedValue()
                return model.handleKey(key) ? 1 : 0
            }
        }
        options.exclusive_access_notice = { context, text, visible in
            MainActor.assumeIsolated {
                guard let context else { return }
                let model = Unmanaged<HostWindow>.fromOpaque(context).takeUnretainedValue()
                model.notice = visible != 0 ? text.map { String(cString: $0) } ?? "" : ""
                model.window.contentView?.layoutSubtreeIfNeeded()
            }
        }
        return options
    }

    func create() -> BoazHostResult {
        var options = makeOptions()
        var createdHandle: UInt64 = 0
        let result = owner.api.create_window!(&options, &createdHandle)
        guard result == BOAZ_HOST_OK else { return result }
        engineAccepted = true
        guard owner.bind(self, to: createdHandle) else { return BOAZ_HOST_INVALID_HANDLE }
        newPage("https://example.com")
        newPage("https://example.org")
        return result
    }

    func newPage(_ url: String) {
        let id = handle
        owner.queue { api in
            var page: UInt64 = 0
            return url.withCString { api.create_page!(id, $0, &page) }
        }
    }
    @objc private func showExtensions() {
        guard !owner.stopped, handle != 0, !allowClose else { return }
        let expectedWindow = handle
        let expectedPage = active
        let snapshot = ExtensionSnapshot()
        let result = owner.api.enumerate_extensions!(expectedWindow, { context, id, name in
            guard let context, let id, let name else { return }
            MainActor.assumeIsolated {
                let copied = Unmanaged<ExtensionSnapshot>.fromOpaque(context).takeUnretainedValue()
                copied.actions.append((String(cString: id), String(cString: name)))
            }
        }, Unmanaged.passUnretained(snapshot).toOpaque())
        guard result == BOAZ_HOST_OK else {
            message = "Could not load extensions (\(result.rawValue))."
            return
        }
        let menu = NSMenu(title: "Extensions")
        menu.autoenablesItems = false
        for action in snapshot.actions.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) {
            let item = NSMenuItem(title: action.name, action: #selector(selectExtension(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = action.id
            item.isEnabled = expectedPage != 0
            menu.addItem(item)
        }
        if snapshot.actions.isEmpty {
            let item = NSMenuItem(title: "No extensions installed", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        selectedExtension = nil
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: extensionsButton.bounds.maxY), in: extensionsButton)
        guard let selected = selectedExtension else { return }
        selectedExtension = nil
        // NSMenu tracking has returned; never reenter the engine from menu dispatch.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.owner.stopped, !self.allowClose,
                  self.handle == expectedWindow, self.active == expectedPage,
                  self.extensionsButton.window === self.window else { return }
            let bounds = self.extensionsButton.bounds
            guard let x = Int32(exactly: bounds.minX.rounded(.down)),
                  let y = Int32(exactly: bounds.minY.rounded(.down)),
                  let width = Int32(exactly: bounds.width.rounded(.up)),
                  let height = Int32(exactly: bounds.height.rounded(.up)),
                  width > 0, height > 0 else {
                self.message = "The extension button is not ready."
                return
            }
            let anchor = Unmanaged.passUnretained(self.extensionsButton).toOpaque()
            let invoked = selected.withCString {
                self.owner.api.invoke_extension!(expectedWindow, expectedPage, $0, anchor, x, y, width, height)
            }
            self.message = invoked == BOAZ_HOST_OK ? "" : "Could not open extension (\(invoked.rawValue))."
        }
    }
    @objc private func selectExtension(_ sender: NSMenuItem) {
        selectedExtension = sender.representedObject as? String
    }
    @objc func addTab() { newPage("https://example.com") }
    @objc func submitAddress() {
        let id = active
        let value = address.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id != 0, !value.isEmpty else { return }
        let url = value.contains("://") ? value : "https://" + value
        owner.queue { api in url.withCString { api.navigate!(id, $0) } }
    }
    func focusAddress() { window.makeFirstResponder(address); address.selectText(nil) }
    func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, event.modifierFlags.contains(.command) else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "l": focusAddress()
        case "t": addTab()
        case "w": closePage(active)
        case "r": reload()
        case "q": owner.queue { $0.request_shutdown!() }
        default: return false
        }
        return true
    }
    func activate(_ id: UInt64) { owner.queue { $0.activate_page!(id, 1) } }
    func closePage(_ id: UInt64) { guard id != 0 else { return }; owner.queue { $0.close_page!(id) } }
    func back() { let id = active; owner.queue { $0.go_back!(id) } }
    func forward() { let id = active; owner.queue { $0.go_forward!(id) } }
    func reload() { let id = active; owner.queue { $0.reload!(id) } }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowClose { return true }
        let id = handle
        owner.queue { $0.close_window!(id) }
        return false
    }
    func finishClose() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        pages.forEach { $0.view?.removeFromSuperview(); $0.view = nil }
        allowClose = true
        window.close()
    }
    func detach(_ id: UInt64) {
        guard let page = pages.first(where: { $0.id == id }) else { return }
        page.view?.removeFromSuperview()
        page.view = nil
    }
    func update(_ event: BoazHostPageEvent, _ state: PageUpdate) {
        if event == BOAZ_HOST_PAGE_CLOSED {
            detach(state.page)
            pages.removeAll { $0.id == state.page }
            if active == state.page { active = 0 }
            return
        }
        let page = pages.first(where: { $0.id == state.page }) ?? Page(state.page)
        if !pages.contains(where: { $0.id == page.id }) { pages.append(page) }
        page.title = state.title.isEmpty ? "Untitled" : state.title
        page.url = state.url
        page.back = state.back
        page.forward = state.forward
        page.loading = state.loading
        if event == BOAZ_HOST_PAGE_RENDERER_FAILED { message = "This page's renderer stopped. Reload to retry." }
        if event == BOAZ_HOST_PAGE_CLOSE_CANCELLED { message = "Page close was cancelled." }
        if event == BOAZ_HOST_PAGE_CREATED || event == BOAZ_HOST_PAGE_VIEW_CHANGED || event == BOAZ_HOST_PAGE_CLOSE_CANCELLED || page.view == nil {
            var pointer: UnsafeMutableRawPointer?
            if owner.api.get_native_view!(page.id, &pointer) == BOAZ_HOST_OK, let pointer {
                page.view = Unmanaged<NSView>.fromOpaque(pointer).takeUnretainedValue()
            }
        }
        if state.active {
            active = page.id
            for other in pages where other.id != page.id { other.view?.removeFromSuperview() }
            if let view = page.view {
                if view.superview !== viewport { view.removeFromSuperview(); viewport.addSubview(view) }
                view.frame = viewport.bounds
                view.autoresizingMask = [.width, .height]
            }
        }
        objectWillChange.send()
    }
}

private struct ExistingView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct WindowContent: View {
    @ObservedObject var model: HostWindow
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back", action: model.back).disabled(!(model.pages.first { $0.id == model.active }?.back ?? false))
                Button("Forward", action: model.forward).disabled(!(model.pages.first { $0.id == model.active }?.forward ?? false))
                Button("Reload", action: model.reload).disabled(model.active == 0)
                ExistingView(view: model.address).frame(minWidth: 220, minHeight: 26)
                ExistingView(view: model.addButton).frame(width: 32, height: 28)
                ExistingView(view: model.extensionsButton).frame(width: 100, height: 28)
                Button("Quit") { model.owner.queue { $0.request_shutdown!() } }
            }.padding(8)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(model.pages) { page in
                        HStack {
                            Button(page.title) { model.activate(page.id) }
                                .fontWeight(model.active == page.id ? .bold : .regular)
                                .accessibilityValue(model.active == page.id ? "Selected tab" : "Tab")
                            Button("Close") { model.closePage(page.id) }.accessibilityLabel("Close \(page.title)")
                        }.padding(6)
                    }
                }
            }.frame(height: 40)
            if !model.notice.isEmpty {
                Text(model.notice).font(.headline).padding(10).frame(maxWidth: .infinity)
                    .background(Color.yellow.opacity(0.25)).accessibilityLabel(model.notice)
            }
            if !model.message.isEmpty { Text(model.message).padding(6).frame(maxWidth: .infinity) }
            ExistingView(view: model.viewport).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(minWidth: 640, minHeight: 400)
    }
}

@_cdecl("BoazNativeUIStart")
public func boazNativeUIStart(_ pointer: UnsafePointer<BoazHostAPI>?) -> BoazHostResult {
    guard Thread.isMainThread else { return BOAZ_HOST_WRONG_THREAD }
    guard let pointer else { return BOAZ_HOST_INVALID_ARGUMENT }
    let api = pointer.pointee
    guard api.size >= MemoryLayout<BoazHostAPI>.size,
          api.version == BOAZ_HOST_ABI_VERSION, api.version == 4 else { return BOAZ_HOST_INVALID_ARGUMENT }
    return MainActor.assumeIsolated {
        guard session == nil else { return BOAZ_HOST_UNAVAILABLE }
        guard api.set_callbacks != nil, api.create_window != nil, api.create_page != nil,
              api.navigate != nil, api.go_back != nil, api.go_forward != nil, api.reload != nil,
              api.activate_page != nil, api.get_native_view != nil, api.close_page != nil,
              api.close_window != nil, api.request_shutdown != nil,
              api.enumerate_extensions != nil, api.invoke_extension != nil else { return BOAZ_HOST_INVALID_ARGUMENT }
        let value = HostSession(api)
        session = value
        return value.start()
    }
}
