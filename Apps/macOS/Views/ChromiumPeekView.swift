#if BOAZ_CHROMIUM
import SwiftUI

struct ChromiumPeekView: View {
    @Environment(BrowserState.self) private var browser
    let adapter: ChromiumEnginePageAdapter
    let backdrop: NSImage?

    var body: some View {
        ZStack {
            if let backdrop {
                GeometryReader { geometry in
                    Image(nsImage: backdrop).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }.accessibilityHidden(true)
            }
            Color.black.opacity(0.22).contentShape(Rectangle())
                .onTapGesture { browser.closePeek() }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "globe").font(.caption).foregroundStyle(.secondary)
                    Text(adapter.state.title.isEmpty ? (adapter.state.url?.host() ?? "Loading…") : adapter.state.title)
                        .font(.callout.weight(.medium)).lineLimit(1)
                    Spacer()
                    HoverIconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Open as Tab") {
                        browser.promotePeek()
                    }.disabled(browser.chromiumPeekClosing || adapter.state.lifecycle != .active)
                    HoverIconButton(symbol: "xmark", help: "Close", hint: "Close (Esc)") {
                        browser.closePeek()
                    }.disabled(browser.chromiumPeekClosing)
                }.padding(.horizontal, 12).frame(height: 38)
                ChromiumPageView(adapter: adapter)
                    .overlay {
                        if adapter.state.loadFailure != nil || adapter.state.lifecycle == .crashed {
                            ChromiumLoadFailureView(adapter: adapter)
                        }
                    }
                    .overlay(alignment: .top) {
                        if adapter.state.isLoading { ProgressView().padding(8) }
                    }
            }
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: MacRadius.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MacRadius.panel).strokeBorder(.white.opacity(0.3)))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
            .padding(.horizontal, 56).padding(.vertical, 32)
        }
    }
}
#endif
