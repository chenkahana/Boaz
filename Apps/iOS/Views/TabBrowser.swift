import FolioKit
import SwiftUI
import WebKit

/// A tab's web page with Arc-style chrome: a bottom bar you swipe to change tabs, which shrinks while reading.
struct TabBrowser: View {
    @Environment(AppModel.self) private var model
    let tab: SidebarItem
    @State private var dragX: CGFloat = 0
    @State private var collapsed = false
    @State private var bump = 0

    var body: some View {
        let page = model.page(for: tab)
        WebView(page)
            .webViewBackForwardNavigationGestures(.enabled)
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) { old, new in
                let shouldCollapse = new > 80 && new > old + 4
                let shouldExpand = new < old - 8 || new < 40
                if shouldCollapse != collapsed && (shouldCollapse || shouldExpand) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { collapsed = shouldCollapse }
                }
            }
            .offset(x: dragX)
            .overlay(alignment: .top) { LoadingGlow(page: page) }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                BrowserBar(tab: tab, page: page, collapsed: $collapsed)
                    .highPriorityGesture(paging)
            }
            .sensoryFeedback(.selection, trigger: bump)
            .onChange(of: page.url) { model.didNavigate(tab, url: page.url, title: page.title) }
            .onChange(of: page.title) { model.didNavigate(tab, url: page.url, title: page.title) }
            .id(tab.id)
            .transition(.asymmetric(insertion: .move(edge: dragX < 0 ? .trailing : .leading),
                                    removal: .opacity))
    }

    /// Horizontal swipe on the bar pages through neighbouring tabs; rubber-bands at the ends.
    private var paging: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragX = value.translation.width * 0.6
            }
            .onEnded { value in
                let offset = value.translation.width < -70 ? 1 : value.translation.width > 70 ? -1 : 0
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    if offset != 0, model.pageTab(by: offset) { bump += 1 }
                    dragX = 0
                }
            }
    }
}

private struct BrowserBar: View {
    @Environment(AppModel.self) private var model
    let tab: SidebarItem
    let page: WebPage
    @Binding var collapsed: Bool

    var body: some View {
        Group {
            if collapsed {
                Button { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { collapsed = false } } label: {
                    Text(host).font(.caption.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    BarButton(symbol: "square.grid.2x2") { model.goHome() }
                    Button { model.beginSearch(.currentTab) } label: {
                        HStack(spacing: 6) {
                            if page.url?.scheme == "https" { Image(systemName: "lock.fill").font(.caption2) }
                            Text(host).lineLimit(1)
                        }
                        .font(.callout.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    BarButton(symbol: page.isLoading ? "xmark" : "arrow.clockwise") {
                        if page.isLoading { page.stopLoading() } else { _ = page.reload() }
                    }
                    Menu {
                        Button(model.isPinned(tab) ? "Unpin" : "Pin", systemImage: "pin") { model.togglePin(tab) }
                        if let url = page.url { ShareLink(item: url) }
                        Button("Close Tab", systemImage: "xmark", role: .destructive) { model.close(tab) }
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, collapsed ? 0 : 4)
        .frame(maxWidth: .infinity)
    }

    private var host: String { page.url?.host() ?? tab.url?.host() ?? "New Tab" }
}

private struct BarButton: View {
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
    }
}

/// Thin gradient progress line along the top while a page loads.
private struct LoadingGlow: View {
    let page: WebPage

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Theme.glow)
                .frame(width: proxy.size.width * page.estimatedProgress, height: 3)
                .shadow(color: Theme.violet.opacity(0.8), radius: 6)
                .opacity(page.isLoading ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: page.estimatedProgress)
                .animation(.easeOut(duration: 0.4), value: page.isLoading)
        }
        .frame(height: 3)
        .allowsHitTesting(false)
    }
}
