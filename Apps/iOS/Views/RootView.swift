import SwiftUI

/// Layout comes from size class and hinge *status*; the raw angle only drives effects (Apple's iPhone Duo guidance).
struct RootView: View {
    @Environment(BrowserModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .compact {
                CompactLayout()
            } else {
                ArrangementView {
                    if model.isDeskPosture { WebPane() } else { AnswerPane() }
                } secondary: {
                    if model.isDeskPosture { DeskControls() } else { WebPane() }
                }
                .arrangementViewStyle(.split)
                .overlay { FoldGlow() }
            }
        }
        .background(Theme.background)
        .onHingeChange { _, new in
            withAnimation(.smooth) { model.hinge = new.hinge }
        }
    }
}

/// Folded (cover screen): one column; citations push the source page.
private struct CompactLayout: View {
    @Environment(BrowserModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            AnswerPane()
                .navigationDestination(isPresented: $model.showsWebInCompact) { WebPane() }
        }
    }
}

/// Soft glow along the fold. Uses the division reserved region for placement and hinge angle for intensity.
private struct FoldGlow: View {
    @Environment(BrowserModel.self) private var model

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
