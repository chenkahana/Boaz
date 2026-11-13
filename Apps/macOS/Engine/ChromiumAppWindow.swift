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
    private var finished = false
    private var closing = false

    init(runtime: ChromiumRuntime, profile: ChromiumProfile, model: MacModel) throws {
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
        browser.chromiumAddressField = addressField
        browser.activateChromiumPage = { [weak self] page in
            guard let self, let adapter = page.adapter as? ChromiumEnginePageAdapter,
                  let activate = runtime.api.activate_page else { return }
            let result = activate(adapter.handle, 1)
            if result != BOAZ_HOST_OK { window.subtitle = "Could not activate page (\(result.rawValue))." }
        }
        addressField.setAccessibilityLabel("Address")
        browser.createChromiumPage = { [weak self] tab in
            guard let self, !self.finished, self.handle != 0 else { throw EnginePageError.closed }
            guard self.profile.identity.isPrivate || (tab.profileID ?? "default") == self.profile.identity.id else {
                throw EnginePageError.invalidRequest
            }
            return try self.runtime.createPage(window: self.handle,
                url: tab.url ?? URL(string: "about:blank")!, profile: self.profile.identity)
        }
        var options = makeOptions()
        do {
            handle = try runtime.createWindow(profile: profile, options: &options)
        } catch {
            window.delegate = nil
            window.close()
            throw error
        }
        let hosting = NSHostingView(rootView: BrowserWindow(browser: browser)
            .environment(model).task { await model.start() })
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
            MainActor.assumeIsolated {
                guard let context else { return nil }
                let owner = Unmanaged<ChromiumAppWindow>.fromOpaque(context).takeUnretainedValue()
                return Unmanaged.passUnretained(owner.contentContainer).toOpaque()
            }
        }
        options.address_field = { context in
            MainActor.assumeIsolated {
                guard let context else { return nil }
                let owner = Unmanaged<ChromiumAppWindow>.fromOpaque(context).takeUnretainedValue()
                return Unmanaged.passUnretained(owner.addressField).toOpaque()
            }
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !finished else { return true }
        if !closing {
            closing = true
            queue { owner in
                let result = owner.runtime.api.close_window!(owner.handle)
                owner.closing = false
                if result != BOAZ_HOST_OK { owner.window.subtitle = "Could not close window (\(result.rawValue))." }
            }
        }
        return false
    }

    func finishClose() {
        guard !finished else { return }
        finished = true
        browser.createChromiumPage = nil
        browser.activateChromiumPage = nil
        browser.chromiumAddressField = nil
        window.delegate = nil
        window.orderOut(nil)
        window.close()
        onClosed?()
    }
}
#endif
