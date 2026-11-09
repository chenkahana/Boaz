import FolioKit
import SwiftUI
import TipKit
import WebKit

/// A tab's web page with Arc-style chrome: a bottom bar you swipe to change tabs, which shrinks while reading.
struct TabBrowser: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Preferences.tintWithSiteColorsKey) private var tintWithSiteColors = true
    let tab: SidebarItem
    @State private var dragX: CGFloat = 0
    /// The side the next tab slides in from; set while the finger is still down, so the outgoing page
    /// has already rendered with it by the time the tab changes.
    @State private var pageDirection: Edge = .trailing
    @State private var bump = 0
    @State private var loadFailure: LoadFailure?
    @State private var findVisible = false

    // Pull-to-refresh: derived straight from the page's own rubber-band at the top, so no extra
    // gesture competes with scrolling. `pullPeak` is the deepest pull seen since the finger went
    // down; a reversal (offset recoiling toward zero) means the finger lifted.
    @State private var pullDistance: CGFloat = 0
    @State private var pullPeak: CGFloat = 0
    @State private var pullArmed = false
    @State private var reloading = false
    private let pullThreshold: CGFloat = 70

    @State private var readableLength = 0
    @State private var readerArticle: ReaderArticle?
    @State private var showingDownloads = false
    /// Identifies this browser when claiming the page (see `AppModel.claimPage`).
    @State private var hostID = UUID()
    /// Whether a status cluster lies across the top of the page (the inner screen held upright).
    @State private var statusAcrossTop = false

    var body: some View {
        let page = model.page(for: tab)
        Group {
            if model.pageOwners[tab.id] == hostID {
                webView(page)
                    // WebKit leaves the top safe area to the page while the web view touches the window's top edge,
                    // so the status cluster would sit on the page; one point of clearance makes it inset the page.
                    .padding(.top, statusAcrossTop ? 1 : 0)
            } else {
                // Shown for the moment another layout's browser still holds this page.
                Color(.systemBackground)
                    .overlay(alignment: .top) {
                        if let snapshot = model.snapshots[tab.id] {
                            Image(uiImage: snapshot).resizable().scaledToFit()
                        }
                    }
                    .ignoresSafeArea()
            }
        }
            .onGeometryChange(for: Bool.self, of: Self.statusAcrossTop) { statusAcrossTop = $0 }
            .onAppear {
                model.claimPage(tab.id, host: hostID)
                model.updateSiteColor(for: tab)
            }
            .onDisappear { model.releasePage(tab.id, host: hostID) }
            .onChange(of: tab.id) { old, new in
                model.releasePage(old, host: hostID)
                model.claimPage(new, host: hostID)
            }
            .offset(x: dragX)
            .overlay(alignment: .top) { LoadingGlow(page: page) }
            .overlay(alignment: .top) {
                PullToRefreshIndicator(progress: pullDistance / pullThreshold, armed: pullArmed, reloading: reloading)
                    .padding(.top, 10)
                    .opacity(pullDistance > 2 || reloading ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .toolRail { axis in
                BrowserBar(tab: tab, page: page, axis: axis, readableLength: readableLength,
                           onReader: { Task { readerArticle = await Reader.extract(from: page) } },
                           onDownloads: { showingDownloads = true },
                           onFind: { findVisible = true })
                    .highPriorityGesture(paging(axis))
                    .accessibilityAction(named: "Next Tab") { pageTab(by: 1) }
                    .accessibilityAction(named: "Previous Tab") { pageTab(by: -1) }
            }
            .background { siteBackdrop }
            .environment(\.chromeTint, site?.color)
            .animation(SiteColor.fade(reduceMotion: reduceMotion), value: site)
            .sensoryFeedback(.selection, trigger: bump)
            .sensoryFeedback(.selection, trigger: model.backForwardHaptic)
            .sensoryFeedback(.impact(weight: .light), trigger: pullArmed) { old, new in new && !old }
            .onChange(of: page.url) { model.didNavigate(tab, url: page.url, title: page.title) }
            .onChange(of: page.title) { model.didNavigate(tab, url: page.url, title: page.title) }
            .onChange(of: page.url) { model.updateSiteColor(for: tab) }
            .task(id: tab.id) { await trackNavigations(of: page) }
            .sheet(item: $readerArticle) { article in ReaderView(article: article, tint: Theme.brand) }
            .pageAISheet(tab: tab, page: page)
            .sheet(isPresented: $showingDownloads) { DownloadsView() }
            .id(tab.id)
            .transition(pageTransition)
    }

    private var pageTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(insertion: .move(edge: pageDirection),
                           removal: .move(edge: pageDirection == .trailing ? .leading : .trailing))
    }

    /// The cluster lies across the top (wider than tall) on the upright inner screen; in landscape it stands in the
    /// side column the rail keeps clear. On iPhones without a side column the status bar is always across the top.
    nonisolated private static func statusAcrossTop(_ proxy: GeometryProxy) -> Bool {
        let insets = proxy.safeAreaInsets
        if insets.top > 0, insets.leading == 0, insets.trailing == 0 { return true }
        return proxy.reservedRegions(kind: .occlusion).contains { $0.frame.maxY <= 1 && $0.frame.width > $0.frame.height }
    }

    private var site: SiteColor? { tintWithSiteColors ? model.siteColors[tab.id] : nil }

    /// The site's color in the status column and behind the top of the page.
    private var siteBackdrop: some View {
        ZStack {
            if let site { site.color.transition(.opacity) }
        }
        .ignoresSafeArea()
    }

    private func webView(_ page: WebPage) -> some View {
        WebView(page)
            .webViewBackForwardNavigationGestures(.enabled)
            .webViewCollapsesToolRail(expandingOn: page.url) { old, new in
                handlePullGeometry(old: old, new: new, page: page)
            }
            .findNavigator(isPresented: $findVisible)
            .onDisappear { [tab, hostID] in model.releasePage(tab.id, host: hostID) }
            .overlay {
                // WebKit draws no error page of its own, so a failed load would otherwise stay blank.
                if let loadFailure {
                    ContentUnavailableView {
                        Label("Can't Open This Page", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(loadFailure.message)
                    } actions: {
                        Button("Try Again") { retry(loadFailure, on: page) }
                            .buttonStyle(.glassProminent)
                    }
                    .tint(SpaceStyle(model.currentSpace, scheme: scheme).tint)
                    .background(Color(.systemBackground).ignoresSafeArea())
                }
            }
    }

    private func retry(_ failure: LoadFailure, on page: WebPage) {
        loadFailure = nil
        // A failed link never became the current item, so reloading would reload the page before it.
        if let url = failure.url { _ = page.load(URLRequest(url: url)) } else { _ = page.reload() }
    }

    /// Steps to a neighbouring tab, for VoiceOver's Next Tab and Previous Tab actions.
    private func pageTab(by offset: Int) {
        pageDirection = offset > 0 ? .trailing : .leading
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
            if model.pageTab(by: offset) { bump += 1 }
        }
    }

    /// Swiping along the toolbar pages through neighbouring tabs: sideways on the bottom bar, up and down on
    /// the rail (up = next). The page follows the finger sideways and rubber-bands at the ends.
    private func paging(_ axis: Axis) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                let along = axis == .vertical ? -value.translation.height : value.translation.width
                let across = axis == .vertical ? value.translation.width : value.translation.height
                guard abs(along) > abs(across) else { return }
                dragX = along * 0.6
                pageDirection = along < 0 ? .trailing : .leading
            }
            .onEnded { value in
                let along = axis == .vertical ? -value.translation.height : value.translation.width
                let offset = along < -70 ? 1 : along > 70 ? -1 : 0
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    if offset != 0, model.pageTab(by: offset) {
                        bump += 1
                        SwipeTabsTip().invalidate(reason: .actionPerformed)
                    }
                    dragX = 0
                }
            }
    }

    private func handlePullGeometry(old: CGFloat, new: CGFloat, page: WebPage) {
        guard !reloading else { return }
        if new < 0 {
            let distance = -new
            if distance >= pullPeak {
                pullPeak = distance
                pullDistance = min(distance, pullThreshold * 1.4)
                pullArmed = distance > pullThreshold
            } else if pullPeak > 0 && distance < pullPeak - 4 {
                // Offset is recoiling toward zero: the finger lifted.
                let wasArmed = pullArmed
                pullPeak = 0
                pullArmed = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { pullDistance = 0 }
                if wasArmed { reload(page) }
            }
        } else if old < 0 {
            pullPeak = 0
            pullArmed = false
            pullDistance = 0
        }
    }

    private func reload(_ page: WebPage) {
        reloading = true
        Task {
            do {
                for try await event in page.reload() where event == .finished { break }
            } catch {
                // Reload failed; still clear the indicator below.
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { reloading = false }
        }
    }

    /// The single subscriber to this page's `navigations` (the async sequence supports only one
    /// consumer): on every finished load it tells the model to snapshot the tab and refreshes the
    /// cheap text-length probe used to enable/disable the Reader button. A failed load is shown.
    private func trackNavigations(of page: WebPage) async {
        readableLength = 0
        while !Task.isCancelled {
            do {
                for try await event in page.navigations {
                    switch event {
                    case .startedProvisionalNavigation, .committed:
                        loadFailure = nil
                    case .finished:
                        model.pageDidFinishLoading(tab)
                        readableLength = await Reader.estimatedReadableLength(of: page)
                    default:
                        break
                    }
                }
                return // The sequence finished: the page is gone.
            } catch WebPage.NavigationError.pageClosed {
                return
            } catch {
                // A failed navigation ends the sequence; go round again so later loads are still tracked.
                if let failure = LoadFailure(error) { loadFailure = failure }
            }
        }
    }
}

