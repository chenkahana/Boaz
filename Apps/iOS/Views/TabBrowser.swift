import BoazKit
import Network
import SwiftUI
import TipKit
import Translation
import WebKit

/// A tab's web page with its chrome: a bottom bar you swipe to change tabs, which collapses while reading on the
/// tall inner screen.
struct TabBrowser: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.collapsesBar) private var collapsesBar
    @Environment(\.paneIndex) private var pane
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(Preferences.tintWithSiteColorsKey) private var tintWithSiteColors = true
    let tab: SidebarItem
    /// The side the next tab slides in from, and a count of tab turns for the haptic; both outlive this tab's
    /// browser (each tab gets its own), so the pane keeps them.
    @Binding var pageDirection: Edge
    @Binding var bump: Int
    @State private var dragX: CGFloat = 0
    @State private var findVisible = false

    // Pull-to-refresh: derived straight from the page's own rubber-band at the top, so no extra
    // gesture competes with scrolling. `pullPeak` is the deepest pull seen since the finger went
    // down; a reversal (offset recoiling toward zero) means the finger lifted.
    @State private var pullDistance: CGFloat = 0
    @State private var pullPeak: CGFloat = 0
    @State private var pullArmed = false
    @State private var reloading = false
    /// Deep enough that the bounce off a flick to the top doesn't reload the page.
    private let pullThreshold: CGFloat = 120

    @State private var readableLength = 0
    @State private var readerArticle: ReaderArticle?
    @State private var showingDownloads = false
    /// Identifies this browser when claiming the page (see `AppModel.claimPage`). The pane gives every tab a
    /// browser of its own, so the outgoing tab's, still sliding away, never releases the incoming one's page.
    @State private var hostID = UUID()
    /// Whether a status cluster lies across the top of the page (the inner screen held upright).
    @State private var statusAcrossTop = false
    /// Whether the toolbar is the side rail (it matches `ToolRailModifier`'s choice) rather than the bottom bar.
    @State private var hasRail = false
    /// Non-nil while Translate's sheet is up; its presence is the sheet's `isPresented`.
    @State private var translationText: String?
    /// The screen's safe-area insets around the page (without the bottom bar's), which take the page's edge colors.
    @State private var outerInsets = EdgeInsets()
    @State private var scroll = PageScroll()
    @State private var barCollapsed = false

    var body: some View {
        let page = model.page(for: tab)
        Group {
            if model.pageOwners[tab.id] == hostID {
                webView(page)
                    // Inset below the status bar (next line), the page has no top strip to cover: the band would
                    // land on the page itself. The backdrop colors the status bar instead. At the bottom the page
                    // runs on under the home indicator, as in Safari.
                    .overlay { TopEdgeBand(edges: edges, height: statusAcrossTop ? 0 : outerInsets.top) }
                    // WebKit leaves the top safe area to the page while the web view touches the window's top edge,
                    // so the status cluster would sit on the page; one point of clearance makes it inset the page.
                    .padding(.top, statusAcrossTop ? 1 : 0)
                    // The page ends where the rail begins. A web view touching the rail's column runs on under it,
                    // and pages sized in `vw` (which counts that hidden strip) lose their right-hand side; one point
                    // of clearance keeps it out of the column too.
                    .padding(.trailing, hasRail ? 1 : 0)
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
                model.restoreSiteEdges(for: tab)
            }
            .onDisappear { model.releasePage(tab.id, host: hostID) }
            .offset(x: dragX)
            .overlay(alignment: .top) { LoadingGlow(page: page) }
            .overlay(alignment: .top) {
                PullToRefreshIndicator(progress: pullDistance / pullThreshold, armed: pullArmed, reloading: reloading)
                    .padding(.top, 10)
                    .opacity(pullDistance > 2 || reloading ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .overlay {
                // In the page area: beside the rail, above the bottom bar. Half-open, in the focused pane only.
                if model.showsPageSettings, model.activeTabID == tab.id {
                    // A half-open pane is short, and accessibility text sizes need the room: there the menu may
                    // take all of it, and scrolls.
                    BottomPanel(site: edges?.bottom, maxHeight: model.isSplit || typeSize.isAccessibilitySize ? 1 : 0.56,
                                onDismiss: closePageSettings) {
                        PageSettingsPanel(tab: tab, page: page, failedURL: loadFailure?.url,
                                          readableLength: readableLength,
                                          onReader: { Task { readerArticle = await Reader.extract(from: page) } },
                                          onDownloads: { showingDownloads = true },
                                          onFind: { findVisible = true },
                                          onTranslate: { translate(page) })
                    }
                }
            }
            .onGeometryChange(for: Bool.self, of: { $0.safeAreaInsets.trailing >= 44 }) { hasRail = $0 }
            .toolRail(edgeEffect: false) { axis in
                BrowserBar(tab: tab, page: page, axis: axis, collapsed: collapsesBar && barCollapsed,
                           expand: { setBarCollapsed(false) })
                    .highPriorityGesture(paging(axis))
                    .accessibilityAction(named: "Next Tab") { pageTab(by: 1) }
                    .accessibilityAction(named: "Previous Tab") { pageTab(by: -1) }
            }
            .onGeometryChange(for: EdgeInsets.self, of: { $0.safeAreaInsets }) { outerInsets = $0 }
            .background { siteBackdrop }
            .environment(\.chromeTint, edges?.top.color)
            .environment(\.siteEdges, edges)
            .animation(SiteEdges.fade(reduceMotion: reduceMotion), value: edges)
            // Handoff: the focused page shows on the user's Mac (in Boaz there, or its default browser). Only a normal
            // tab's web page; never Incognito, never history (must-have 11).
            .userActivity(NSUserActivityTypeBrowsingWeb, isActive: handoffURL(page) != nil) { activity in
                activity.webpageURL = handoffURL(page)
                activity.title = page.title.isEmpty ? handoffURL(page)?.host() : page.title
                activity.isEligibleForHandoff = true
                activity.isEligibleForSearch = false
                activity.isEligibleForPublicIndexing = false
            }
            .sensoryFeedback(Haptics.pageTurned.feedback, trigger: model.backForwardHaptic)
            .sensoryFeedback(Haptics.refreshArmed.feedback, trigger: pullArmed) { old, new in new && !old }
            .onChange(of: page.url) { model.didChangeURL(tab) }
            .onChange(of: page.title) { model.didChangeTitle(tab) }
            .onChange(of: page.url) { model.restoreSiteEdges(for: tab) }
            .onChange(of: collapsesBar) { barCollapsed = false }
            // The Reader button's probe, once the page has loaded (or shows again, loaded already).
            .task(id: page.isLoading) {
                guard !page.isLoading, page.url != nil else { return }
                readableLength = await Reader.estimatedReadableLength(of: page)
            }
            // Back online: a load that failed for want of a connection loads again (coming back to the app, the model
            // tries; see `AppModel.sceneDidChange`).
            .task {
                for await path in NWPathMonitor() where path.status == .satisfied { model.retryIfPassing(tab.id) }
            }
            .sheet(item: $readerArticle) { article in ReaderView(article: article, tint: Theme.brand) }
            .pageAISheet(tab: tab, page: page)
            .sheet(isPresented: $showingDownloads) { DownloadsView() }
            // Unfolded it's a popover, which can't attach to the whole page (there's no room around it): it hangs
            // from the top instead.
            .translationPresentation(isPresented: Binding(get: { translationText != nil },
                                                            set: { if !$0 { translationText = nil } }),
                                      text: translationText ?? "", attachmentAnchor: .point(.top))
    }

    /// The cluster lies across the top (wider than tall) on the upright inner screen; in landscape it stands in the
    /// side column the rail keeps clear. On iPhones without a side column the status bar is always across the top.
    nonisolated private static func statusAcrossTop(_ proxy: GeometryProxy) -> Bool {
        let insets = proxy.safeAreaInsets
        if insets.top > 0, insets.leading == 0, insets.trailing == 0 { return true }
        return proxy.reservedRegions(kind: .occlusion).contains { $0.frame.maxY <= 1 && $0.frame.width > $0.frame.height }
    }

    /// What the tab's last load failed with, until a load commits (`AppModel.loadFailures`).
    private var loadFailure: LoadFailure? { model.loadFailures[tab.id] }

    private func handoffURL(_ page: WebPage) -> URL? {
        guard model.activeTabID == tab.id, !model.isPrivate(tab), loadFailure == nil,
              let url = page.url ?? tab.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    private var edges: SiteEdges? {
        if model.isPrivate(tab) { return .incognito }
        return tintWithSiteColors ? model.siteEdges[tab.id] : nil
    }

    /// The page's edge colors behind it, seen where the page doesn't reach (beside it while swiping tabs).
    private var siteBackdrop: some View {
        ZStack {
            if let edges {
                VStack(spacing: 0) { Rectangle().fill(edges.top.color); Rectangle().fill(edges.bottom.color) }
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
    }

    private func webView(_ page: WebPage) -> some View {
        WebView(page)
            .webViewBackForwardNavigationGestures(.enabled)
            // A page that fits the width doesn't rubber-band sideways.
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .webViewOnScrollGeometryChange(for: PageScroll.Sample.self, of: PageScroll.Sample.init) { old, new in
                // Never `page` in here: WebKit keeps this action as long as the page's web view, so capturing the page
                // would keep a page closed to save memory alive.
                handlePullGeometry(old: old.offset, new: new.offset)
                model.pageDidScroll(tab)
                scroll.note(new)
                // Followed in every posture (this action can outlive an environment change); shown only where
                // the bar collapses.
                setBarCollapsed(scroll.barCollapses(new, collapsed: barCollapsed))
            }
            .findNavigator(isPresented: $findVisible)
            .overlay { PasswordSuggestions(tabID: tab.id, page: page) }
            .overlay(alignment: .top) { SavePasswordPrompt(tabID: tab.id) }
            .animation(.smooth(duration: 0.25), value: PasswordAutofill.shared.offer)
            .modifier(RelayoutCover(page: page, scroll: scroll, snapshot: { [tab] in model.snapshots[tab.id] },
                                    background: edges?.page.color ?? Color(.systemBackground),
                                    shownWidth: model.shownWidth(of: tab.id),
                                    onWidth: { [tab] in model.pageShows(tab.id, atWidth: $0) }))
            // A page loaded again shows its top until it is back at the reader's place: its preview covers it.
            .overlay {
                if model.restoringTabs.contains(tab.id), let preview = model.snapshots[tab.id] {
                    PreviewCover(image: preview, background: edges?.page.color ?? Color(.systemBackground))
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.restoringTabs.contains(tab.id))
            .onDisappear { [tab, hostID] in model.releasePage(tab.id, host: hostID) }
            .overlay {
                // WebKit draws no error page of its own, so a failed load would otherwise stay blank.
                if let loadFailure {
                    ContentUnavailableView {
                        Label(loadFailure.kind.title, systemImage: loadFailure.kind.symbol)
                    } description: {
                        Text(loadFailure.message)
                    } actions: {
                        Button("Try Again") { model.retry(tab.id) }
                            .buttonStyle(.glassProminent)
                    }
                    .tint(Theme.brand)
                    .background(Color(.systemBackground).ignoresSafeArea())
                } else if model.failedTabs.contains(tab.id), page.isLoading {
                    ContentUnavailableView {
                        Label(PageFailureKind.unreachable.title, systemImage: PageFailureKind.unreachable.symbol)
                    } description: {
                        Text("Trying again…")
                    } actions: {
                        ProgressView()
                    }
                    .background(Color(.systemBackground).ignoresSafeArea())
                }
            }
    }

    private func setBarCollapsed(_ collapsed: Bool) {
        guard collapsed != barCollapsed else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3)) { barCollapsed = collapsed }
    }

    /// Steps to a neighbouring tab, for VoiceOver's Next Tab and Previous Tab actions.
    private func pageTab(by offset: Int) {
        model.focusPane(pane)
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
                model.focusPane(pane)
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

    private func handlePullGeometry(old: CGFloat, new: CGFloat) {
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
                if wasArmed { reload(model.page(for: tab)) }
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
                for try await event in page.reload(tabURL: loadFailure?.url ?? tab.url) where event == .finished {
                    break
                }
            } catch {
                // Reload failed; still clear the indicator below.
            }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { reloading = false }
        }
    }

    private func closePageSettings() {
        withAnimation(BottomPanelStyle.motion) { model.showsPageSettings = false }
    }

    private func translate(_ page: WebPage) {
        Task {
            guard let text = await VisibleText.extract(from: page) else {
                model.showToast("Nothing to translate")
                return
            }
            translationText = text
        }
    }
}

private struct BrowserBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.listsTabsElsewhere) private var listsTabsElsewhere
    @Environment(\.siteEdges) private var edges
    @Environment(\.paneIndex) private var pane
    @Environment(\.collapsesBar) private var collapsesBar
    let tab: SidebarItem
    let page: WebPage
    let axis: Axis
    /// Collapsed to a slim strip with the page's title while reading; tapping it brings the bar back.
    let collapsed: Bool
    let expand: () -> Void

    var body: some View {
        bar.onChange(of: tabCount, initial: true) { SwipeTabsTip.openTabs = tabCount }
            .onChange(of: page.isLoading, initial: true) { SwipeTabsTip.pageLoaded = !page.isLoading }
    }

    /// On the rail, top to bottom: the tabs, New Tab, then the page settings. The bottom bar has a layout of its own.
    @ViewBuilder private var bar: some View {
        if axis == .vertical {
            RailColumn {
                tabsButton
                // Like the empty page's search button: a private tab's says so.
                RailButton(symbol: model.isPrivate(tab) ? "eyeglasses" : "plus", label: "New Tab",
                           isSelected: searching, action: toggleSearch)
            } bottom: {
                RailButton(symbol: "ellipsis", label: "Page Settings", isSelected: showsPageSettings,
                           action: togglePageSettings)
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .bouncy(duration: 0.35), value: tabCount)
            .popoverTip(SwipeTabsTip(), arrowEdge: .trailing)
        } else {
            bottomBar
        }
    }

    /// The stack of the phone's tabs (opens the carousel); none beside the tab strip, which lists them.
    @ViewBuilder private var tabsButton: some View {
        if !listsTabsElsewhere {
            if axis == .vertical {
                TabStack(cardSize: CGSize(width: 26, height: 36), minimumSide: RailMetrics.control)
            } else {
                TabStack(cardSize: collapsesBar ? CGSize(width: 30, height: 39) : CGSize(width: 34, height: 46))
            }
        }
    }

    /// The phone's own toolbar: the tab fan at the leading end, New Tab as a glass pill in the middle, the page menu
    /// in a glass circle at the trailing end, across the bottom on a frosted strip in the page's bottom color.
    /// Collapsed, the strip shrinks to the page's title; it keeps its room, so the page under it never moves.
    private var bottomBar: some View {
        HStack(spacing: 0) {
            tabsButton.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: toggleSearch) {
                HStack(spacing: 8) {
                    if model.isPrivate(tab) {
                        Text("Private").font(.headline).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    Image(systemName: "plus")
                }
                    .font(.title3.weight(.semibold))
                    .frame(width: 116, height: collapsesBar ? 44 : 50)
                    .railSelection(searching)
                    .contentShape(.capsule)
            }
            .buttonStyle(PressableStyle())
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityLabel("New Tab")
            .accessibilityShowsLargeContentViewer { Label("New Tab", systemImage: "plus") }
            .accessibilityAddTraits(searching ? .isSelected : [])
            RailButton(symbol: "ellipsis", label: "Page Settings", isSelected: showsPageSettings,
                       size: collapsesBar ? 44 : RailMetrics.barControl,
                       action: togglePageSettings)
                .glassEffect(.regular.interactive(), in: .circle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, collapsesBar ? 6 : 8)
        .padding(.bottom, collapsesBar ? 6 : 4)
        .opacity(collapsed ? 0 : 1)
        .scaleEffect(collapsed && !reduceMotion ? 0.8 : 1, anchor: .bottom)
        .allowsHitTesting(!collapsed)
        .popoverTip(SwipeTabsTip(), arrowEdge: .bottom)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            Group {
                if collapsesBar, let site = edges?.bottom {
                    Rectangle().fill(site.color)
                } else {
                    Rectangle().fill(.bar)
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .frame(height: collapsed ? 14 : nil)
            .overlay(alignment: .top) { Divider() }
        }
        .overlay(alignment: .bottom) {
            Button(action: expand) {
                Text(collapsedTitle).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .opacity(collapsed ? 1 : 0)
            .allowsHitTesting(collapsed)
            .accessibilityHidden(!collapsed)
            .accessibilityHint("Shows the toolbar")
        }
        .chromeScheme(edges?.bottom)
    }

    private var collapsedTitle: String {
        page.title.isEmpty ? page.url?.host() ?? tab.title ?? "" : page.title
    }

    /// Half-open, only the focused pane's controls show its panels as open.
    private var searching: Bool { model.searchTarget != nil && model.activeTabID == tab.id }
    private var showsPageSettings: Bool { model.showsPageSettings && model.activeTabID == tab.id }

    /// New Tab opens the search panel; pressed again, it puts it away. One panel at a time.
    private func toggleSearch() {
        model.focusPane(pane)
        withAnimation(BottomPanelStyle.motion) {
            model.showsPageSettings = false
            if model.searchTarget != nil { model.searchTarget = nil } else { model.beginSearch(.newTab) }
        }
    }

    private func togglePageSettings() {
        model.focusPane(pane)
        withAnimation(BottomPanelStyle.motion) {
            model.searchTarget = nil
            model.showsPageSettings.toggle()
        }
    }

    private var tabCount: Int { model.phoneTabs.count }
}

/// The page's top color in the screen's top safe area, so the page seems to run under the status bar, which picks
/// its own contrast from what's under it.
private struct TopEdgeBand: View {
    let edges: SiteEdges?
    let height: CGFloat

    var body: some View {
        ZStack {
            if let edges {
                Rectangle().fill(edges.top.color).frame(height: height)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
