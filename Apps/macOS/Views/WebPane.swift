import AppKit
import BoazKit
import SwiftUI
import WebKit

/// One tab's live page. In split view it gets a slim header that focuses the pane when clicked.
struct TabPane: View {
    @Environment(BrowserState.self) private var browser
    let tab: SidebarItem
    let inSplit: Bool
    @State private var failure: LoadFailure?

    var body: some View {
        let page = browser.page(for: tab)
        VStack(spacing: 0) {
            if inSplit { PaneHeader(tab: tab, page: page) }
            WebView(page)
                .webViewBackForwardNavigationGestures(.enabled)
                .webViewMagnificationGestures(.enabled)
                // The system find bar: match count, ⌘G and ⇧⌘G.
                .findNavigator(isPresented: Binding {
                    browser.findVisible && browser.activeTabID == tab.id
                } set: { browser.findVisible = $0 })
                .overlay { if let failure { LoadFailureView(failure: failure, page: page) } }
                .overlay(alignment: .top) { LoadingGlow(page: page) }
        }
        .task(id: ObjectIdentifier(page)) { await track(page) }
        .onChange(of: page.url) { browser.didChangeURL(tab.id) }
        .onChange(of: page.title) { browser.didChangeTitle(tab.id) }
        .onAppear { browser.updateSiteColor(tab.id, page: page) }
        .onChange(of: page.url) { browser.updateSiteColor(tab.id, page: page) }
        .onChange(of: page.isLoading) { browser.updateSiteColor(tab.id, page: page) }
        .onChange(of: page.isLoading) { browser.pageDidFinishLoading(page: page) }
    }

    /// The page's only `navigations` subscriber. A failed load ends the sequence with an error, so it
    /// resubscribes rather than stopping for the life of the tab.
    private func track(_ page: WebPage) async {
        failure = nil
        while !Task.isCancelled {
            do {
                for try await event in page.navigations {
                    switch event {
                    case .startedProvisionalNavigation: failure = nil
                    case .committed, .finished:
                        if PageZoom.level(for: page.url, isPrivate: browser.isIncognito) != 1 {
                            PageZoom.apply(to: page, isPrivate: browser.isIncognito)
                        }
                    default: break
                    }
                }
                return
            } catch WebPage.NavigationError.pageClosed {
                return
            } catch {
                failure = LoadFailure(error)
                // Never spin if resubscribing fails straight away.
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
}

/// Why a page didn't load, and what to load to retry it.
struct LoadFailure {
    let message: String
    let url: URL?

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

/// Little Boaz: a small window for links opened from other apps, promotable to a full tab.
struct LittleBoazWindow: View {
    @Environment(MacModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let url: URL?
    @State private var page: WebPage?
    @State private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer().frame(width: 64)
                if let page, page.url != nil {
                    Image(systemName: page.url?.scheme == "https" ? "lock.fill" : "globe")
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
                    WebView(page).overlay(alignment: .top) { LoadingGlow(page: page) }
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
        }
        holder.store = configuration.websiteDataStore
        model.applyContentBlocking(to: &configuration)
        let page = WebPage(configuration: configuration, navigationDecider: LittleRouter(holder: holder),
                           dialogPresenter: MacDialogs())
        holder.page = page
        page.load(URLRequest(url: url))
        self.page = page
    }
}

/// Little Boaz keeps "new window" links in the same small window.
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
            holder.page?.load(URLRequest(url: url))
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