/// Why a page couldn't load, and what Try Again should load.
private struct LoadFailure {
    let message: String
    let url: URL?

    /// Nil for navigations that were cut short rather than failed: superseded by another load, or turned into a download.
    init?(_ error: any Error) {
        let underlying: any Error
        switch error as? WebPage.NavigationError {
        case .failedProvisionalNavigation(let inner): underlying = inner
        case .webContentProcessTerminated:
            message = "The page stopped responding."
            url = nil
            return
        case .invalidURL:
            message = "The address isn't valid."
            url = nil
            return
        case .pageClosed: return nil
        default: underlying = error
        }
        let nsError = underlying as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return nil }
        // WebKitErrorFrameLoadInterruptedByPolicyChange: the response became a download.
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return nil }
        message = nsError.localizedDescription
        url = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL
    }
}

private struct BrowserBar: View {
    @Environment(AppModel.self) private var model
    @Environment(ToolRailState.self) private var rail
    @Environment(\.homeControlsElsewhere) private var homeControlsElsewhere
    @Environment(\.chromeTint) private var tint
    @Environment(\.sidebar) private var sidebar
    let tab: SidebarItem
    let page: WebPage
    let axis: Axis
    let readableLength: Int
    let onReader: () -> Void
    let onDownloads: () -> Void
    let onFind: () -> Void
    /// The rail teaches both of its swipes, one at a time.
    @State private var railTips = TipGroup(.firstAvailable) {
        SwipeTabsTip()
        TuckRailTip()
    }

