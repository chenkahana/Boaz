#if BOAZ_CHROMIUM
import AppKit
import SwiftUI

struct ChromiumTabPreview: ViewModifier {
    @Environment(BrowserState.self) private var browser
    let tabID: String
    let title: String?
    let url: URL?
    let enabled: Bool
    @State private var hovering = false
    @State private var snapshot: Snapshot?

    struct Snapshot: Identifiable {
        let id = UUID()
        let image: NSImage
        let title: String
        let host: String
    }
    private struct HoverRequest: Equatable {
        let tabID: String
        let url: URL?
        let hovering: Bool
    }
    private var actualURL: URL? { browser.cachedChromiumPage(for: tabID)?.state.url ?? url }

    func body(content: Content) -> some View {
        content
            .onHover { hovering = $0; if !$0 { snapshot = nil } }
            .task(id: HoverRequest(tabID: tabID, url: actualURL, hovering: hovering)) {
                snapshot = nil
                guard enabled, hovering, browser.createChromiumPage != nil else { return }
                let expectedURL = actualURL
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                guard !Task.isCancelled, hovering, actualURL == expectedURL,
                      browser.window?.isVisible == true,
                      let image = browser.chromiumPreview(for: tabID, url: expectedURL) else { return }
                snapshot = Snapshot(image: image,
                    title: browser.cachedChromiumPage(for: tabID)?.state.title.nonEmpty ?? title ?? expectedURL?.host() ?? "Page",
                    host: expectedURL?.host() ?? "")
            }
            // Not a popover: a transient popover swallows the click that dismisses it, so the row under the pointer
            // missed clicks and drags. The panel beside the row never takes the mouse or focus.
            .background(PreviewAnchor(snapshot: snapshot))
            .onChange(of: browser.activeTabID) { snapshot = nil; hovering = false }
            .onDisappear { snapshot = nil; hovering = false }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
                guard let window = note.object as? NSWindow, window === browser.window else { return }
                snapshot = nil
                hovering = false
            }
    }
}

private struct PreviewAnchor: NSViewRepresentable {
    let snapshot: ChromiumTabPreview.Snapshot?

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        if let snapshot { TabPreviewPanel.shared.show(snapshot, beside: view) } else { TabPreviewPanel.shared.hide(from: view) }
    }

    static func dismantleNSView(_ view: NSView, coordinator: ()) { TabPreviewPanel.shared.hide(from: view) }
}

/// One floating preview at a time, beside its row. It ignores the mouse, never becomes key, and goes away at the
/// next click anywhere.
@MainActor
private final class TabPreviewPanel {
    static let shared = TabPreviewPanel()

    private let panel: NSPanel
    private weak var owner: NSView?
    private var monitor: Any?
    /// The preview on screen, and the last one a click put away: a row redrawing doesn't bring that one back.
    private var shown: UUID?
    private var dismissed: UUID?

    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.hide(from: nil)
            return event
        }
    }

    func show(_ snapshot: ChromiumTabPreview.Snapshot, beside anchor: NSView) {
        guard let window = anchor.window, snapshot.id != dismissed, snapshot.id != shown || owner !== anchor else { return }
        let host = NSHostingView(rootView: PreviewCard(snapshot: snapshot))
        host.frame.size = host.fittingSize
        panel.contentView = host
        let row = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        var frame = NSRect(x: row.maxX + 8, y: row.midY - host.frame.height / 2,
                           width: host.frame.width, height: host.frame.height)
        if let screen = window.screen?.visibleFrame {
            frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        }
        panel.setFrame(frame, display: true)
        panel.orderFront(nil)
        owner = anchor
        shown = snapshot.id
    }

    /// Hides the preview if `anchor` (or anyone, when nil) is showing it.
    func hide(from anchor: NSView?) {
        guard anchor == nil || owner === anchor else { return }
        if anchor == nil { dismissed = shown }
        shown = nil
        panel.orderOut(nil)
        panel.contentView = nil
        owner = nil
    }
}

private struct PreviewCard: View {
    let snapshot: ChromiumTabPreview.Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(nsImage: snapshot.image).resizable().scaledToFit()
                .frame(width: 264, height: 176)
                .background(.background)
                .clipShape(.rect(cornerRadius: 8))
            Text(snapshot.title).font(.callout.weight(.medium)).lineLimit(2)
            if !snapshot.host.isEmpty { Text(snapshot.host).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(12).frame(width: 288)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
#endif
