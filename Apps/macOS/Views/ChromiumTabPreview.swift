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

    private struct Snapshot: Identifiable {
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
            .popover(item: $snapshot, arrowEdge: .trailing) { value in
                VStack(alignment: .leading, spacing: 8) {
                    Image(nsImage: value.image).resizable().scaledToFit()
                        .frame(width: 264, height: 176)
                        .background(.background)
                        .clipShape(.rect(cornerRadius: 8))
                    Text(value.title).font(.callout.weight(.medium)).lineLimit(2)
                    if !value.host.isEmpty { Text(value.host).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }
                .padding(12).frame(width: 288)
                .allowsHitTesting(false)
            }
            .onChange(of: browser.activeTabID) { snapshot = nil; hovering = false }
            .onDisappear { snapshot = nil; hovering = false }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
                guard let window = note.object as? NSWindow, window === browser.window else { return }
                snapshot = nil
                hovering = false
            }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
#endif
