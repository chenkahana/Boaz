import BoazKit
import SwiftUI

/// One view tree for every posture, so folding never rebuilds the browser: `PostureLayout` places an optional tab
/// strip, the first pane (the same view in every posture) and, half-open, a second pane along the fold. Layout comes
/// from the window's shape and the hinge *status*, never its angle (Apple's iPhone Duo guidance).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    /// The fold, while the window is on a screen that has one (the inner screen), even lying flat.
    @State private var fold: CGRect?
    /// The whole window, keyboard or not: what a posture is made of.
    @State private var window = CGSize.zero

    private var arrangement: PostureLayout.Arrangement {
        guard let fold else { return .single }
        if model.isSplit { return .split(fold: fold) }
        // The window's shape, not the layout's: the keyboard doesn't turn a tall screen wide. Whole points, so the
        // page beside the strip is too: WebKit lays a page out in whole points and leaves the rest of a fractional
        // width as a sliver of the backdrop.
        return window.width > window.height ? .strip(width: min(max(window.width * 0.18, 150), 260).rounded()) : .single
    }

    var body: some View {
        @Bindable var model = model
        let arrangement = arrangement
        PostureLayout(arrangement: arrangement) {
            if case .strip = arrangement { TabStrip().layoutValue(key: PaneSlot.self, value: -1) }
            Pane(index: 0)
            if case .split = arrangement { Pane(index: 1).layoutValue(key: PaneSlot.self, value: 1) }
        }
        // The keyboard doesn't move the fold: the panes keep to their halves and it comes up over them.
        .ignoresSafeArea(.keyboard, edges: arrangement == .single || arrangement.hasStrip ? [] : .all)
        .environment(\.listsTabsElsewhere, arrangement.hasStrip)
        // Unfolded and taller than wide: the bar gets out of the way while reading.
        .environment(\.collapsesBar, fold != nil && arrangement == .single)
        .environment(\.posture, Posture(arrangement: arrangement, window: window))
        // A posture change resizes the panes; their pages are never animated to the new size.
        .transaction(value: Posture(arrangement: arrangement, window: window)) { $0.animation = nil }
        .background { if case .split(let fold) = arrangement { FoldFill(fold: fold) } }
        .onGeometryChange(for: CGRect?.self, of: {
            $0.reservedRegions(kind: .division, options: .includeInactive).first?.frame
        }) { fold = $0 }
        .background { Color.clear.onGeometryChange(for: CGSize.self, of: { $0.size }) { window = $0 }.ignoresSafeArea() }
        .overlay(alignment: .top) {
            if let toast = model.toast { ToastView(toast: toast).padding(.top, model.showsCoverFlow ? 64 : 8) }
        }
        .overlay {
            if model.searchTarget != nil { SearchPanel() }
        }
        .environment(\.isPrivateBrowsing, model.isIncognito)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast)
        .animation(BottomPanelStyle.motion, value: model.searchTarget)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.toast) { _, new in new?.canUndo == true }
        // While a sheet is up, the alert has to come from there instead.
        .modifier(ShakeToUndo(isEnabled: model.sheet == nil && !model.showOnboarding))
        .sheet(item: $model.sheet, onDismiss: model.sheetDidDismiss) { sheet in
            switch sheet {
            case .library: LibrarySheet()
            case .settings: SettingsSheet()
            }
        }
        .tidyAISheets()
        .sheet(item: $model.popup) { PopupSheet(popup: $0) }
        .fullScreenCover(isPresented: $model.showOnboarding) { OnboardingView() }
        .onChange(of: scenePhase) { _, phase in
            // Inactive, not background: Picture in Picture can only start while the app is still on screen.
            if phase != .background { model.sceneDidChange(isActive: phase == .active) }
            if phase == .active {
                model.reloadSidebar()
                model.archiveStaleTabs()
                model.registerDevice()
                Task { await model.sync?.syncNow() }
            }
        }
        .onHingeChange { _, new in model.hinge = new.hinge }
        // A hand-speed unfold passes through half-open on its way flat: only a posture held for a moment splits the
        // screen. Leaving the split is immediate.
        .task(id: model.hinge?.status == .partiallyOpen && fold != nil) {
            let halfOpen = model.hinge?.status == .partiallyOpen && fold != nil
            if halfOpen {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
            }
            model.setSplit(halfOpen)
        }
        // The strip lists the tabs; the carousel mustn't stay up over the pane beside it.
        .onChange(of: arrangement.hasStrip) { _, strip in
            if strip { model.showsCoverFlow = false }
        }
    }
}

/// What a pane's size is made of. A change means the posture changed, which resizes the panes.
struct Posture: Hashable {
    var arrangement: PostureLayout.Arrangement = .single
    var window = CGSize.zero
}

nonisolated private enum PaneSlot: LayoutValueKey {
    /// -1 is the tab strip; panes are 0 and 1.
    static let defaultValue = 0
}

/// Places the strip and the panes. The strip takes the leading edge; half-open, the panes meet the fold on either side.
struct PostureLayout: Layout {
    enum Arrangement: Hashable {
        case single
        case strip(width: CGFloat)
        case split(fold: CGRect)

        var hasStrip: Bool { if case .strip = self { true } else { false } }
    }

