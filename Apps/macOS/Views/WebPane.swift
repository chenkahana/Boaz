import AppKit
import FolioKit
import SwiftUI
import WebKit

/// One tab's live page. In split view it gets a slim header that focuses the pane when clicked.
struct TabPane: View {
    @Environment(BrowserState.self) private var browser
    let tab: SidebarItem
    let inSplit: Bool

    var body: some View {
        let page = browser.page(for: tab)
        VStack(spacing: 0) {
            if inSplit { PaneHeader(tab: tab, page: page) }
            WebView(page)
                .webViewBackForwardNavigationGestures(.enabled)
                .webViewMagnificationGestures(.enabled)
                .overlay(alignment: .top) { LoadingGlow(page: page) }
                .overlay(alignment: .topTrailing) {
                    if browser.findVisible && browser.activeTabID == tab.id {
                        FindBar(page: page).transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.85), value: browser.findVisible)
        }
        .onChange(of: page.url) { browser.didNavigate(tab.id, url: page.url, title: page.title) }
        .onChange(of: page.title) { browser.didNavigate(tab.id, url: page.url, title: page.title) }
        .onAppear { browser.updateSiteColor(tab.id, page: page) }
        .onChange(of: page.url) { browser.updateSiteColor(tab.id, page: page) }
        .onChange(of: page.isLoading) { browser.updateSiteColor(tab.id, page: page) }
        .onChange(of: page.isLoading) { browser.pageDidFinishLoading(page: page) }
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
            Text(page.title.isEmpty ? (tab.title ?? page.url?.host() ?? "Tab") : page.title)
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

/// ⌘F: WebKit's own `window.find`, which selects and scrolls to each match.
private struct FindBar: View {
    @Environment(BrowserState.self) private var browser
    let page: WebPage
    @State private var text = ""
    @State private var missed = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in page", text: $text)
                .textFieldStyle(.plain)
                .frame(width: 180)
                .focused($focused)
                .onSubmit { find(backwards: NSEvent.modifierFlags.contains(.shift)) }
                .onChange(of: text) { find(backwards: false, fromStart: true) }
            if missed { Text("No matches").font(.caption).foregroundStyle(.secondary) }
            HoverIconButton(symbol: "chevron.up", size: 22) { find(backwards: true) }
            HoverIconButton(symbol: "chevron.down", size: 22) { find(backwards: false) }
            HoverIconButton(symbol: "xmark", size: 22) { close() }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        .padding(10)
        .onAppear { focused = true }
        .onKeyPress(.escape) { close(); return .handled }
    }

    private func find(backwards: Bool, fromStart: Bool = false) {
        let query = text
        Task {
            if fromStart { _ = try? await page.callJavaScript("window.getSelection().removeAllRanges()") }
            guard !query.isEmpty else { missed = false; return }
            let found = try? await page.callJavaScript("return window.find(q, false, b, true, false, false, false);",
                                                       arguments: ["q": query, "b": backwards])
            missed = (found as? Bool) == false
        }
    }

    private func close() {
        browser.findVisible = false
        Task { _ = try? await page.callJavaScript("window.getSelection().removeAllRanges()") }
    }
}

/// Little Folio: a small window for links opened from other apps, promotable to a full tab.
struct LittleFolioWindow: View {
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
                    Label("Open in Folio", systemImage: "arrow.up.forward.app")
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
            .clipShape(.rect(cornerRadius: 9, style: .continuous))
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

/// Little Folio keeps "new window" links in the same small window.
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
