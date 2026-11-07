import FolioKit
import SwiftUI

/// Layout comes from size class and hinge *status*; the raw angle only drives effects (Apple's iPhone Duo guidance).
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .compact {
                CompactShell()
            } else {
                ArrangementView {
                    if model.isDeskPosture { browserPane } else { SpaceHome() }
                } secondary: {
                    if model.isDeskPosture { DeskControls() } else { browserPane }
                }
                .arrangementViewStyle(.split)
                .overlay { FoldGlow() }
            }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast { ToastView(toast: toast).padding(.top, 8) }
        }
        .overlay {
            if model.searchTarget != nil { SearchOverlay() }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.searchTarget)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.toast) { _, new in new?.canUndo == true }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in model.undoClose() }
        .onHingeChange { _, new in
            withAnimation(.smooth) { model.hinge = new.hinge }
        }
    }

    @ViewBuilder private var browserPane: some View {
        if let tab = model.activeTab {
            TabBrowser(tab: tab)
        } else {
            ContentUnavailableView("No tab open", systemImage: "square.on.square",
                                   description: Text("Pick a tab or search to open one."))
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
        .background(SpaceStyle(model.currentSpace, scheme: .light).gradient)
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
