import SwiftUI
import TipKit
import WebKit

/// Whether a toolbar is out of the way. Scrolling down collapses it; scrolling back up, tapping the nub or pulling
/// it out brings it back. Swiping the rail toward the edge tucks it away until it's pulled back out.
@Observable final class ToolRailState {
    /// Collapsed by scrolling down; cleared by scrolling up, nearing the top or navigating.
    var scrolledAway = false
    /// Tucked away by hand; scrolling doesn't bring it back.
    var tucked = false

    var isCollapsed: Bool { scrolledAway || tucked }

    func expand() {
        scrolledAway = false
        tucked = false
    }
}

/// Puts a toolbar in the screen's right-hand column — the strip iPhone Duo reserves for the camera, time and
/// status icons — stacked vertically below those icons. Falls back to a bottom bar where there's no such column.
private struct ToolRailModifier<Rail: View>: ViewModifier {
    let rail: (Axis) -> Rail
    @State private var state = ToolRailState()
    /// The content's safe-area insets. Measured here because a reader that ignores the safe area sees none.
    @State private var insets = EdgeInsets()
    /// Live horizontal pull on the rail, toward the edge (tuck) or out of it (pop back).
    @State private var pull: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.chromeTint) private var tint

    func body(content: Content) -> some View {
        // One structural position for `content` in both layouts: switching branches around it would rebuild the
        // content (and re-host its web view) whenever the measured insets change.
        let hasColumn = insets.trailing >= 44
        content
            // A bar rather than an inset, so content scrolling under it gets the system's scroll-edge effect.
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if !hasColumn {
                    rail(.horizontal).animation(motion, value: state.isCollapsed)
                }
            }
            .overlay {
                if hasColumn {
                    GeometryReader { proxy in column(in: proxy) }
                        .ignoresSafeArea()
                }
            }
            .environment(state)
        .onGeometryChange(for: EdgeInsets.self, of: { $0.safeAreaInsets }) { insets = $0 }
        // Only a deliberate tuck; scrolling collapses the rail too often for a tap each time.
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: state.tucked) { _, tucked in tucked }
    }

    private func column(in proxy: GeometryProxy) -> some View {
        ZStack(alignment: .top) {
            if state.isCollapsed {
                // The whole empty column pulls the rail back out.
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { state.expand() }
            }
            rail(.vertical)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, railTop(in: proxy))
                .padding(.bottom, insets.bottom + 12)
                .offset(x: pull)
        }
        .frame(width: insets.trailing)
        // A light wash of the site's color: WebKit paints the page's white under the column on the cover screen,
        // so this keeps the column the site's without hurting the status icons' contrast.
        .background { if let tint { tint.opacity(0.32).transition(.opacity) } }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .simultaneousGesture(tuckAndPull)
        .animation(motion, value: state.isCollapsed)
    }

    /// Swipe the rail toward the edge to tuck it away; swipe out of the column to bring it back.
    private var tuckAndPull: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let x = value.translation.width
                guard abs(x) > abs(value.translation.height) else { return }
                pull = state.isCollapsed ? rubberBand(min(x, 0)) : rubberBand(max(x, 0))
            }
            .onEnded { value in
                let x = value.predictedEndTranslation.width
                let sideways = abs(value.translation.width) > abs(value.translation.height)
                withAnimation(motion) {
                    if sideways, state.isCollapsed, x < -30 { state.expand() }
                    else if sideways, !state.isCollapsed, x > 50 {
                        state.tucked = true
                        TuckRailTip().invalidate(reason: .actionPerformed)
                    }
                    pull = 0
                }
            }
    }

    private func rubberBand(_ x: CGFloat) -> CGFloat {
        let limit: CGFloat = 40
        return x.sign == .minus ? -limit * (1 - exp(x / limit)) : limit * (1 - exp(-x / limit))
    }

    private var motion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .bouncy(duration: 0.42, extraBounce: 0.08)
    }

    /// Just below the camera/status cluster at the top of the column.
    private func railTop(in proxy: GeometryProxy) -> CGFloat {
        let column = proxy.size.width - insets.trailing
        let occluded = proxy.reservedRegions(kind: .occlusion)
            .filter { $0.frame.maxX > column }
            .map(\.frame.maxY)
            .max()
        return (occluded ?? insets.top) + 12
    }
}

extension View {
    func toolRail<Rail: View>(@ViewBuilder _ rail: @escaping (Axis) -> Rail) -> some View {
        modifier(ToolRailModifier(rail: rail))
    }

    /// Scrolling this view down collapses the enclosing tool rail; scrolling back up restores it.
    func collapsesToolRail() -> some View { modifier(RailScrollCollapse(key: 0, webView: false, onScroll: nil)) }

    /// For a `WebView`, whose scrolling only reports through WebKit's own geometry modifier. Also restores the
    /// rail whenever `key` changes (e.g. the page navigates). Other uses of the same offset (pull to refresh) go
    /// through `onScroll`, so the web view has a single scroll-geometry observer.
    func webViewCollapsesToolRail(expandingOn key: some Equatable,
                                  onScroll: ((CGFloat, CGFloat) -> Void)? = nil) -> some View {
        modifier(RailScrollCollapse(key: key, webView: true, onScroll: onScroll))
    }
}