    var body: some View {
        bar.onChange(of: tabCount, initial: true) { SwipeTabsTip.openTabs = tabCount }
    }

    @ViewBuilder private var bar: some View {
        if axis == .vertical {
            RailColumn {
                siteButton(size: 40).padding(.vertical, 3)
                if !backList.isEmpty {
                    backButton.transition(.scale(scale: 0.4).combined(with: .opacity))
                }
                RailButton(symbol: page.isLoading ? "xmark" : "arrow.clockwise",
                           label: page.isLoading ? "Stop" : "Reload") { reloadOrStop() }
            } bottom: {
                RailButton(symbol: "plus", label: "New Tab") { model.beginSearch(.newTab) }
                if let sidebar {
                    SidebarRailButton(sidebar: sidebar)
                } else if !homeControlsElsewhere {
                    Button { model.goHome() } label: {
                        RailGlyph(symbol: "square.grid.2x2").overlay(alignment: .topTrailing) { RailBadge(count: tabCount) }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Tabs")
                    .accessibilityValue("\(tabCount) open")
                } else {
                    forwardButton
                }
                menu
            } nub: {
                SiteTile(url: page.url ?? tab.url, page: page, size: 30)
            }
            .animation(.bouncy(duration: 0.35), value: backList.isEmpty)
            .animation(.bouncy(duration: 0.35), value: tabCount)
            .popoverTip(railTips.currentTip, arrowEdge: .trailing)
        } else {
            bottomBar
        }
    }

    /// Book and laptop poses already list the tabs beside or below the page, so Forward takes the Tabs button's place.
    private var showsForwardButton: Bool { sidebar == nil && homeControlsElsewhere }

    private var forwardButton: some View {
        Button { if let next = forwardList.first { _ = page.load(next) } } label: {
            if axis == .vertical { RailGlyph(symbol: "chevron.forward") } else { RailIcon(symbol: "chevron.forward") }
        }
        .buttonStyle(PressableStyle())
        .disabled(forwardList.isEmpty)
        .accessibilityLabel("Forward")
    }

    /// The site's tile with a live loading ring: tap to edit the address, hold for link actions.
    private func siteButton(size: CGFloat) -> some View {
        Button { model.beginSearch(.currentTab) } label: {
            SiteTile(url: page.url ?? tab.url, page: page, size: size)
                .overlay(alignment: .bottomTrailing) {
                    if page.url?.scheme == "https" {
                        Image(systemName: "lock.fill").font(.caption2.weight(.bold)).imageScale(.small)
                            .padding(3.5).background(.regularMaterial, in: .circle).offset(x: 5, y: 5)
                    }
                }
        }
        .buttonStyle(PressableStyle())
        .contextMenu {
            if let url = page.url {
                Button("Copy Link", systemImage: "link") {
                    UIPasteboard.general.url = url
                    model.showToast("Link copied")
                }
                ShareLink(item: url)
            }
            Button("Edit Address", systemImage: "pencil") { model.beginSearch(.currentTab) }
        }
        .accessibilityLabel("Address")
        .accessibilityValue(host)
        .accessibilityHint("Edit address or search")
    }

    /// Tap goes back one page; hold for the whole back history.
    private var backButton: some View {
        Menu {
            ForEach(backList.reversed()) { item in
                Button(item.title?.isEmpty == false ? item.title! : item.url.host() ?? item.url.absoluteString) {
                    _ = page.load(item)
                }
            }
        } label: {
            if axis == .vertical { RailGlyph(symbol: "chevron.backward") } else { RailIcon(symbol: "chevron.backward") }
        } primaryAction: {
            if let previous = backList.last { _ = page.load(previous) }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Back")
    }

    private var bottomBar: some View {
        Group {
            if rail.isCollapsed {
                Button { rail.expand() } label: {
                    Text(host).font(.caption.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .glassEffect(.regular.tint(tint?.opacity(0.45)), in: .capsule)
                        // The capsule stays small; the target is a full 44pt.
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show Toolbar")
                .accessibilityValue(host)
            } else {
                HStack(spacing: 10) {
                    if let sidebar {
                        BarButton(symbol: "sidebar.left", action: sidebar.toggle)
                            .accessibilityLabel(sidebar.isCollapsed ? "Show Sidebar" : "Hide Sidebar")
                    } else if !homeControlsElsewhere {
                        BarButton(symbol: "square.grid.2x2") { model.goHome() }
                            .accessibilityLabel("Tabs")
                            .accessibilityValue("\(tabCount) open")
                    }
                    if !backList.isEmpty {
                        backButton.transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                    if showsForwardButton { forwardButton }
                    addressPill
                    menu
                }
                .padding(.horizontal, 12)
                .animation(.bouncy(duration: 0.35), value: backList.isEmpty)
                .popoverTip(SwipeTabsTip(), arrowEdge: .bottom)
            }
        }
        .padding(.top, rail.isCollapsed ? 0 : 6)
        .padding(.bottom, rail.isCollapsed ? 0 : 4)
        .frame(maxWidth: .infinity)
    }

    /// The address (tap to edit) with Reload at its trailing end, as Safari does, leaving room for Back in the bar.
    private var addressPill: some View {
        HStack(spacing: 0) {
            Button { model.beginSearch(.currentTab) } label: {
                HStack(spacing: 6) {
                    if page.url?.scheme == "https" { Image(systemName: "lock.fill").font(.caption2) }
                    Text(host).lineLimit(1)
                }
                .font(.callout.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                // Balances the reload glyph so the host stays centred in the pill.
                .padding(.leading, 44)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Address")
            .accessibilityValue(host)
            .accessibilityHint("Edit address or search")
            Button(action: reloadOrStop) {
                Image(systemName: page.isLoading ? "xmark" : "arrow.clockwise")
                    .font(.callout.weight(.medium))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(page.isLoading ? "Stop" : "Reload")
        }
        .glassEffect(.chrome(tint), in: .capsule)
    }

    private var menu: some View {
        Menu {
            Button(model.isPinned(tab) ? "Unpin" : "Pin", systemImage: "pin") { model.togglePin(tab) }
            Button("Forward", systemImage: "chevron.forward") { if let next = forwardList.first { _ = page.load(next) } }
                .disabled(forwardList.isEmpty)
            Button("Find on Page", systemImage: "text.magnifyingglass", action: onFind)
            Button("Reader", systemImage: "doc.text.magnifyingglass", action: onReader)
                .disabled(readableLength < Reader.minimumCharacters)
            PageAIMenuItems(tab: tab)
            Button("Downloads", systemImage: "arrow.down.circle", action: onDownloads)
            if let url = page.url { ShareLink(item: url) }
            if axis == .vertical {
                Button("Hide Toolbar", systemImage: "sidebar.trailing") { rail.tucked = true }
            }
            Button("Reopen Closed Tab", systemImage: "arrow.uturn.backward") { model.undoClose() }
                .disabled(!model.canReopenClosedTab)
            Button("Archive Tab", systemImage: "archivebox") { model.close(tab) }
            if homeControlsElsewhere {
                Divider()
                HomeMenuItems()
            }
        } label: {
            if axis == .vertical { RailGlyph(symbol: "ellipsis") } else { RailIcon(symbol: "ellipsis") }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("More")
    }

    private func reloadOrStop() {
        if page.isLoading { page.stopLoading() } else { _ = page.reload() }
    }

    private var backList: [WebPage.BackForwardList.Item] { page.backForwardList.backList }
    private var forwardList: [WebPage.BackForwardList.Item] { page.backForwardList.forwardList }

    private var tabCount: Int {
        guard let space = model.currentSpace else { return 0 }
        return model.todayTabs(in: space).count
    }

    private var host: String { page.url?.host() ?? tab.url?.host() ?? "New Tab" }
}

/// Site monogram ringed by the page's loading progress.
private struct SiteTile: View {
    let url: URL?
    let page: WebPage
    let size: CGFloat

    var body: some View {
        Monogram(url: url, tint: Theme.brand, size: size)
            .overlay {
                RoundedRectangle(cornerRadius: (size + 7) * 0.3)
                    .trim(from: 0, to: page.isLoading ? max(page.estimatedProgress, 0.06) : 1)
                    .stroke(Theme.glow, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .padding(-3.5)
                    .opacity(page.isLoading ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: page.estimatedProgress)
                    .animation(.easeOut(duration: 0.4), value: page.isLoading)
            }
            .contentTransition(.interpolate)
            .animation(.bouncy, value: url?.host())
    }
}

private struct BarButton: View {
    @Environment(\.chromeTint) private var tint
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 44, height: 44).glassEffect(.chrome(tint), in: .circle)
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
