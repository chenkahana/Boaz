import SwiftUI

/// The shared container for the page-area panels: "+" (search) and "…" (page settings).
///
///     if isOpen {
///         BottomPanel(site: edges?.bottom, maxHeight: 0.5, onDismiss: { isOpen = false }) { PanelContent() }
///     }
///     // and animate the state that inserts it with `BottomPanelStyle.motion`
///
/// - Lays out inside the safe area, so it stays in the page area: the rail column is the trailing safe-area inset
///   and stays visible and tappable. It respects the keyboard, so it rides above it.
/// - Dims the page above it slightly. Tapping the dimmed page or dragging the panel down calls `onDismiss`.
/// - Glass tinted with the site's color, in the appearance legible on it; corner radius 28, 8 pt from the page edges. Slides up from the bottom (insert it
///   with `if`; it brings its own transitions).
/// - `maxHeight` is a fraction of the page height. Content keeps its natural height up to that; greedy content
///   (a `ScrollView`) fills it.
struct BottomPanel<Content: View>: View {
    let site: SiteColor?
    let maxHeight: CGFloat
    let onDismiss: () -> Void
    let content: Content

    init(site: SiteColor? = nil, maxHeight: CGFloat = 1, onDismiss: @escaping () -> Void,
         @ViewBuilder content: () -> Content) {
        self.site = site
        self.maxHeight = maxHeight
        self.onDismiss = onDismiss
        self.content = content()
    }

    /// Live downward drag of the panel.
    @State private var drag: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.18)
                    .contentShape(.rect)
                    .onTapGesture(perform: onDismiss)
                    // The panel's escape action covers this for VoiceOver.
                    .accessibilityHidden(true)
                    .ignoresSafeArea(.container, edges: [.top, .bottom, .leading])
                    .transition(.opacity)
                MaxHeight(proxy.size.height * maxHeight - 16) { content.frame(maxWidth: .infinity) }
                    .glassEffect(.regular.tint(site?.color.opacity(0.35)),
                                 in: .rect(cornerRadius: BottomPanelStyle.cornerRadius))
                    .chromeScheme(site)
                    .accessibilityElement(children: .contain)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityAction(.escape, onDismiss)
                    .padding(8)
                    .offset(y: drag)
                    .gesture(dragToDismiss)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private var dragToDismiss: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let y = value.translation.height
                guard abs(y) > abs(value.translation.width) else { return }
                // Follows a drag down; resists a drag up.
                drag = y > 0 ? y : -12 * (1 - exp(y / 40))
            }
            .onEnded { value in
                if value.translation.height > 80 || value.predictedEndTranslation.height > 220 {
                    onDismiss()
                }
                withAnimation(BottomPanelStyle.motion) { drag = 0 }
            }
    }
}

/// Caps its content's height without stretching it (a `maxHeight` frame grows to the cap).
private struct MaxHeight: Layout {
    let limit: CGFloat
    init(_ limit: CGFloat) { self.limit = max(limit, 0) }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = min(proposal.height ?? limit, limit)
        return subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: height)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// The panels' shared motion and shape.
enum BottomPanelStyle {
    static let motion = Animation.snappy(duration: 0.3)
    static let cornerRadius: CGFloat = 28
}