private struct RailScrollCollapse<Key: Equatable>: ViewModifier {
    let key: Key
    let webView: Bool
    let onScroll: ((CGFloat, CGFloat) -> Void)?
    @Environment(ToolRailState.self) private var state: ToolRailState?

    func body(content: Content) -> some View {
        Group {
            if webView {
                content.webViewOnScrollGeometryChange(for: CGFloat.self, of: offset, action: scrolled)
            } else {
                content.onScrollGeometryChange(for: CGFloat.self, of: offset, action: scrolled)
            }
        }
        .onChange(of: key) { state?.scrolledAway = false }
    }

    private func offset(_ geometry: ScrollGeometry) -> CGFloat { geometry.contentOffset.y + geometry.contentInsets.top }

    private func scrolled(from old: CGFloat, to new: CGFloat) {
        onScroll?(old, new)
        guard let state else { return }
        if new > 80, new > old + 4 {
            if !state.scrolledAway { state.scrolledAway = true }
        } else if new < old - 8 || new < 40 {
            if state.scrolledAway { state.scrolledAway = false }
        }
    }
}

/// The vertical rail: a glass dock of controls at the top, another at the bottom within thumb reach. Collapsed,
/// the top dock melts into a small nub and the bottom one dissolves; both morph back out.
struct RailColumn<Top: View, Bottom: View, Nub: View>: View {
    @Environment(ToolRailState.self) private var state
    @Environment(\.chromeTint) private var tint
    @Namespace private var glass
    @ViewBuilder var top: Top
    @ViewBuilder var bottom: Bottom
    @ViewBuilder var nub: Nub

    var body: some View {
        GlassEffectContainer(spacing: 24) {
            VStack(spacing: 0) {
                if state.isCollapsed {
                    nub
                        .padding(5)
                        .glassEffect(.chrome(tint), in: .capsule)
                        .glassEffectID("top", in: glass)
                        .contentShape(.capsule)
                        .onTapGesture { state.expand() }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Show Toolbar")
                } else {
                    dock(top).glassEffectID("top", in: glass)
                }
                Spacer(minLength: 16)
                if !state.isCollapsed {
                    dock(bottom).glassEffectID("bottom", in: glass)
                }
            }
        }
    }

    private func dock(_ content: some View) -> some View {
        VStack(spacing: 4) { content }
            .padding(5)
            .glassEffect(.chrome(tint), in: .capsule)
    }
}

extension Axis {
    /// Stack for a toolbar's buttons: down the rail, or across the bottom bar.
    func stack(spacing: CGFloat) -> AnyLayout {
        self == .vertical ? AnyLayout(VStackLayout(spacing: spacing)) : AnyLayout(HStackLayout(spacing: spacing))
    }
}

/// A button inside a rail dock (the dock supplies the glass).
struct RailButton: View {
    let symbol: String
    var label: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) { RailGlyph(symbol: symbol) }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(label ?? symbol)
    }
}

/// Bare rail icon with a full circular hit area.
struct RailGlyph: View {
    let symbol: String
    var size: CGFloat = 46
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 18

    var body: some View {
        Image(systemName: symbol)
            // Grows with Dynamic Type, but stays inside the rail's fixed-width circle.
            .font(.system(size: min(glyph, 28), weight: .semibold))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .contentShape(.circle)
    }
}

/// Round glass icon for the bottom bar.
struct RailIcon: View {
    @Environment(\.chromeTint) private var tint
    let symbol: String
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.body.weight(.medium))
            .frame(width: size, height: size)
            .glassEffect(.chrome(tint), in: .circle)
    }
}

/// Small count bubble pinned to a rail button's corner.
struct RailBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("\(count)")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(count)))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 17, minHeight: 17)
                .background(Theme.brand.gradient, in: .capsule)
                .offset(x: 4, y: -2)
                .allowsHitTesting(false)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

extension EnvironmentValues {
    /// Set when another pane's rail carries the home controls (unfolded: the browser pane's rail).
    @Entry var homeControlsElsewhere = false
    /// Set when the home page is the unfolded layout's sidebar: narrower, with Today as rows.
    @Entry var isSidebar = false
    /// The unfolded sidebar's show/hide control (`nil` where there is no sidebar).
    @Entry var sidebar: SidebarControl?
    /// The current site's color, which toolbar glass picks up (`nil`: plain glass).
    @Entry var chromeTint: Color?
}

extension Glass {
    /// Toolbar glass, lightly tinted with the site's color when there is one.
    static func chrome(_ tint: Color?) -> Glass { .regular.tint(tint?.opacity(0.45)).interactive() }
}

struct SidebarControl {
    var isCollapsed: Bool
    var toggle: () -> Void
    /// A row in the sidebar was picked, even the tab already showing: a floating sidebar gets out of the way.
    var didPick: () -> Void = {}
}

/// Shows or hides the unfolded sidebar; takes the Tabs button's place in the rail, since the sidebar lists the tabs.
struct SidebarRailButton: View {
    let sidebar: SidebarControl

    var body: some View {
        RailButton(symbol: "sidebar.left", label: sidebar.isCollapsed ? "Show Sidebar" : "Hide Sidebar",
                   action: sidebar.toggle)
    }
}
