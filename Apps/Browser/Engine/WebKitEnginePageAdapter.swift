import Foundation
import Observation
import WebKit

@MainActor @Observable
final class WebKitEnginePageAdapter: EnginePageAdapter {
    let page: WebPage
    let profile: EngineProfileIdentity
    let kind: BrowserEngineKind = .webKit
    private var lifecycle: EnginePageLifecycle = .active

    init(page: WebPage, profile: EngineProfileIdentity) {
        self.page = page
        self.profile = profile
    }

    var state: EnginePageState {
        EnginePageState(
            url: page.url,
            title: page.title,
            isLoading: page.isLoading,
            canGoBack: !page.backForwardList.backList.isEmpty,
            canGoForward: !page.backForwardList.forwardList.isEmpty,
            lifecycle: lifecycle
        )
    }

    func navigate(to url: URL) throws {
        try requireOpen()
        page.load(URLRequest(url: url))
    }

    func goBack() throws {
        try requireOpen()
        if let item = page.backForwardList.backList.last { page.load(item) }
    }

    func goForward() throws {
        try requireOpen()
        if let item = page.backForwardList.forwardList.first { page.load(item) }
    }

    func reload() throws {
        try requireOpen()
        page.reload()
    }

    func stopLoading() throws {
        guard state.lifecycle == .active else { throw EnginePageError.closed }
        page.stopLoading()
    }

    func changeZoom(_ change: EngineZoomChange) throws {
        guard state.lifecycle == .active else { throw EnginePageError.closed }
        let action: PageZoom.Change = switch change {
        case .increase: .in
        case .decrease: .out
        case .reset: .reset
        }
        PageZoom.change(action, for: page, isPrivate: profile.isPrivate)
    }

    func close() throws {
        guard lifecycle != .closing, lifecycle != .closed else { return }
        lifecycle = .closing
        page.stopLoading()
        lifecycle = .closed
    }

    private func requireOpen() throws {
        if lifecycle == .closing || lifecycle == .closed { throw EnginePageError.closed }
    }
}
