#if BOAZ_CHROMIUM
import AppKit
import SwiftUI

@MainActor
final class ChromiumDevToolsWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    let profile: ChromiumProfile
    private let runtime: ChromiumRuntime
    private let contentContainer = NSView()
    private let addressField = NSTextField()
    private(set) var handle: BoazHostWindow = 0
    private var page: EnginePage?
    private var finished = false
    private var closeQueued = false
    private var keyMonitor: Any?

    init(runtime: ChromiumRuntime, profile: ChromiumProfile) {
        self.runtime = runtime
        self.profile = profile
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = "Boaz Developer Tools"
        window.delegate = self
        window.contentView = contentContainer
        addressField.isHidden = true
        contentContainer.addSubview(addressField)
    }

    func adoptNativeWindow(_ handle: BoazHostWindow) throws {
        guard !finished, self.handle == 0, handle != 0 else { throw EnginePageError.invalidRequest }
        self.handle = handle
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, event.window === self.window else { return false }
                return self.handleKey(event)
            }
            return consumed ? nil : event
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func adoptPage(_ page: EnginePage) throws {
        guard !finished, handle != 0, self.page == nil,
              let adapter = page.adapter as? ChromiumEnginePageAdapter,
              adapter.profile == profile.identity else { throw EnginePageError.invalidRequest }
        self.page = page
        let hosting = NSHostingView(rootView: ChromiumPageView(adapter: adapter))
        hosting.frame = contentContainer.bounds
        hosting.autoresizingMask = [.width, .height]
        contentContainer.addSubview(hosting)
        hosting.layoutSubtreeIfNeeded()
        queue { $0.focusAddress() }
    }

    func makeOptions() -> BoazHostWindowOptions {
        var options = BoazHostWindowOptions()
        options.size = MemoryLayout<BoazHostWindowOptions>.size
        options.native_nswindow = Unmanaged.passUnretained(window).toOpaque()
        options.context = Unmanaged.passUnretained(self).toOpaque()
        options.content_view = { context in
            let bits: UInt? = MainActor.assumeIsolated {
                guard let context else { return nil }
                let owner = Unmanaged<ChromiumDevToolsWindow>.fromOpaque(context).takeUnretainedValue()
                return UInt(bitPattern: Unmanaged.passUnretained(owner.contentContainer).toOpaque())
            }
            return bits.flatMap { UnsafeMutableRawPointer(bitPattern: $0) }
        }
        options.address_field = { context in
            let bits: UInt? = MainActor.assumeIsolated {
                guard let context else { return nil }
                let owner = Unmanaged<ChromiumDevToolsWindow>.fromOpaque(context).takeUnretainedValue()
                return UInt(bitPattern: Unmanaged.passUnretained(owner.addressField).toOpaque())
            }
            return bits.flatMap { UnsafeMutableRawPointer(bitPattern: $0) }
        }
        options.focus_address = { context in
            MainActor.assumeIsolated {
                guard let context else { return }
                let owner = Unmanaged<ChromiumDevToolsWindow>.fromOpaque(context).takeUnretainedValue()
                owner.queue { $0.focusAddress() }
            }
        }
        options.focus_toolbar = options.focus_address
        options.handle_key = { context, event in
            MainActor.assumeIsolated {
                guard let context, let event else { return 0 }
                let owner = Unmanaged<ChromiumDevToolsWindow>.fromOpaque(context).takeUnretainedValue()
                let key = Unmanaged<NSEvent>.fromOpaque(event).takeUnretainedValue()
                return owner.handleKey(key) ? 1 : 0
            }
        }
        options.exclusive_access_notice = { context, text, visible in
            MainActor.assumeIsolated {
                guard let context else { return }
                let owner = Unmanaged<ChromiumDevToolsWindow>.fromOpaque(context).takeUnretainedValue()
                let copied = visible != 0 ? text.map { String(cString: $0) } ?? "" : ""
                owner.queue { $0.window.subtitle = copied }
            }
        }
        return options
    }

    private func queue(_ action: @escaping (ChromiumDevToolsWindow) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.finished else { return }
            action(self)
        }
    }
    private func focusAddress() {
        if let adapter = page?.adapter as? ChromiumEnginePageAdapter,
           let view = try? adapter.nativeView() { window.makeFirstResponder(view) }
    }
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "w": queue { $0.window.performClose(nil) }
        default: return false
        }
        return true
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if finished { return true }
        guard !closeQueued else { return false }
        closeQueued = true
        queue { owner in
            let result = owner.runtime.api.close_window!(owner.handle)
            owner.closeQueued = false
            if result != BOAZ_HOST_OK { owner.window.subtitle = "The window could not close (\(result.rawValue))." }
        }
        return false
    }
    func finishClose() {
        guard !finished else { return }
        finished = true
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        (page?.adapter as? ChromiumEnginePageAdapter)?.detachNativeView()
        page = nil
        window.delegate = nil
        window.orderOut(nil)
        window.close()
    }

}
#endif
