import BoazKit
import SwiftUI

/// Layout comes from size class and hinge *status*; the raw angle only drives effects (Apple's iPhone Duo guidance).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    /// Whether the screen has a fold (iPhone Duo), even while it lies flat.
    @State private var hasFold = false

    /// The unfolded layout is for a foldable's inner screen; a large iPhone turned landscape is also regular width
    /// but keeps the folded layout.
    private var isUnfolded: Bool { sizeClass == .regular && (model.hinge != nil || hasFold) }

    var body: some View {
        @Bindable var model = model
        Group {
            if !isUnfolded {
                CompactShell()
            } else {
                UnfoldedShell()
                    .environment(\.homeControlsElsewhere, true)
                    .overlay { FoldGlow() }
            }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast { ToastView(toast: toast).padding(.top, model.showsCoverFlow ? 64 : 8) }
        }
        .overlay {
            if model.searchTarget != nil { SearchPanel() }
        }
        .environment(\.isPrivateBrowsing, model.isIncognito)
        .confetti(trigger: Celebration.shared.bursts)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast)
        .animation(BottomPanelStyle.motion, value: model.searchTarget)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.toast) { _, new in new?.canUndo == true }
        // While the folded layout's page cover or a sheet is up, the alert has to come from there instead.
        .modifier(ShakeToUndo(isEnabled: model.sheet == nil && !model.showOnboarding
                                         && (isUnfolded || model.activeTabID == nil)))
        .onGeometryChange(for: Bool.self, of: { !$0.reservedRegions(kind: .division, options: .includeInactive).isEmpty }) {
            hasFold = $0
        }
        .sheet(item: $model.sheet, onDismiss: model.sheetDidDismiss) { sheet in
            switch sheet {
            case .library: LibrarySheet()
            case .settings: SettingsSheet()
            }
        }
        .tidyAISheets()
        .fullScreenCover(isPresented: $model.showOnboarding) { OnboardingView() }
        .spaceEditorPresenter()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reloadSidebar()
                model.archiveStaleTabs()
                model.registerDevice()
                Task { await model.sync?.syncNow() }
            }
        }
        .onHingeChange { _, new in
            withAnimation(.smooth) { model.hinge = new.hinge }
        }
        // The tab carousel belongs to the folded layout; unfolding mustn't leave it waiting for the next fold.
        .onChange(of: isUnfolded) { _, unfolded in
            if unfolded { model.showsCoverFlow = false }
        }
    }

}

