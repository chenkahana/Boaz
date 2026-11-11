import SwiftUI
import WebKit

/// What a browser keeps of its page's scrolling: where the reader is and how the bar should be. A plain object, so
/// following a scroll never redraws the browser.
final class PageScroll {
    struct Sample: Hashable {
        /// From the top of the page; negative while pulled down past it.
        var offset: CGFloat
        var maxOffset: CGFloat
        var contentHeight: CGFloat
        var container: CGSize

        init(_ geometry: ScrollGeometry) {
            offset = geometry.contentOffset.y + geometry.contentInsets.top
            contentHeight = geometry.contentSize.height
            maxOffset = contentHeight + geometry.contentInsets.top + geometry.contentInsets.bottom
                - geometry.containerSize.height
            container = geometry.containerSize
        }
    }

    /// While a resize is covered, the page's own scrolling is not the reader's.
    var isHeld = false
    /// The reader's place as a fraction of the document's height, once known.
    private var fraction: CGFloat?
    private var container = CGSize.zero
    /// Where the bar last turned, followed while the page keeps going the same way.
    private var barAnchor: CGFloat = 0

    /// Follows the reader. A sample at a new size comes from the resize, not the reader.
    func note(_ sample: Sample) {
        defer { container = sample.container }
        guard !isHeld, sample.container == container, sample.contentHeight > 0 else { return }
        fraction = max(sample.offset, 0) / sample.contentHeight
    }

    /// The bar collapses as the page scrolls down and comes back as it scrolls up, after `hysteresis` points either
    /// way, and always at the top and the bottom.
    func barCollapses(_ sample: Sample, collapsed: Bool, hysteresis: CGFloat = 12) -> Bool {
        guard !isHeld else { return collapsed }
        if sample.offset <= 0 || sample.offset >= sample.maxOffset - 1 {
            barAnchor = sample.offset
            return false
        }
        let travel = sample.offset - barAnchor
        if collapsed ? travel > 0 : travel < 0 {
            barAnchor = sample.offset
        } else if abs(travel) > hysteresis {
            barAnchor = sample.offset
            return !collapsed
        }
        return collapsed
    }

    /// Back to the reader's place after the page laid out at a new width.
    func restore(on page: WebPage) async {
        guard let fraction else { return }
        _ = try? await page.callJavaScript("window.scrollTo(0, fraction * document.documentElement.scrollHeight)",
                                           arguments: ["fraction": fraction], contentWorld: .defaultClient)
    }
}

/// Covers a page while a posture change resizes it, as Safari does: its preview (the viewport as last seen at rest,
/// `AppModel.snapshots`) scaled to the new width, until the size has held still and the page is back at the
/// reader's place, then a quick cross-fade to the live page.
struct RelayoutCover: ViewModifier {
    let page: WebPage
    let scroll: PageScroll
    let snapshot: () -> UIImage?
    let background: Color
    @Environment(\.posture) private var posture
    @State private var cover: UIImage?
    @State private var width: CGFloat = 0
    @State private var settling: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let cover { PreviewCover(image: cover, background: background) }
            }
            .onChange(of: posture) { hold() }
            // Mid-fold the width can change more than once, and not always with the posture.
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { new in
                if width > 0 { hold() }
                width = new
            }
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { _ in if scroll.isHeld { settle() } }
    }

    private func hold() {
        scroll.isHeld = true
        if cover == nil { cover = snapshot() }
        settle()
    }

    private func settle() {
        settling?.cancel()
        settling = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            // A page busy with script may answer late, or never: the cover waits for it only so long.
            let (answered, answer) = AsyncStream<Void>.makeStream()
            Task { await scroll.restore(on: page); answer.yield() }
            Task { try? await Task.sleep(for: .milliseconds(300)); answer.yield() }
            for await _ in answered { break }
            guard !Task.isCancelled else { return }
            scroll.isHeld = false
            withAnimation(.easeOut(duration: 0.2)) { cover = nil }
        }
    }
}

/// A page's preview over the page, scaled to its width, while the page itself isn't showing what the reader saw.
struct PreviewCover: View {
    let image: UIImage
    let background: Color

    var body: some View {
        background
            .overlay(alignment: .top) {
                Image(uiImage: image).resizable().scaledToFit().fixedSize(horizontal: false, vertical: true)
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
    }
}
