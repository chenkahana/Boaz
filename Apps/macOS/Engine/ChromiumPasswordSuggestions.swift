#if BOAZ_CHROMIUM
import AppKit

@MainActor
final class ChromiumPasswordSuggestions: NSObject, NSPopoverDelegate {
    static let shared = ChromiumPasswordSuggestions()
    private var page: ChromiumEnginePageAdapter?
    private var target: ChromiumCapturedDocument?
    private weak var window: NSWindow?
    private var sequence: UInt64 = 0
    private var generation: UInt64 = 0
    private var pending: Task<Void, Never>?
    private var observations: [NSObjectProtocol] = []
    private var scrollMonitor: Any?
    private let popover = NSPopover()

    func focus(page: ChromiumEnginePageAdapter, sequence: UInt64,
               target: ChromiumCapturedDocument?, screenBounds: CGRect, window: NSWindow) {
        if self.page?.handle == page.handle && sequence <= self.sequence {
            target?.release()
            return
        }
        dismiss()
        self.sequence = sequence
        guard let target else { return }
        self.page = page
        self.target = target
        self.window = window
        let current = generation
        pending = Task { @MainActor [weak self] in
            do {
                let probe = try target.clone()
                defer { probe.release() }
                let eligible = try await page.executeTrusted(on: probe, function: Self.predicate, arguments: [:])
                guard let self, !Task.isCancelled, self.generation == current else { return }
                guard eligible == .bool(true), page.state.lifecycle == .active,
                      page.state.navigationID == target.navigationID,
                      page.profile == target.profile, window.isKeyWindow else {
                    self.dismiss(page: page.handle)
                    return
                }
                self.show(bounds: screenBounds, window: window)
            } catch {
                guard let self, self.generation == current else { return }
                self.dismiss(page: page.handle)
            }
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.didResizeNotification,
                     NSWindow.willCloseNotification, NSWindow.didMoveNotification] {
            observations.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                [weak self] _ in
                Task { @MainActor in
                    guard let self, self.generation == current else { return }
                    self.dismiss()
                }
            })
        }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            let relevant = MainActor.assumeIsolated { self?.window === event.window }
            if relevant {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == current else { return }
                    self.dismiss(page: page.handle)
                }
            }
            return event
        }
    }

    func dismiss(page handle: BoazHostPage? = nil) {
        if let handle, page?.handle != handle { return }
        generation &+= 1
        pending?.cancel()
        pending = nil
        target?.release()
        target = nil
        page = nil
        window = nil
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        scrollMonitor = nil
        popover.delegate = nil
        popover.close()
    }

    private func show(bounds: CGRect, window: NSWindow) {
        guard let content = window.contentView, let primary = NSScreen.screens.first,
              bounds.minX.isFinite, bounds.minY.isFinite,
              bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else {
            dismiss(); return
        }
        let appKitScreen = NSRect(x: bounds.minX, y: primary.frame.maxY - bounds.maxY,
                                  width: bounds.width, height: bounds.height)
        let local = content.convert(window.convertFromScreen(appKitScreen), from: nil)
        let anchor = local.intersection(content.bounds)
        guard !anchor.isNull, !anchor.isEmpty else { dismiss(); return }
        let controller = NSViewController()
        let button = NSButton(title: "Fill Saved Password…", target: self, action: #selector(fill))
        button.bezelStyle = .rounded
        button.setAccessibilityLabel("Fill Saved Password")
        controller.view = NSView(frame: NSRect(x: 0, y: 0, width: 230, height: 46))
        button.frame = NSRect(x: 10, y: 10, width: 210, height: 26)
        controller.view.addSubview(button)
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.delegate = self
        popover.show(relativeTo: anchor, of: content, preferredEdge: .minY)
    }

    @objc private func fill() {
        guard let page, let window, let target else { dismiss(); return }
        self.target = nil
        dismiss()
        Task { @MainActor in
            await ChromiumPasswordFill.run(on: page, window: window, capturedTarget: target) {
                MacModel.shared.showToast($0)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        let current = generation
        Task { @MainActor [weak self] in
            guard let self, self.generation == current else { return }
            self.dismiss()
        }
    }

    private static let predicate = """
        () => {
            const e = document.activeElement;
            if (!(e instanceof HTMLInputElement) || !e.isConnected || e.disabled || e.readOnly) return false;
            if (e.type === 'password') return true;
            if (!['text', 'email'].includes(e.type) || !e.form) return false;
            const fields = e.form.elements;
            if (fields.length > 128) return false;
            const named = /user|email|login|account|identifier/i.test(
                [e.name, e.id, e.autocomplete, e.getAttribute('aria-label')].join(' '));
            if (!named && e.type !== 'email') return false;
            for (let i = 0; i < fields.length; ++i) {
                if (fields[i] instanceof HTMLInputElement && fields[i].type === 'password') return true;
            }
            return false;
        }
        """
}
#endif