/// The inner screen. One structure for every flat and book pose, so the page is never rebuilt as the hinge moves:
/// - flat and wide (landscape): Arc's sidebar beside the page; it can be hidden.
/// - flat and narrow (portrait): the page gets the whole width; the sidebar floats over it as a card when called.
/// - book (half-open, fold running top to bottom): the sidebar fills the left half up to the fold, the page the right.
/// - laptop (half-open, fold running across): the page on the upper half, controls on the lower one.
private struct UnfoldedShell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("sidebarCollapsed") private var sidebarCollapsed = false
    @AppStorage(Preferences.tintWithSiteColorsKey) private var tintWithSiteColors = true
    /// The narrow layout's floating sidebar.
    @State private var cardOpen = false
    @State private var size = CGSize.zero
    @State private var fold: CGRect?

    private enum Pose: Equatable { case wide, narrow, book, laptop }

    private var pose: Pose {
        if model.isDeskPosture {
            let vertical = fold.map { $0.height > $0.width } ?? (size.height > size.width)
            return vertical ? .book : .laptop
        }
        return size.width >= 820 ? .wide : .narrow
    }

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                if let width = inlineSidebarWidth {
                    sidebar
                        .frame(width: width)
                        .transition(reduceMotion ? .opacity : .move(edge: .leading))
                    // A hairline; in book pose, the crease itself, so the page starts past the hinge, in the page's
                    // colors while one is showing.
                    Group {
                        if pose == .book, let edges = pageEdges {
                            LinearGradient(colors: [edges.top.color, edges.bottom.color], startPoint: .top,
                                           endPoint: .bottom)
                        } else {
                            Color(uiColor: .separator)
                        }
                    }
                    .frame(width: creaseWidth)
                    .ignoresSafeArea()
                }
                VStack(spacing: 0) {
                    browserPane.frame(height: deskSplit?.page)
                    if let deskSplit {
                        DeskControls()
                            .padding(.top, deskSplit.gap)
                            // The fold under the page takes the page's bottom color.
                            .background(alignment: .top) {
                                if let edges = pageEdges {
                                    Rectangle().fill(edges.bottom.color).frame(height: deskSplit.gap)
                                }
                            }
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            if pose == .narrow, cardOpen { floatingSidebar }
        }
        .environment(\.sidebar, sidebarControl)
        .onGeometryChange(for: CGSize.self, of: { $0.size }) { size = $0 }
        .onGeometryChange(for: CGRect?.self, of: { $0.reservedRegions(kind: .division).first?.frame }) { fold = $0 }
        .onChange(of: model.activeTabID) { _, id in
            // Picking a tab puts the floating card away; closing the last one brings it back to choose another.
            withAnimation(motion) { cardOpen = id == nil }
        }
        // A card opened earlier shouldn't reappear on returning to the narrow layout.
        .onChange(of: pose) { cardOpen = model.activeTabID == nil }
        .onAppear { cardOpen = model.activeTabID == nil }
        .animation(motion, value: pose)
        .animation(SiteEdges.fade(reduceMotion: reduceMotion), value: pageEdges)
    }

    /// The showing page's edge colors, which the fold beside or below it takes on.
    private var pageEdges: SiteEdges? {
        guard tintWithSiteColors, let id = model.activeTabID else { return nil }
        return model.siteEdges[id]
    }

    /// Nil when the sidebar isn't laid out beside the page.
    private var inlineSidebarWidth: CGFloat? {
        switch pose {
        // With no page to make room for, the sidebar shows even when hidden.
        case .wide: sidebarCollapsed && model.activeTabID != nil ? nil : 300
        case .book: max(fold?.minX ?? size.width / 2, 260)
        case .narrow, .laptop: nil
        }
    }

    private var creaseWidth: CGFloat { pose == .book ? max(fold?.width ?? 0, 0.5) : 0.5 }

    /// Laptop pose: the page's height down to the fold, and the fold's own height before the controls.
    private var deskSplit: (page: CGFloat, gap: CGFloat)? {
        guard pose == .laptop else { return nil }
        guard let fold else { return (size.height / 2, 0) }
        return (fold.minY, fold.height)
    }

    private var sidebar: some View { SpaceHome().environment(\.isSidebar, true) }

    private var floatingSidebar: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture { withAnimation(motion) { cardOpen = false } }
                .accessibilityLabel("Close sidebar")
                .accessibilityAddTraits(.isButton)
            sidebar
                .frame(width: min(340, size.width - 72))
                // The space gradient is translucent; the card must hide the page under it.
                .background(Color(uiColor: .systemBackground).ignoresSafeArea())
                .clipShape(.rect(cornerRadius: 30, style: .continuous))
                .shadow(color: .black.opacity(0.22), radius: 24, x: 6)
                .padding(8)
                .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
        }
        // VoiceOver stays on the card (and its scrim's close action) instead of reaching the page beneath.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .transition(.opacity)
    }

    /// The sidebar button in the rail and the sidebar's header. Book pose has no control: the sidebar is the left half.
    private var sidebarControl: SidebarControl? {
        switch pose {
        case .wide where model.activeTabID == nil:
            nil
        case .wide:
            SidebarControl(isCollapsed: sidebarCollapsed) { withAnimation(motion) { sidebarCollapsed.toggle() } }
        case .narrow:
            SidebarControl(isCollapsed: !cardOpen,
                           toggle: { withAnimation(motion) { cardOpen.toggle() } },
                           didPick: { withAnimation(motion) { cardOpen = false } })
        case .book, .laptop:
            nil
        }
    }

    private var motion: Animation { reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.34) }

    @ViewBuilder private var browserPane: some View {
        if let tab = model.activeTab {
            TabBrowser(tab: tab)
        } else {
            EmptyBrowser()
                .toolRail { axis in HomeBar(axis: axis) }
        }
    }
}

