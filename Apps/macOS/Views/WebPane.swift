import AppKit
import BoazKit
import Network
import SwiftUI
import WebKit

struct TabPane: View {
    @Environment(BrowserState.self) private var browser
    let tab: SidebarItem
    let inSplit: Bool

    var body: some View {
        #if BOAZ_CHROMIUM
        if browser.createChromiumPage != nil {
            ChromiumTabPane(tab: tab, inSplit: inSplit).id(tab.id)
        } else {
            WebKitTabPane(tab: tab, inSplit: inSplit)
        }
        #else
        WebKitTabPane(tab: tab, inSplit: inSplit)
        #endif
    }
}

#if BOAZ_CHROMIUM
private struct ChromiumTabPane: View {
    @Environment(BrowserState.self) private var browser
    let tab: SidebarItem
    let inSplit: Bool
    @State private var engine: EnginePage?
    @State private var failure: String?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            if inSplit {
                let focused = browser.activeTabID == tab.id
                HStack(spacing: 8) {
                    Text(engine?.state.title.isEmpty == false ? engine!.state.title :
                         (tab.title ?? engine?.state.url?.host() ?? "New Tab"))
                        .font(.caption.weight(focused ? .semibold : .regular)).lineLimit(1)
                    Spacer()
                    if hovering {
                        HoverIconButton(symbol: "rectangle.split.2x1.slash", help: "Separate", size: 20) {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                browser.split = nil
                                browser.focusPane(tab.id)
                            }
                        }
                        HoverIconButton(symbol: "xmark", help: "Close", size: 20) { browser.close(tab) }
                    }
                }
                .padding(.horizontal, 10).frame(height: 26)
                .background(.primary.opacity(focused ? 0.06 : 0.02))
                .contentShape(Rectangle())
                .onTapGesture { browser.focusPane(tab.id) }
                .onHover { hovering = $0 }
            }
            if let failure {
                ContentUnavailableView {
                    Label("Can't Open This Page", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Try Again", action: open).buttonStyle(.glass)
                }
            } else if let engine, let adapter = engine.adapter as? ChromiumEnginePageAdapter {
                ChromiumPageView(adapter: adapter)
                    .overlay(alignment: .top) {
                        if engine.state.isLoading { ProgressView().padding(8) }
                    }
            } else {
                ProgressView("Opening page…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: tab.id) { open() }
        .task(id: faviconDocument) {
            guard faviconDocument != nil,
                  let adapter = engine?.adapter as? ChromiumEnginePageAdapter else { return }
            await ChromiumPageServices.learnFavicon(from: adapter)
        }
        .onChange(of: engine?.state, initial: true) {
            guard let state = engine?.state, !state.isLoading, state.lifecycle == .active else { return }
            browser.didNavigate(tab.id, url: state.url, title: state.title)
        }
    }

    private var faviconDocument: String? {
        guard let adapter = engine?.adapter as? ChromiumEnginePageAdapter,
              !adapter.profile.isPrivate, adapter.state.lifecycle == .active,
              !adapter.state.isLoading, let url = adapter.state.url else { return nil }
        return "\(adapter.handle):\(adapter.state.navigationID):\(url.absoluteString)"
    }

    private func open() {
        failure = nil
        do {
            let page = try browser.enginePage(for: tab)
            guard page.adapter is ChromiumEnginePageAdapter else { throw EnginePageError.incompatibleBridge }
            engine = page
        } catch {
            engine = nil
            failure = "Chromium could not open this page: \(String(describing: error))."
        }
    }
}
#endif

/// One tab's live page. In split view it gets a slim header that focuses the pane when clicked.
private struct WebKitTabPane: View {
    @Environment(BrowserState.self) private var browser
    let tab: SidebarItem
    let inSplit: Bool
    @State private var retriedOnItsOwn = false
    /// While the quiet retry is pending, the failure isn't shown.
    @State private var retrying = false
    /// The room the page has in Responsive Design Mode.
    @State private var stage = CGSize.zero

    private var failure: LoadFailure? {
        get { browser.loadFailures[tab.id] }
        nonmutating set { browser.loadFailures[tab.id] = newValue }
    }

    var body: some View {
        let page = browser.page(for: tab)
        let devTools = browser.devTools[tab.id]
        let scale = devTools.responsive?.size.map {
            max(0.1, min(1, (stage.width - 24) / $0.width, (stage.height - 24) / $0.height))
        } ?? 1
        VStack(spacing: 0) {
            if inSplit { PaneHeader(tab: tab, page: page) }
            if let viewport = devTools.responsive {
                ResponsiveBar(tabID: tab.id, viewport: viewport, stage: stage, scale: scale)
            }
            WebView(page)
                .webViewBackForwardNavigationGestures(.enabled)
                .webViewMagnificationGestures(.enabled)
                // The system find bar: match count, ⌘G and ⇧⌘G.
                .findNavigator(isPresented: Binding {
                    browser.findVisible && browser.activeTabID == tab.id
                } set: { browser.findVisible = $0 })
                .overlay { PasswordSuggestions(tabID: tab.id, page: page) }
                .overlay(alignment: .top) { SavePasswordPrompt(tabID: tab.id) }
                .animation(.smooth(duration: 0.25), value: PasswordAutofill.shared.offer)
                .overlay { if let failure, !retrying { LoadFailureView(failure: failure, page: page) } }
                .overlay(alignment: .top) { LoadingGlow(page: page) }
                .deviceViewport(devTools.responsive, scale: scale, appearance: devTools.appearance, stage: $stage)
            if browser.devTools.consoleVisible && browser.activeTabID == tab.id { ConsolePanel(tabID: tab.id, page: page) }
        }
        .task(id: ObjectIdentifier(page)) { await track(page) }
        // A load that failed for want of a connection loads again once there is one, when Boaz comes forward and
        // when the Mac wakes. The monitor reports the current path first, so a tab shown later retries too.
        .task(id: ObjectIdentifier(page)) {
            for await path in NWPathMonitor() where path.status == .satisfied { retryIfPassing(on: page) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            retryIfPassing(on: page)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            retryIfPassing(on: page)
        }
        .onChange(of: page.url) { browser.didChangeURL(tab.id) }
        .onChange(of: page.title) { browser.didChangeTitle(tab.id) }
        .onChange(of: page.isLoading) { browser.pageDidFinishLoading(page: page) }
        // A first load can settle before `track` subscribes.
        .onChange(of: page.isLoading) { browser.didChangeURL(tab.id) }
    }

    /// The page's only `navigations` subscriber. A failed load ends the sequence with an error, so it
    /// resubscribes rather than stopping for the life of the tab. A failure from before it subscribed (the tab's first
    /// load, see `BrowserState.makePage`) stays until the next load starts.
    private func track(_ page: WebPage) async {
        var requested: URL?
        while !Task.isCancelled {
            do {
                for try await event in page.navigations {
                    switch event {
                    case .startedProvisionalNavigation:
                        failure = nil
                        requested = page.url
                    case .receivedServerRedirect:
                        requested = page.url
                    case .committed, .finished:
                        if event == .finished { retriedOnItsOwn = false }
                        if event == .committed, let blocked = LoadFailure(blocked: requested, committed: page.url) {
                            failure = blocked
                        }
                        if event == .committed {
                            requested = nil
                            browser.didCommitLoad(tab.id)
                        }
                        // The address the page settled on, which `didChangeURL` skips while a load is in flight.
                        browser.didChangeURL(tab.id, committed: true)
                        if PageZoom.level(for: page.url, isPrivate: browser.isIncognito) != 1 {
                            PageZoom.apply(to: page, isPrivate: browser.isIncognito)
                        }
                        browser.devToolsDidLoad(tab.id)
                    default: break
                    }
                }
                return
            } catch WebPage.NavigationError.pageClosed {
                return
            } catch {
                failure = LoadFailure(error)
                if case WebPage.NavigationError.webContentProcessTerminated = error {
                    PictureInPicture.controller(of: page)?.pageDidReset()
                    browser.pageDidTerminate(tab.id)
                }
                // The network often comes back a moment after a wake or a Wi-Fi change: one quiet retry first.
                if failure?.passes == true, !retriedOnItsOwn {
                    retriedOnItsOwn = true
                    retrying = true
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        retrying = false
                        retryIfPassing(on: page)
                    }
                }
                // Never spin if resubscribing fails straight away.
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func retryIfPassing(on page: WebPage) {
        guard let failure, failure.passes else { return }
        self.failure = nil
        if let url = failure.url { _ = page.load(URLRequest(url: url)) } else { _ = page.reload(tabURL: tab.url) }
    }
}

/// Why a page didn't load, and what to load to retry it.
struct LoadFailure {
    let message: String
    let url: URL?
    /// Whether it may well load on its own later: the connection was down or dropped, or the page's process ended.
    var passes = false

    /// Nil for loads that were stopped on purpose (a new navigation, a download, a link routed elsewhere).
    init?(_ error: Error) {
        var underlying = error
        if case WebPage.NavigationError.failedProvisionalNavigation(let inner) = error { underlying = inner }
        let nsError = underlying as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return nil }
        // WebKitErrorFrameLoadInterruptedByPolicyChange and WebKitErrorPlugInWillHandleLoad.
        if nsError.domain == "WebKitErrorDomain" && [102, 204].contains(nsError.code) { return nil }
        message = switch error {
        case WebPage.NavigationError.webContentProcessTerminated: "The page stopped working."
        case WebPage.NavigationError.invalidURL: "The address isn't valid."
        default: nsError.localizedDescription
        }
        url = nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL
        if case WebPage.NavigationError.webContentProcessTerminated = error { passes = true } else {
            passes = nsError.domain == NSURLErrorDomain && [
                NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut,
                NSURLErrorDataNotAllowed, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost,
            ].contains(nsError.code)
        }
    }

    /// Waits out one load: why it failed, or nil once it commits a page.
    static func of(_ load: some AsyncSequence<WebPage.NavigationEvent, any Error>, page: WebPage,
                   url: URL) async -> LoadFailure? {
        do {
            for try await event in load where event == .committed {
                return LoadFailure(blocked: url, committed: page.url)
            }
            return nil
        } catch {
            return LoadFailure(error)
        }
    }

    /// WebKit refuses some ports (1, 9, 25 and so on) without any navigation error: it commits about:blank instead.
    init?(blocked requested: URL?, committed: URL?) {
        guard committed?.absoluteString == "about:blank", let requested, requested.scheme?.hasPrefix("http") == true
        else { return nil }
        message = "Boaz couldn't open this address."
        url = requested
    }
}

private struct LoadFailureView: View {
    let failure: LoadFailure
    let page: WebPage

    var body: some View {
        ContentUnavailableView {
            Label("Can't Open This Page", systemImage: "wifi.exclamationmark")
        } description: {
            Text(failure.message)
        } actions: {
            Button("Try Again") {
                if let url = failure.url { _ = page.load(URLRequest(url: url)) } else { _ = page.reload() }
            }
            .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct PaneHeader: View {
    @Environment(BrowserState.self) private var browser
    let tab: SidebarItem
    let page: WebPage
    @State private var hovering = false

    var body: some View {
        let focused = browser.activeTabID == tab.id
        HStack(spacing: 8) {
            Text(page.title.isEmpty ? (tab.title ?? page.url?.host() ?? "New Tab") : page.title)
                .font(.caption.weight(focused ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            if hovering {
                HoverIconButton(symbol: "rectangle.split.2x1.slash", help: "Separate", size: 20) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { browser.split = nil; browser.focusPane(tab.id) }
                }
                HoverIconButton(symbol: "xmark", help: "Close", size: 20) { browser.close(tab) }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(.primary.opacity(focused ? 0.06 : 0.02))
        .contentShape(Rectangle())
        .onTapGesture { browser.focusPane(tab.id) }
        .onHover { hovering = $0 }
    }
}

/// Quick Window: a small window for links opened from other apps, promotable to a full tab.
struct QuickWindow: View {
    @Environment(MacModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let url: URL?
    @State private var page: WebPage?
    /// The profile whose data store the page uses; deleting that profile closes the window.
    @State private var profileID: String?
    @State private var failure: LoadFailure?
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer().frame(width: 64)
                if let page, page.url != nil {
                    Image(systemName: page.url?.scheme == "https" && page.serverTrust != nil ? "lock.fill" : "globe")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(page.title.isEmpty ? (page.url?.host() ?? "") : page.title)
                        .font(.callout.weight(.medium)).lineLimit(1)
                } else {
                    TextField("Search or enter address", text: $address)
                        .textFieldStyle(.plain)
                        .focused($addressFocused)
                        .onSubmit(go)
                }
                Spacer()
                Button {
                    if let current = page?.url ?? url { model.openInMainWindow(current, title: page?.title) }
                    dismiss()
                } label: {
                    Label("Open in Boaz", systemImage: "arrow.up.forward.app")
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.white.opacity(0.35), in: .capsule)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("o")
                .disabled(page?.url == nil)
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
            Group {
                if let page {
                    WebView(page)
                        .overlay { if let failure { LoadFailureView(failure: failure, page: page) } }
                        .overlay(alignment: .top) { LoadingGlow(page: page) }
                } else {
                    Color(nsColor: .textBackgroundColor)
                }
            }
            .clipShape(.rect(cornerRadius: MacRadius.row, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
            .padding([.horizontal, .bottom], 6)
        }
        .background(LinearGradient(colors: [Theme.peach.opacity(0.55), Theme.electric.opacity(0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .ignoresSafeArea()
        .frame(minWidth: 420, minHeight: 320)
        .onAppear {
            guard page == nil else { return }
            if let url { start(url) } else { addressFocused = true }
        }
        .onChange(of: model.sidebar.profiles.map(\.id)) { _, ids in
            guard let profileID, !ids.contains(profileID) else { return }
            page = nil
            dismiss()
        }
        .task(id: page.map(ObjectIdentifier.init)) {
            guard let page else { return }
            // As a tab's pane does: a failed load ends the sequence, so it resubscribes.
            while !Task.isCancelled {
                do {
                    for try await event in page.navigations where event == .startedProvisionalNavigation {
                        failure = nil
                    }
                    return
                } catch WebPage.NavigationError.pageClosed {
                    return
                } catch {
                    failure = LoadFailure(error)
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
    }

    private func go() {
        guard let url = SearchInput.url(for: address, searchTemplate: Preferences.searchEngine.template) else { return }
        start(url)
    }

    private func start(_ url: URL) {
        let holder = LittleRouter.Holder()
        var configuration = WebPage.Configuration()
        if let profile = model.sidebar.profiles.first(where: \.isDefault) ?? model.sidebar.profiles.first {
            configuration.websiteDataStore = model.dataStore(for: profile.id)
            profileID = profile.id
        }
        holder.store = configuration.websiteDataStore
        model.applyContentBlocking(to: &configuration)
        let page = WebPage(configuration: configuration, navigationDecider: LittleRouter(holder: holder),
                           dialogPresenter: MacDialogs())
        holder.page = page
        page.isInspectable = true
        // A page that never loads has no address of its own, so the field keeps the one asked for.
        address = url.absoluteString
        failure = nil
        model.load(url, in: page, configuration: configuration) { failure = $0 }
        self.page = page
    }
}

/// A Quick Window keeps "new window" links in the same small window.
private struct LittleRouter: WebPage.NavigationDeciding {
    final class Holder { weak var page: WebPage?; var store: WKWebsiteDataStore = .default() }
    let holder: Holder

    func decidePolicy(for action: WebPage.NavigationAction,
                      preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
        if action.shouldPerformDownload, let url = action.request.url {
            PageDownloads.start(url, store: holder.store)
            return .cancel
        }
        if action.target == nil, let url = action.request.url {
            if LinkDownloadMenu.takeRequest() { PageDownloads.start(url, store: holder.store) } else {
                holder.page?.load(URLRequest(url: url))
            }
            return .cancel
        }
        return .allow
    }

    func decidePolicy(for response: WebPage.NavigationResponse) async -> WKNavigationResponsePolicy {
        guard PageDownloads.shouldDownload(response), let url = response.response.url else { return .allow }
        PageDownloads.start(url, store: holder.store)
        return .cancel
    }
}
