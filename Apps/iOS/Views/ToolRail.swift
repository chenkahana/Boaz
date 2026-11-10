import SwiftUI
import TipKit
import WebKit

/// Puts a toolbar in the screen's right-hand column — the strip iPhone Duo reserves for the camera, time and
/// status icons — stacked vertically below those icons. Falls back to a bottom bar where there's no such column.
private struct ToolRailModifier<Rail: View>: ViewModifier {
    /// Whether content scrolling under the bottom bar gets the system's scroll-edge effect.
    let edgeEffect: Bool
    /// Whether the bottom bar floats over the content instead of ending it (a bar that collapses while reading).
    let overlaysContent: Bool
    let rail: (Axis) -> Rail
    /// The content's safe-area insets. Measured here because a reader that ignores the safe area sees none.
    @State private var insets = EdgeInsets()
    @State private var barHeight: CGFloat = 0
    @Environment(\.siteEdges) private var edges

    func body(content: Content) -> some View {
        // One structural position for `content` in both layouts: switching branches around it would rebuild the
        // content (and re-host its web view) whenever the measured insets change.
        let hasColumn = insets.trailing >= 44
        bottomBar(content, shown: !hasColumn)
            .overlay {
                if hasColumn {
                    GeometryReader { proxy in column(in: proxy) }
                        .ignoresSafeArea()
                }
            }
        .onGeometryChange(for: EdgeInsets.self, of: { $0.safeAreaInsets }) { insets = $0 }
    }

    /// A bar gives content scrolling under it the system's scroll-edge effect. A web page fills that effect with
    /// its own background color, which can be far from what's showing (a pale band across a dark hero image), so
    /// a page ends above its bar instead, which brings its own background. `edgeEffect` never changes for a given
    /// use, so `content` keeps its place.
    @ViewBuilder private func bottomBar(_ content: Content, shown: Bool) -> some View {
        let bar = ZStack { if shown { rail(.horizontal) } }
        if edgeEffect {
            content.safeAreaBar(edge: .bottom, spacing: 0) { bar }
        } else {
            // Floating, the bar takes no room: the content keeps its frame and gets the bar's height as safe area,
            // so its last line can scroll clear of the bar. One structure either way, so `content` keeps its place.
            let floats = shown && overlaysContent
            VStack(spacing: 0) {
                content.safeAreaPadding(.bottom, floats ? barHeight : 0)
                bar.onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { barHeight = $0 }
                    .frame(height: floats ? 0 : nil, alignment: .bottom)
            }
        }
    }

    private func column(in proxy: GeometryProxy) -> some View {
        rail(.vertical)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, railTop(in: proxy))
            .padding(.bottom, insets.bottom + 12)
            .frame(width: insets.trailing)
        // The page's own background, so the page seems to run under the camera and status icons (which pick
        // their contrast from what's under them). It holds still while the page scrolls.
        .background {
            if let edges { Rectangle().fill(edges.page.color).transition(.opacity) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
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
    func toolRail<Rail: View>(edgeEffect: Bool = true, overlaysContent: Bool = false,
                              @ViewBuilder _ rail: @escaping (Axis) -> Rail) -> some View {
        modifier(ToolRailModifier(edgeEffect: edgeEffect, overlaysContent: overlaysContent, rail: rail))
    }
}

/// The vertical rail: two glass docks of controls at the bottom, within thumb reach, the main one (`top`) above the
/// other. Always shown; nothing tucks it away.
struct RailColumn<Top: View, Bottom: View>: View {
    @Environment(\.chromeTint) private var tint
    @Environment(\.siteEdges) private var edges
    @ViewBuilder var top: Top
    @ViewBuilder var bottom: Bottom

    var body: some View {
        // Both docks sit on the page's background.
        let site = edges?.page
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            dock(top, on: site)
            dock(bottom, on: site)
        }
    }

    private func dock(_ content: some View, on site: SiteColor?) -> some View {
        VStack(spacing: 4) { content }
            .padding(5)
            .glassEffect(.chrome(site?.color ?? tint), in: .capsule)
            .chromeScheme(site)
    }
}

extension Axis {
    /// Stack for a toolbar's buttons: down the rail, or across the bottom bar.
    func stack(spacing: CGFloat) -> AnyLayout {
        self == .vertical ? AnyLayout(VStackLayout(spacing: spacing)) : AnyLayout(HStackLayout(spacing: spacing))
    }
}

/// A rail dock laid across the bottom bar: one glass capsule around its buttons.
struct BarDock<Content: View>: View {
    @Environment(\.chromeTint) private var tint
    var site: SiteColor?
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 2) { content }
            .padding(3)
            .glassEffect(.chrome(site?.color ?? tint), in: .capsule)
    }
}

/// A button inside a rail dock (the dock supplies the glass).
struct RailButton: View {
    let symbol: String
    var label: String?
    /// Shown pressed: the panel or screen this button opens is up.
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { RailGlyph(symbol: symbol).railSelection(isSelected) }
            .buttonStyle(PressableStyle())
            .accessibilityLabel(label ?? symbol)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension View {
    /// The pressed look of a rail or bar button whose panel is open.
    func railSelection(_ isSelected: Bool) -> some View {
        background {
            if isSelected {
                Circle().fill(.primary.opacity(0.16)).transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: isSelected)
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
    @ScaledMetric(relativeTo: .body) private var glyph: CGFloat = 17

    var body: some View {
        Image(systemName: symbol)
            // Grows with Dynamic Type, but stays inside its fixed-size circle.
            .font(.system(size: min(glyph, 26), weight: .medium))
            .frame(width: size, height: size)
            .glassEffect(.chrome(tint), in: .circle)
    }
}

extension EnvironmentValues {
    /// Set beside the tab strip, which lists the tabs: the bar has no tab fan.
    @Entry var listsTabsElsewhere = false
    /// Set where the bottom bar collapses while reading (unfolded, taller than wide).
    @Entry var collapsesBar = false
    /// Which pane a view is in: 0, or 1 for the second pane half-open.
    @Entry var paneIndex = 0
    /// The posture the pane is laid out for (see `RootView`).
    @Entry var posture = Posture()
    /// The current site's color, which toolbar glass picks up (`nil`: plain glass).
    @Entry var chromeTint: Color?
    /// The current page's edge colors, which the rail's column takes on (`nil`: no page, or tinting is off).
    @Entry var siteEdges: SiteEdges?
}

extension View {
    /// Chrome drawn over a site color takes the appearance legible on it: dark glyphs and light glass on a light
    /// color, and the reverse. Unchanged without one. The glyph color is explicit because glass otherwise picks
    /// its content's vibrancy from the system appearance.
    func chromeScheme(_ site: SiteColor?) -> some View { modifier(ChromeScheme(site: site)) }
}

/// The same view with a site color or without: a branch on it would rebuild the chrome when a page's colors arrive,
/// taking the keyboard from the search field.
private struct ChromeScheme: ViewModifier {
    let site: SiteColor?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .foregroundStyle(site.map { AnyShapeStyle($0.isLight ? Color.black : Color.white) } ?? AnyShapeStyle(.foreground))
            .environment(\.colorScheme, site?.colorScheme ?? colorScheme)
    }
}

extension Glass {
    /// Toolbar glass, lightly tinted with the site's color when there is one.
    static func chrome(_ tint: Color?) -> Glass { .regular.tint(tint?.opacity(0.45)).interactive() }
}
