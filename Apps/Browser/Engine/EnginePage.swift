import Foundation
import Observation

enum BrowserEngineKind: String, Codable, Sendable {
    case webKit
    case chromium
}

struct EngineProfileIdentity: Hashable, Sendable {
    let id: String
    let isPrivate: Bool
}

enum EngineZoomChange: Sendable { case increase, decrease, reset }

enum EnginePageLifecycle: Sendable {
    case active
    case closing
    case closed
    case crashed
}

struct EnginePageState: Equatable, Sendable {
    var url: URL?
    var title = ""
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var lifecycle: EnginePageLifecycle = .active
    var navigationID: UInt64 = 0
    var isAudible = false
    var isMuted = false
    var findMatchCount = -1
    var findActiveMatch = -1
    var findFinal = false
}

enum EnginePageError: Error, LocalizedError {
    case closed
    case unavailable
    case invalidRequest
    case incompatibleBridge

    var errorDescription: String? {
        switch self {
        case .closed: "This page is closed."
        case .unavailable: "The browser engine cannot perform this operation right now."
        case .invalidRequest: "The browser engine rejected the request."
        case .incompatibleBridge: "The Chromium bridge does not match this version of Boaz."
        }
    }
}

@MainActor
protocol EnginePageAdapter: AnyObject {
    var kind: BrowserEngineKind { get }
    var profile: EngineProfileIdentity { get }
    var state: EnginePageState { get }
    func navigate(to url: URL) throws
    func goBack() throws
    func goForward() throws
    func reload() throws
    func stopLoading() throws
    func changeZoom(_ change: EngineZoomChange) throws
    func close() throws
}

@MainActor @Observable
final class EnginePage: Identifiable {
    let id = UUID()
    let adapter: any EnginePageAdapter

    init(adapter: any EnginePageAdapter) {
        self.adapter = adapter
    }

    var kind: BrowserEngineKind { adapter.kind }
    var profile: EngineProfileIdentity { adapter.profile }
    var state: EnginePageState { adapter.state }

    func navigate(to url: URL) throws { try requireOpen(); try adapter.navigate(to: url) }
    func goBack() throws { try requireOpen(); try adapter.goBack() }
    func goForward() throws { try requireOpen(); try adapter.goForward() }
    func reload() throws { try requireOpen(); try adapter.reload() }
    func stopLoading() throws { try requireOpen(); try adapter.stopLoading() }
    func changeZoom(_ change: EngineZoomChange) throws { try requireOpen(); try adapter.changeZoom(change) }
    func close() throws {
        guard state.lifecycle != .closed, state.lifecycle != .closing else { return }
        try adapter.close()
    }

    private func requireOpen() throws {
        if state.lifecycle == .closed || state.lifecycle == .closing { throw EnginePageError.closed }
    }
}