/// Folded (cover screen): home underneath; the active tab zooms out of its card full screen. The tab carousel of
/// Today tabs opens over whichever is showing, and moves to the home screen if its last open page is archived.
private struct CompactShell: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var zoom

    var body: some View {
        SpaceHome(zoom: zoom)
            .overlay { carousel(zoom: zoom, isShown: model.showsCoverFlow && model.activeTabID == nil) }
            .fullScreenCover(isPresented: Binding(get: { model.activeTabID != nil },
                                                  set: { if !$0 { model.goHome() } })) {
                // One view for every tab, so the overlays (the carousel closing into the tab it opened) aren't
                // rebuilt when the tab changes.
                ZStack {
                    if let tab = model.activeTab {
                        TabBrowser(tab: tab).environment(\.isPrivateBrowsing, model.isPrivate(tab))
                    }
                }
                .navigationTransition(.zoom(sourceID: model.activeTabID ?? "", in: zoom))
                .overlay { carousel(zoom: nil, isShown: model.showsCoverFlow) }
                .overlay {
                    if model.searchTarget != nil { SearchPanel() }
                }
                .overlay(alignment: .top) {
                    if let toast = model.toast { ToastView(toast: toast).padding(.top, model.showsCoverFlow ? 64 : 8) }
                }
                .animation(BottomPanelStyle.motion, value: model.searchTarget)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast)
                .modifier(ShakeToUndo(isEnabled: true))
            }
    }

    /// The animation stays on the carousel: a tab opened from it changes the page underneath without sliding.
    private func carousel(zoom: Namespace.ID?, isShown: Bool) -> some View {
        ZStack {
            // It animates itself in and out; this fade covers being closed from outside (unfolding, Home).
            if isShown { TabCarousel(zoom: zoom).transition(.asymmetric(insertion: .identity, removal: .opacity)) }
        }
        .animation(carouselMotion, value: isShown)
    }

    private var carouselMotion: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .interpolatingSpring(duration: 0.42, bounce: 0.08)
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

/// Half-open "laptop" posture: page on top; today's tabs and the address bar on the bottom half.
private struct DeskControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: 16) {
            if let space = model.currentSpace {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(model.todayTabs(in: space)) { tab in
                            let selected = tab.id == model.activeTabID
                            Button { model.activate(tab) } label: {
                                Text(tab.title ?? tab.url?.host() ?? "New Tab").lineLimit(1)
                                    .padding(.horizontal, 14).padding(.vertical, 12)
                                    .frame(minHeight: 44)
                                    .glassEffect(selected ? .regular.tint(Theme.brand) : .regular, in: .capsule)
                                    .overlay {
                                        if selected, contrast == .increased {
                                            Capsule().strokeBorder(.primary.opacity(0.4), lineWidth: 1)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            Button { model.beginSearch(.newTab) } label: {
                Label("Search or enter address", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .glassEffect(.regular.interactive(), in: .capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SpaceStyle(model.currentSpace, scheme: scheme).gradient.ignoresSafeArea())
    }
}

/// Soft glow along the fold. Uses the division reserved region for placement and hinge angle for intensity.
/// It flares once as the device settles half-open, then stays faint. Only with no page showing: beside a page, the
/// fold takes the page's colors instead.
private struct FoldGlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flare = false

    var body: some View {
        GeometryReader { proxy in
            ForEach(proxy.reservedRegions(kind: .division)) { region in
                Rectangle()
                    .fill(Theme.glow)
                    .frame(width: max(region.frame.width, 2), height: max(region.frame.height, 2))
                    .position(x: region.frame.midX, y: region.frame.midY)
                    .blur(radius: 6)
                    .opacity(intensity)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
        .onChange(of: model.isDeskPosture) { _, halfOpen in
            guard halfOpen, !reduceMotion else { return }
            withAnimation(.easeIn(duration: 0.3)) { flare = true } completion: {
                withAnimation(.easeOut(duration: 1.2)) { flare = false }
            }
        }
    }

    /// Brightest when half-open, fading out as the device lies flat. An effect only, so none with Reduce Motion.
    private var intensity: Double {
        guard !reduceMotion, model.activeTabID == nil, let degrees = model.hinge?.angle.degrees else { return 0 }
        return max(0, 1 - abs(degrees - 110) / 70) * (flare ? 0.35 : 0.15)
    }
}

/// The unfolded browser pane with no tab open: a quiet wash of the space's color and a way to open one.
private struct EmptyBrowser: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let style = SpaceStyle(model.currentSpace, scheme: scheme)
        VStack(spacing: 18) {
            Image(systemName: "square.on.square")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(style.tint.gradient)
            Text("No tab open").font(.system(.title2, design: .rounded, weight: .bold))
            Text("Pick a tab in the sidebar, or open a new one.")
                .font(.callout).foregroundStyle(Theme.textSecondary)
            Button("New Tab", systemImage: "plus") { model.beginSearch(.newTab) }
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
