import FolioKit
import SwiftUI

/// Layout comes from size class and hinge *status*; the raw angle only drives effects (Apple's iPhone Duo guidance).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        Group {
            if sizeClass == .compact {
                CompactShell()
            } else {
                UnfoldedShell()
                    .environment(\.homeControlsElsewhere, true)
                    .overlay { FoldGlow() }
            }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast { ToastView(toast: toast).padding(.top, 8) }
        }
        .overlay {
            if model.searchTarget != nil { SearchOverlay() }
        }
        .environment(\.isPrivateBrowsing, model.isIncognito)
        .confetti(trigger: Celebration.shared.bursts)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.searchTarget)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.toast) { _, new in new?.canUndo == true }
        .sensoryFeedback(.impact(weight: .light), trigger: model.sheet) { _, new in new != nil }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in model.undoClose() }
        .sheet(item: $model.sheet, onDismiss: model.sheetDidDismiss) { sheet in
            switch sheet {
            case .library: LibrarySheet()
            case .settings: SettingsSheet()
            }
        }
        .fullScreenCover(isPresented: $model.showOnboarding) { OnboardingView() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reloadSidebar()
                model.archiveStaleTabs()
                Task { await model.sync?.syncNow() }
            }
        }
        .onHingeChange { _, new in
            withAnimation(.smooth) { model.hinge = new.hinge }
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
                        .transition(.move(edge: .leading))
                    // A hairline; in book pose, the crease itself, so the page starts past the hinge.
                    Rectangle().fill(Color(uiColor: .separator)).frame(width: creaseWidth).ignoresSafeArea()
                }
                VStack(spacing: 0) {
                    browserPane.frame(height: deskSplit?.page)
                    if let deskSplit {
                        DeskControls()
                            .padding(.top, deskSplit.gap)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
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
                .transition(.move(edge: .leading).combined(with: .opacity))
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

/// Folded (cover screen): home underneath; the active tab zooms out of its card full screen.
private struct CompactShell: View {
    @Environment(AppModel.self) private var model
    @Namespace private var zoom

    var body: some View {
        SpaceHome(zoom: zoom)
            .fullScreenCover(isPresented: Binding(get: { model.activeTabID != nil },
                                                  set: { if !$0 { model.goHome() } })) {
                if let tab = model.activeTab {
                    TabBrowser(tab: tab)
                        .environment(\.isPrivateBrowsing, model.isPrivate(tab))
                        .navigationTransition(.zoom(sourceID: tab.id, in: zoom))
                        .overlay {
                            if model.searchTarget != nil { SearchOverlay() }
                        }
                        .overlay(alignment: .top) {
                            if let toast = model.toast { ToastView(toast: toast).padding(.top, 8) }
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.searchTarget)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast)
                }
            }
    }
}

/// Half-open "laptop" posture: page on top; today's tabs and the address bar on the bottom half.
private struct DeskControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 16) {
            if let space = model.currentSpace {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(model.todayTabs(in: space)) { tab in
                            Button { model.activate(tab) } label: {
                                Text(tab.title ?? tab.url?.host() ?? "Tab").lineLimit(1)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .glassEffect(tab.id == model.activeTabID ? .regular.tint(Theme.brand) : .regular, in: .capsule)
                            }
                            .buttonStyle(.plain)
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
private struct FoldGlow: View {
    @Environment(AppModel.self) private var model

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
    }

    /// Brightest when half-open, fading out as the device lies flat.
    private var intensity: Double {
        guard let degrees = model.hinge?.angle.degrees else { return 0 }
        return max(0, 1 - abs(degrees - 110) / 70) * 0.8
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
                .font(.callout).foregroundStyle(.secondary)
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
