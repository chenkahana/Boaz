#if BOAZ_CHROMIUM
import AppKit

/// Never ordered in or made key, however asked: Chromium can still route a foreign page into a background window
/// (`clients.openWindow`, `chrome.tabs.create`, a focused `windows.update`), and the host calls ordering methods
/// directly on the native `NSWindow` it was given, so the window itself must refuse rather than relying on callers
/// to behave.
private final class BoazHiddenWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func makeKeyAndOrderFront(_ sender: Any?) {}
    override func makeKey() {}
    override func orderFront(_ sender: Any?) {}
    override func orderFrontRegardless() {}
    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        guard place == .out else { return }
        super.order(place, relativeTo: otherWin)
    }
}

/// A profile's `BackgroundPage`: one Chromium page in a window that's never ordered in, so no one sees it, it has no
/// tab in the sidebar and no entry in the Window menu, and it's left out of session restore. Chromium closes it with
/// the other windows at quit; a page that fails, crashes or stops answering closes it too, and the next run opens a
/// fresh one.
@MainActor
final class ChromiumBackgroundWindow: NSObject {
    let profile: ChromiumProfile
    private(set) var handle: BoazHostWindow = 0
    private(set) var isClosing = false
    /// Fires once, only when `close_window` itself fails: the host never confirms the close, so `windowClosed`
    /// never will either, and the owner must forget this window and release its profile itself.
    var closeFailed: (() -> Void)?
    private let runtime: ChromiumRuntime
    private let window = BoazHiddenWindow(contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768), styleMask: [.titled],
                                          backing: .buffered, defer: true)
    private let contentContainer = NSView()
    private let addressField = NSTextField()
    private var page: ChromiumEnginePageAdapter?

    init(runtime: ChromiumRuntime, profile: ChromiumProfile) throws {
        self.runtime = runtime
        self.profile = profile
        super.init()
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.contentView = contentContainer
        addressField.isHidden = true
        contentContainer.addSubview(addressField)
        var options = makeOptions()
        handle = try runtime.createWindow(profile: profile, options: &options)
    }

    func load(_ url: URL) throws {
        page = try runtime.createPage(window: handle, url: url, profile: profile.identity).adapter as? ChromiumEnginePageAdapter
    }

    /// Runs `function` on `json` parsed, in the page at `url`'s origin, and answers its string.
    func run(_ function: String, arguments json: String, at url: URL) async throws -> String {
        let key = UUID().uuidString
        do {
            let page = try await ready(at: url)
            defer {
                Task { @MainActor in
                    _ = try? await page.executeTrusted(function: "({key}) => { delete window.__boazBackgroundResults?.[key]; return null; }",
                                                       arguments: ["key": .string(key)])
                }
            }
            _ = try await page.executeTrusted(function: """
                ({key, json}) => {
                    const results = (window.__boazBackgroundResults ??= Object.create(null));
                    results[key] = {done: false};
                    Promise.resolve().then(() => (\(function))(JSON.parse(json))).then(
                        (value) => { results[key] = {done: true, value: String(value)}; },
                        (error) => { results[key] = {done: true, error: String(error?.message ?? error)}; });
                    return null;
                }
                """, arguments: ["key": .string(key), "json": .string(json)])
            // Trusted execution doesn't await a promise: wait for the result, then read it in chunks.
            for _ in 0..<240 {
                try await Task.sleep(for: .milliseconds(250))
                let state = try await page.executeTrusted(function: """
                    ({key}) => {
                        const result = window.__boazBackgroundResults?.[key];
                        return !result ? 'missing' : !result.done ? null : result.error != null ? 'error:' + result.error : 'done';
                    }
                    """, arguments: ["key": .string(key)])
                switch state {
                case .null: continue
                case .string("done"):
                    return try await ChromiumTextTransfer.read(from: page,
                        body: "return window.__boazBackgroundResults?.['\(key)']?.value;")
                case .string(let message) where message.hasPrefix("error:"):
                    throw BackgroundPage.Failure(errorDescription: String(message.dropFirst("error:".count)))
                default: throw EnginePageError.unavailable
                }
            }
            throw ChromiumTrustedScriptError.timeout
        } catch let error as BackgroundPage.Failure {
            throw error
        } catch {
            // A page that stopped answering (crashed, frozen, navigated away) is replaced on the next run.
            if !(error is CancellationError) { close() }
            throw error
        }
    }

    /// The page, once it shows `url`'s origin.
    private func ready(at url: URL) async throws -> ChromiumEnginePageAdapter {
        for _ in 0..<300 {
            guard !isClosing, let page, page.state.lifecycle == .active, page.state.loadFailure == nil else { break }
            if !page.state.isLoading, page.state.url?.host() == url.host() { return page }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw EnginePageError.unavailable
    }

    func close() {
        guard !isClosing else { return }
        isClosing = true
        // A failed close_window means the host never schedules its windowClosed callback: finish closing locally,
        // and tell the owner so it can forget this window and release its profile (`closeFailed`).
        if handle == 0 || runtime.api.close_window?(handle) != BOAZ_HOST_OK {
            finishClose()
            closeFailed?()
        }
    }

    func finishClose() {
        isClosing = true
        page = nil
        window.close()
    }

    private func makeOptions() -> BoazHostWindowOptions {
        var options = BoazHostWindowOptions()
        options.size = MemoryLayout<BoazHostWindowOptions>.size
        options.native_nswindow = Unmanaged.passUnretained(window).toOpaque()
        options.context = Unmanaged.passUnretained(self).toOpaque()
        options.content_view = { context in
            let bits: UInt? = MainActor.assumeIsolated {
                guard let context else { return nil }
                let owner = Unmanaged<ChromiumBackgroundWindow>.fromOpaque(context).takeUnretainedValue()
                return UInt(bitPattern: Unmanaged.passUnretained(owner.contentContainer).toOpaque())
            }
            return bits.flatMap { UnsafeMutableRawPointer(bitPattern: $0) }
        }
        options.address_field = { context in
            let bits: UInt? = MainActor.assumeIsolated {
                guard let context else { return nil }
                let owner = Unmanaged<ChromiumBackgroundWindow>.fromOpaque(context).takeUnretainedValue()
                return UInt(bitPattern: Unmanaged.passUnretained(owner.addressField).toOpaque())
            }
            return bits.flatMap { UnsafeMutableRawPointer(bitPattern: $0) }
        }
        options.focus_address = { _ in }
        options.focus_toolbar = { _ in }
        options.handle_key = { _, _ in 0 }
        options.exclusive_access_notice = { _, _, _ in }
        options.menu_features = 0
        return options
    }
}
#endif