    let arrangement: Arrangement

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            let frame = frame(of: subview[PaneSlot.self], in: bounds)
            subview.place(at: frame.origin, proposal: ProposedViewSize(frame.size))
        }
    }

    private func frame(of slot: Int, in bounds: CGRect) -> CGRect {
        switch arrangement {
        case .single:
            return bounds
        case .strip(let width):
            let (strip, pane) = bounds.divided(atDistance: width, from: .minXEdge)
            return slot < 0 ? strip : pane
        case .split(let fold):
            // The fold is in the layout's own coordinates; each pane stops at its edge.
            let fold = fold.offsetBy(dx: bounds.minX, dy: bounds.minY)
            if fold.width > fold.height {
                return slot == 0 ? CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: fold.minY - bounds.minY)
                    : CGRect(x: bounds.minX, y: fold.maxY, width: bounds.width, height: bounds.maxY - fold.maxY)
            }
            return slot == 0 ? CGRect(x: bounds.minX, y: bounds.minY, width: fold.minX - bounds.minX, height: bounds.height)
                : CGRect(x: fold.maxX, y: bounds.minY, width: bounds.maxX - fold.maxX, height: bounds.height)
        }
    }
}

/// One browser: a tab's page and its bar, or the empty page, with the tab carousel over it. Half-open there are two;
/// the one the user last touched is the focused one.
private struct Pane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let index: Int
    /// The side the next tab slides in from; set while the finger is still down, so the outgoing page
    /// has already rendered with it by the time the tab changes.
    @State private var pageDirection: Edge = .trailing
    @State private var bump = 0

    var body: some View {
        ZStack {
            if let tab = model.tab(inPane: index) {
                TabBrowser(tab: tab, pageDirection: $pageDirection, bump: $bump)
                    .environment(\.isPrivateBrowsing, model.isPrivate(tab))
                    .id(tab.id)
                    .transition(pageTransition)
            } else {
                EmptyBrowser().toolRail { axis in HomeBar(axis: axis) }
            }
        }
        .sensoryFeedback(.selection, trigger: bump)
        // The animation stays on the carousel: a tab opened from it changes the page underneath without sliding.
        .overlay {
            ZStack {
                // It animates itself in and out; this fade covers being closed from outside (unfolding).
                if model.showsCoverFlow, model.focusedPane == index {
                    TabCarousel().transition(.asymmetric(insertion: .identity, removal: .opacity))
                }
            }
            .animation(carouselMotion, value: model.showsCoverFlow)
        }
        .environment(\.paneIndex, index)
        .simultaneousGesture(TapGesture().onEnded { model.focusPane(index) }, including: model.isSplit ? .all : .subviews)
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .move(edge: pageDirection),
                           removal: .move(edge: pageDirection == .trailing ? .leading : .trailing))
    }

    private var carouselMotion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .interpolatingSpring(duration: 0.42, bounce: 0.08)
    }
}

/// The fold between the two panes, in each page's own edge colors up to the middle of the fold.
private struct FoldFill: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.tintWithSiteColorsKey) private var tintWithSiteColors = true
    let fold: CGRect

    var body: some View {
        let across = fold.width > fold.height
        let halves = across ? fold.divided(atDistance: fold.height / 2, from: .minYEdge)
            : fold.divided(atDistance: fold.width / 2, from: .minXEdge)
        ZStack(alignment: .topLeading) {
            ForEach(0..<2, id: \.self) { pane in
                let rect = pane == 0 ? halves.slice : halves.remainder
                fill(pane, across: across).frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    @ViewBuilder private func fill(_ pane: Int, across: Bool) -> some View {
        if tintWithSiteColors, let edges = model.tabID(inPane: pane).flatMap({ model.siteEdges[$0] }) {
            if across {
                Rectangle().fill(pane == 0 ? edges.bottom.color : edges.top.color)
            } else {
                LinearGradient(colors: [edges.top.color, edges.bottom.color], startPoint: .top, endPoint: .bottom)
            }
        }
    }
}

/// Shake to undo, as the system does it: only with the Shake to Undo setting on, only with a tab to bring back,
/// and only after asking.
private struct ShakeToUndo: ViewModifier {
    @Environment(AppModel.self) private var model
    let isEnabled: Bool
    @State private var confirming = false

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
                guard isEnabled, UIApplication.shared.applicationSupportsShakeToEdit, model.canReopenClosedTab else { return }
                confirming = true
            }
            .alert("Undo Archive Tab?", isPresented: $confirming) {
                Button("Undo") { model.undoClose() }
                Button("Cancel", role: .cancel) {}
            }
    }
}

/// The browser with no tab open: a quiet wash of color and a way to open one.
private struct EmptyBrowser: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.paneIndex) private var pane

    var body: some View {
        let style = SpaceStyle(nil, scheme: scheme)
        VStack(spacing: 18) {
            Image(systemName: "square.on.square")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(style.tint.gradient)
            Text("No tab open").font(.system(.title2, design: .rounded, weight: .bold))
            Text("Search or enter an address to open one.")
                .font(.callout).foregroundStyle(Theme.textSecondary)
            Button("New Tab", systemImage: "plus") {
                model.focusPane(pane)
                model.beginSearch(.newTab)
            }
            .buttonStyle(.glass)
            .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RadialGradient(colors: [style.tint.opacity(scheme == .dark ? 0.22 : 0.14), .clear],
                           center: .center, startRadius: 0, endRadius: 420)
                .ignoresSafeArea()
        }
    }
}
