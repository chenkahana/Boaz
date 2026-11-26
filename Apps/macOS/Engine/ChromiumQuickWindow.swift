#if BOAZ_CHROMIUM
import AppKit
import BoazKit
import SwiftUI

@MainActor
final class ChromiumQuickWindow: NSObject, ObservableObject, NSWindowDelegate {
    let window: NSWindow
    let profile: ChromiumProfile
    private let runtime: ChromiumRuntime
    private let model: MacModel
    private let contentContainer = NSView()
    private let addressField = NSTextField()
    private(set) var handle: BoazHostWindow = 0
    @Published private var page: EnginePage?
    var chromiumPageHandle: BoazHostPage? {
        (page?.adapter as? ChromiumEnginePageAdapter)?.handle
    }
    @Published private var address = ""
    @Published private var failure = ""
    @Published private var notice = ""
    private var finished = false
    private var closeQueued = false
    private var keyMonitor: Any?

    init(runtime: ChromiumRuntime, profile: ChromiumProfile, url: URL?, model: MacModel) throws {
        self.runtime = runtime
        self.profile = profile
        self.model = model
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        super.init()
        address = url?.absoluteString ?? ""
        window.isReleasedWhenClosed = false
        window.title = "Boaz Quick Window"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.delegate = self
        window.contentView = contentContainer
        addressField.isHidden = true
        contentContainer.addSubview(addressField)
        addressField.setAccessibilityLabel("Search or enter address")
        let hosting = NSHostingView(rootView: Content(owner: self).environment(model))
        hosting.frame = contentContainer.bounds
        hosting.autoresizingMask = [.width, .height]
        contentContainer.addSubview(hosting)
        hosting.layoutSubtreeIfNeeded()
        var options = makeOptions()
        do { handle = try runtime.createWindow(profile: profile, options: &options) }
        catch { window.delegate = nil; window.close(); throw error }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, event.window === self.window else { return false }
                return self.handleKey(event)
            }
            return consumed ? nil : event
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        if let url { load(url) } else { queue { $0.focusAddress() } }
    }

    func makeOptions() -> BoazHostWindowOptions {
        var options = BoazHostWindowOptions()
        options.size = MemoryLayout<BoazHostWindowOptions>.size
        options.native_nswindow = Unmanaged.passUnretained(window).toOpaque()
        options.context = Unmanaged.passUnretained(self).toOpaque()
        options.content_view = { context in
            let bits: UInt? = MainActor.assumeIsolated {
                guard let context else { return nil }
                let owner = Unmanaged<ChromiumQuickWindow>.fromOpaque(context).takeUnretainedValue()
                return UInt(bitPattern: Unmanaged.passUnretained(owner.contentContainer).toOpaque())
            }
            return bits.flatMap { UnsafeMutableRawPointer(bitPattern: $0) }
        }
        options.address_field = { context in
            let bits: UInt? = MainActor.assumeIsolated {
                guard let context else { return nil }
                let owner = Unmanaged<ChromiumQuickWindow>.fromOpaque(context).takeUnretainedValue()
                return UInt(bitPattern: Unmanaged.passUnretained(owner.addressField).toOpaque())
            }
            return bits.flatMap { UnsafeMutableRawPointer(bitPattern: $0) }
        }
        options.focus_address = { context in
            MainActor.assumeIsolated {
                guard let context else { return }
                let owner = Unmanaged<ChromiumQuickWindow>.fromOpaque(context).takeUnretainedValue()
                owner.focusAddress()
            }
        }
        options.focus_toolbar = options.focus_address
        options.handle_key = { context, event in
            MainActor.assumeIsolated {
                guard let context, let event else { return 0 }
                let owner = Unmanaged<ChromiumQuickWindow>.fromOpaque(context).takeUnretainedValue()
                let key = Unmanaged<NSEvent>.fromOpaque(event).takeUnretainedValue()
                return owner.handleKey(key) ? 1 : 0
            }
        }
        options.exclusive_access_notice = { context, text, visible in
            MainActor.assumeIsolated {
                guard let context else { return }
                let owner = Unmanaged<ChromiumQuickWindow>.fromOpaque(context).takeUnretainedValue()
                let copied = visible != 0 ? text.map { String(cString: $0) } ?? "" : ""
                owner.queue { $0.notice = copied }
            }
        }
        // A Quick Window has no split view, and is in no space to send its page from.
        options.menu_features = BOAZ_MENU_FEATURE_INCOGNITO.rawValue
        return options
    }

    private func queue(_ action: @escaping (ChromiumQuickWindow) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.finished else { return }
            action(self)
        }
    }
    private func focusAddress() {
        window.makeFirstResponder(addressField)
        addressField.selectText(nil)
    }
    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if modifiers == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "r" {
            queue { owner in
                do {
                    guard let page = owner.page?.adapter as? ChromiumEnginePageAdapter else { throw EnginePageError.unavailable }
                    try page.reloadFromOrigin()
                } catch { owner.failure = "The page could not reload." }
            }
            return true
        }
        guard modifiers == .command else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "l": queue { $0.focusAddress() }
        case "w": queue { $0.window.performClose(nil) }
        case "r": queue { owner in
            do { try owner.page?.reload() } catch { owner.failure = "The page could not reload." }
        }
        default: return false
        }
        return true
    }
    private func submit() {
        guard let url = SearchInput.url(for: address.trimmingCharacters(in: .whitespacesAndNewlines),
                                       searchTemplate: Preferences.searchEngine.template,
                                       schemes: SearchInput.typedSchemes) else { return }
        load(url)
    }
    private func load(_ url: URL) {
        guard !finished else { return }
        do {
            if let page { try page.navigate(to: url) }
            else { page = try runtime.createPage(window: handle, url: url, profile: profile.identity) }
            failure = ""
        } catch { failure = "The page could not open: \(error.localizedDescription)" }
    }
    private func promote() {
        guard let url = page?.state.url else { return }
        model.openInMainWindow(url, title: page?.state.title, spaceID: model.routedSpace(for: url)?.id)
        window.performClose(nil)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if finished { return true }
        guard !closeQueued else { return false }
        closeQueued = true
        queue { owner in
            let result = owner.runtime.api.close_window!(owner.handle)
            owner.closeQueued = false
            if result != BOAZ_HOST_OK { owner.failure = "The window could not close (\(result.rawValue))." }
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

    private struct Content: View {
        @ObservedObject var owner: ChromiumQuickWindow
        @Environment(MacModel.self) private var model
        var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Spacer().frame(width: 64)
                    Image(systemName: owner.page?.state.url?.scheme == "https" ? "lock.fill" : "globe")
                        .font(.caption).foregroundStyle(.secondary)
                    ChromiumAddressField(field: owner.addressField, text: $owner.address,
                        placeholder: "Search or enter address", moveUp: {}, moveDown: {},
                        submit: owner.submit, cancel: { owner.window.performClose(nil) }, fontSize: 13)
                    Button(action: owner.promote) {
                        Label("Open in Boaz", systemImage: "arrow.up.forward.app")
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.white.opacity(0.35), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .disabled(owner.page?.state.url == nil)
                }
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
                if !owner.notice.isEmpty { Text(owner.notice).font(.callout).padding(6).accessibilityLabel(owner.notice) }
                if !owner.failure.isEmpty { Text(owner.failure).font(.callout).padding(6).accessibilityLabel(owner.failure) }
                Group {
                    if let adapter = owner.page?.adapter as? ChromiumEnginePageAdapter {
                        ChromiumPageView(adapter: adapter)
                            .overlay {
                                if adapter.state.loadFailure != nil || adapter.state.lifecycle == .crashed {
                                    ChromiumLoadFailureView(adapter: adapter)
                                }
                            }
                            .overlay(alignment: .top) {
                                if adapter.state.isLoading { ProgressView().padding(8) }
                            }
                    } else {
                        Color(nsColor: .textBackgroundColor)
                    }
                }
                .clipShape(.rect(cornerRadius: Radius.row, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
                .padding([.horizontal, .bottom], 6)
            }
            .background(LinearGradient(colors: [Theme.peach.opacity(0.55), Theme.electric.opacity(0.35)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .ignoresSafeArea()
            .frame(minWidth: 420, minHeight: 320)
            .onChange(of: owner.page?.state.url) { _, url in
                if owner.addressField.currentEditor() == nil { owner.address = url?.absoluteString ?? "" }
            }
            .onChange(of: model.sidebar.profiles.map(\.id)) { _, ids in
                if !ids.contains(owner.profile.identity.id) { owner.window.performClose(nil) }
            }
        }
    }
}
#endif
