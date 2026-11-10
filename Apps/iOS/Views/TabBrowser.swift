import BoazKit
import SwiftUI
import TipKit
import Translation
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
    /// Deep enough that the bounce off a flick to the top doesn't reload the page.
    private let pullThreshold: CGFloat = 120

    @State private var readableLength = 0
    @State private var readerArticle: ReaderArticle?
    @State private var showingDownloads = false
    /// Identifies this browser when claiming the page (see `AppModel.claimPage`).
    @State private var hostID = UUID()
    /// Whether a status cluster lies across the top of the page (the inner screen held upright).
    @State private var statusAcrossTop = false
    /// Whether the toolbar is the side rail (it matches `ToolRailModifier`'s choice) rather than the bottom bar.
    @State private var hasRail = false
    /// Non-nil while Translate's sheet is up; its presence is the sheet's `isPresented`.
    @State private var translationText: String?
    /// The screen's safe-area insets around the page (without the bottom bar's), which take the page's edge colors.
    @State private var outerInsets = EdgeInsets()

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
            .overlay {
                // In the page area: beside the rail, above the bottom bar.
                if model.showsPageSettings {
                    BottomPanel(site: edges?.bottom, maxHeight: 0.56, onDismiss: closePageSettings) {
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
                BrowserBar(tab: tab, page: page, axis: axis)
                    .highPriorityGesture(paging(axis))
                    .accessibilityAction(named: "Next Tab") { pageTab(by: 1) }
                    .accessibilityAction(named: "Previous Tab") { pageTab(by: -1) }
            }
            .onGeometryChange(for: EdgeInsets.self, of: { $0.safeAreaInsets }) { outerInsets = $0 }
            .background { siteBackdrop }
            .environment(\.chromeTint, edges?.top.color)
            .environment(\.siteEdges, edges)
            .animation(SiteEdges.fade(reduceMotion: reduceMotion), value: edges)
            .sensoryFeedback(.selection, trigger: bump)
            .sensoryFeedback(.selection, trigger: model.backForwardHaptic)
            .sensoryFeedback(.impact(weight: .light), trigger: pullArmed) { old, new in new && !old }
            .onChange(of: page.url) { model.didChangeURL(tab) }
            .onChange(of: page.title) { model.didChangeTitle(tab) }
            .onChange(of: page.url) { model.restoreSiteEdges(for: tab) }
            .task(id: tab.id) { await trackNavigations(of: page) }
            .sheet(item: $readerArticle) { article in ReaderView(article: article, tint: Theme.brand) }
            .pageAISheet(tab: tab, page: page)
            .sheet(isPresented: $showingDownloads) { DownloadsView() }
            .translationPresentation(isPresented: Binding(get: { translationText != nil },
                                                            set: { if !$0 { translationText = nil } }),
                                      text: translationText ?? "")
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

    private var edges: SiteEdges? { tintWithSiteColors ? model.siteEdges[tab.id] : nil }

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
            .webViewOnScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y + $0.contentInsets.top }) {
                handlePullGeometry(old: $0, new: $1, page: page)
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

    /// Text Size is CSS on the document, so each new document needs it again.
    private func applyTextSize(to page: WebPage) {
        let isPrivate = model.isPrivate(tab)
        if PageZoom.level(for: page.url, isPrivate: isPrivate) != 1 { PageZoom.apply(to: page, isPrivate: isPrivate) }
    }

    /// The single subscriber to this page's `navigations` (the async sequence supports only one
    /// consumer): on every finished load it tells the model to snapshot the tab and refreshes the
    /// cheap text-length probe used to enable/disable the Reader button. A failed load is shown.
    private func trackNavigations(of page: WebPage) async {
        readableLength = 0
        var requested: URL?
        var committed: URL?
        while !Task.isCancelled {
            do {
                for try await event in page.navigations {
                    switch event {
                    case .startedProvisionalNavigation:
                        loadFailure = nil
                        requested = page.url
                    case .receivedServerRedirect:
                        // A hop to the same address, or an event read after the redirect, is the page shown now.
                        // A hop from the page already shown (a form posting back to itself) recorded no visit of
                        // its own, so its earlier visit stays.
                        if let hop = requested, hop != page.url, hop != committed {
                            model.didRedirect(tab, from: hop)
                        }
                        requested = page.url
                    case .committed:
                        loadFailure = LoadFailure(blocked: requested, committed: page.url)
                        requested = nil
                        committed = page.url
                        applyTextSize(to: page)
                    case .finished:
                        applyTextSize(to: page)
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
                // Never spin if resubscribing fails straight away.
                try? await Task.sleep(for: .milliseconds(50))
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

    /// WebKit refuses some ports (1, 9, 25 and so on) without any navigation error: it commits about:blank instead.
    init?(blocked requested: URL?, committed: URL?) {
        guard committed?.absoluteString == "about:blank", let requested, requested.scheme?.hasPrefix("http") == true
        else { return nil }
        message = "Boaz couldn't open this address."
        url = requested
    }
}

private struct BrowserBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.homeControlsElsewhere) private var homeControlsElsewhere
    @Environment(\.siteEdges) private var edges
    @Environment(\.sidebar) private var sidebar
    let tab: SidebarItem
    let page: WebPage
    let axis: Axis

    var body: some View {
        bar.onChange(of: tabCount, initial: true) { SwipeTabsTip.openTabs = tabCount }
    }

    /// On the rail, top to bottom: the tabs, New Tab, then the page settings. The bottom bar has a layout of its own.
    @ViewBuilder private var bar: some View {
        if axis == .vertical {
            RailColumn {
                tabsButton
                RailButton(symbol: "plus", label: "New Tab", isSelected: model.searchTarget != nil, action: toggleSearch)
            } bottom: {
                RailButton(symbol: "ellipsis", label: "Page Settings", isSelected: model.showsPageSettings,
                           action: togglePageSettings)
            }
            .animation(reduceMotion ? .easeOut(duration: 0.2) : .bouncy(duration: 0.35), value: tabCount)
            .popoverTip(SwipeTabsTip(), arrowEdge: .trailing)
        } else {
            bottomBar
        }
    }

    /// The stack of Today tabs (opens the carousel); unfolded, the sidebar toggle takes its place, since the
    /// sidebar lists the tabs. Book and laptop poses list the tabs beside or below the page, so there's none.
    @ViewBuilder private var tabsButton: some View {
        if let sidebar {
            SidebarRailButton(sidebar: sidebar)
        } else if !homeControlsElsewhere {
            if axis == .vertical {
                TabStack(space: model.currentSpace, cardSize: CGSize(width: 26, height: 36)).padding(.vertical, 4)
            } else {
                TabStack(space: model.currentSpace, cardSize: CGSize(width: 34, height: 46))
            }
        }
    }

    /// The phone's own toolbar: the tab fan at the leading end (unfolded, the sidebar toggle), New Tab as a glass pill
    /// in the middle, the page menu in a glass circle at the trailing end. Fixed across the bottom on a frosted strip
    /// in the page's bottom color, with the page ending above it.
    private var bottomBar: some View {
        HStack(spacing: 0) {
            leadingControl.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: toggleSearch) {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .frame(width: 116, height: 50)
                    .railSelection(model.searchTarget != nil)
                    .contentShape(.capsule)
            }
            .buttonStyle(PressableStyle())
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityLabel("New Tab")
            .accessibilityAddTraits(model.searchTarget != nil ? .isSelected : [])
            RailButton(symbol: "ellipsis", label: "Page Settings", isSelected: model.showsPageSettings,
                       action: togglePageSettings)
                .glassEffect(.regular.interactive(), in: .circle)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .popoverTip(SwipeTabsTip(), arrowEdge: .bottom)
        .frame(maxWidth: .infinity)
        .background(.bar, ignoresSafeAreaEdges: .bottom)
        .overlay(alignment: .top) { Divider() }
        .chromeScheme(edges?.bottom)
    }

    /// The tab fan stands on its own; the sidebar toggle that replaces it unfolded gets a glass circle.
    @ViewBuilder private var leadingControl: some View {
        if let sidebar {
            SidebarRailButton(sidebar: sidebar).glassEffect(.regular.interactive(), in: .circle)
        } else {
            tabsButton
        }
    }

    /// New Tab opens the search panel; pressed again, it puts it away. One panel at a time.
    private func toggleSearch() {
        withAnimation(BottomPanelStyle.motion) {
            model.showsPageSettings = false
            if model.searchTarget != nil { model.searchTarget = nil } else { model.beginSearch(.newTab) }
        }
    }

    private func togglePageSettings() {
        withAnimation(BottomPanelStyle.motion) {
            model.searchTarget = nil
            model.showsPageSettings.toggle()
        }
    }

    private var tabCount: Int {
        if model.isIncognito { return model.incognitoTabs.count }
        guard let space = model.currentSpace else { return 0 }
        return model.todayTabs(in: space).count
    }
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
