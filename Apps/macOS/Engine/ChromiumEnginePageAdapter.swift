#if BOAZ_CHROMIUM
import AppKit
import Observation

/// Preserves each bridge failure separately from local lifecycle validation.
enum ChromiumPageBridgeError: Error {
    case invalidArgument
    case invalidHandle
    case closing
    case wrongThread
    case unavailable
    case unknown(UInt32)
}

@MainActor @Observable
final class ChromiumEnginePageAdapter: EnginePageAdapter {
    let kind = BrowserEngineKind.chromium
    let profile: EngineProfileIdentity
    let handle: BoazHostPage
    private(set) var state = EnginePageState()
    @ObservationIgnored private let api: BoazHostAPI
    @ObservationIgnored private var closeRequested = false
    @ObservationIgnored private weak var attachedView: NSView?
    private(set) var viewGeneration = 0

    /// The caller validates the pointer's size/version prefix before copying
    /// a full BoazHostAPI into this value parameter. This cannot validate a
    /// short or invalid source pointer retroactively.
    init(api: BoazHostAPI, handle: BoazHostPage, profile: EngineProfileIdentity) throws {
        guard api.size >= MemoryLayout<BoazHostAPI>.size,
              api.version == BOAZ_HOST_ABI_VERSION,
              api.navigate != nil, api.go_back != nil, api.go_forward != nil,
              api.reload != nil, api.get_native_view != nil, api.close_page != nil else {
            throw EnginePageError.incompatibleBridge
        }
        guard handle != 0 else { throw EnginePageError.invalidRequest }
        self.api = api
        self.handle = handle
        self.profile = profile
    }

    /// Dispatcher copies borrowed callback state, then defers this method.
    /// It separately detaches native views synchronously at CLOSING and
    /// VIEW_WILL_CHANGE; this adapter never registers callbacks or owns views.
    func apply(event: BoazHostPageEvent, snapshot: EnginePageState) {
        guard state.lifecycle != .closed else { return }
        let previousLifecycle = state.lifecycle
        state = snapshot
        if event == BOAZ_HOST_PAGE_VIEW_CHANGED { viewGeneration += 1 }
        switch event {
        case BOAZ_HOST_PAGE_CLOSED:
            state.lifecycle = .closed
            closeRequested = false
        case BOAZ_HOST_PAGE_CLOSING:
            state.lifecycle = .closing
        case BOAZ_HOST_PAGE_CLOSE_CANCELLED:
            state.lifecycle = .active
            closeRequested = false
        case BOAZ_HOST_PAGE_RENDERER_FAILED:
            state.lifecycle = previousLifecycle == .closing ? .closing : .crashed
        default:
            if previousLifecycle == .closing { state.lifecycle = .closing }
        }
    }

    /// Borrowed view. The host retains it; callers must obey detach barriers.
    func nativeView() throws -> NSView {
        try requireOpen()
        var pointer: UnsafeMutableRawPointer?
        try check(api.get_native_view!(handle, &pointer))
        guard let pointer else { throw ChromiumPageBridgeError.unavailable }
        let view = Unmanaged<NSView>.fromOpaque(pointer).takeUnretainedValue()
        attachedView = view
        return view
    }

    func detachNativeView() {
        attachedView?.removeFromSuperview()
        attachedView = nil
    }

    func navigate(to url: URL) throws {
        try requireOpen()
        try url.absoluteString.withCString { try check(api.navigate!(handle, $0)) }
    }
    func goBack() throws {
        try requireOpen()
        try check(api.go_back!(handle))
    }
    func goForward() throws {
        try requireOpen()
        try check(api.go_forward!(handle))
    }
    func reload() throws {
        try requireOpen()
        try check(api.reload!(handle))
    }
    func close() throws {
        guard state.lifecycle != .closed, state.lifecycle != .closing, !closeRequested else { return }
        try check(api.close_page!(handle))
        closeRequested = true
    }

    private func requireOpen() throws {
        if state.lifecycle == .closed || state.lifecycle == .closing { throw EnginePageError.closed }
    }
    private func check(_ result: BoazHostResult) throws {
        switch result {
        case BOAZ_HOST_OK: return
        case BOAZ_HOST_INVALID_ARGUMENT: throw ChromiumPageBridgeError.invalidArgument
        case BOAZ_HOST_INVALID_HANDLE: throw ChromiumPageBridgeError.invalidHandle
        case BOAZ_HOST_CLOSING: throw ChromiumPageBridgeError.closing
        case BOAZ_HOST_WRONG_THREAD: throw ChromiumPageBridgeError.wrongThread
        case BOAZ_HOST_UNAVAILABLE: throw ChromiumPageBridgeError.unavailable
        default: throw ChromiumPageBridgeError.unknown(result.rawValue)
        }
    }
}
#endif
