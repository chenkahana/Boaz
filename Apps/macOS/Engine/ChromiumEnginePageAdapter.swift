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
    var responsiveVisible = false
    var appliedMedia: ChromiumMedia?
    var appliedNetwork: ChromiumNetwork?
    var appliedCPURate = 1.0
    var appliedViewport: ChromiumViewport?
    var appliedUserAgent: String?
    var userAgentDefaults: ChromiumUserAgentDefaults?
    var emulationPending = false
    var emulationError: String?
    @ObservationIgnored var emulationRequest: UInt64 = 0
    @ObservationIgnored let api: BoazHostAPI
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
        if state.navigationID != snapshot.navigationID || snapshot.isLoading && !state.isLoading ||
            event == BOAZ_HOST_PAGE_RENDERER_FAILED || event == BOAZ_HOST_PAGE_CLOSED {
            invalidateEmulationState()
        }
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
    var isBusyForResidency: Bool {
        guard state.lifecycle == .active, let query = api.is_busy_for_residency else { return true }
        var busy: UInt8 = 1
        guard query(handle, &busy) == BOAZ_HOST_OK else { return true }
        return busy != 0
    }

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
    func setAudioMuted(_ muted: Bool) throws {
        try requireOpen()
        guard let setMuted = api.set_audio_muted else { throw EnginePageError.incompatibleBridge }
        try check(setMuted(handle, muted ? 1 : 0))
    }

    func find(text: String, forward: Bool) throws {
        try requireOpen()
        guard !text.isEmpty, text.utf8.count <= 8 * 1024, !text.contains("\0") else {
            throw EnginePageError.invalidRequest
        }
        guard let find = api.find_text else { throw EnginePageError.incompatibleBridge }
        try text.withCString { try check(find(handle, $0, forward ? 1 : 0)) }
    }

    func stopFinding() throws {
        try requireOpen()
        guard let stop = api.stop_find else { throw EnginePageError.incompatibleBridge }
        try check(stop(handle))
    }

    func reload() throws {
        try requireOpen()
        try check(api.reload!(handle))
    }
    func changeZoom(_ change: EngineZoomChange) throws {
        try requireOpen()
        guard let get = api.get_zoom_factor, let set = api.set_zoom_factor else {
            throw EnginePageError.incompatibleBridge
        }
        var current = 1.0
        try check(get(handle, &current))
        guard current.isFinite, current > 0 else { throw EnginePageError.invalidRequest }
        let levels = [0.5, 0.75, 0.85, 1.0, 1.15, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]
        let next: Double = switch change {
        case .increase: levels.first(where: { $0 > current + 0.000001 }) ?? levels.last!
        case .decrease: levels.last(where: { $0 < current - 0.000001 }) ?? levels.first!
        case .reset: 1.0
        }
        try check(set(handle, next))
    }

    struct HistoryEntry: Identifiable {
        let id: Int32
        let offset: Int32
        let url: String
        let title: String
    }
    private final class HistorySnapshot { var entries: [HistoryEntry] = [] }

    func historySnapshot() throws -> [HistoryEntry] {
        try requireOpen()
        guard let enumerate = api.enumerate_history else { throw EnginePageError.incompatibleBridge }
        let snapshot = HistorySnapshot()
        try check(enumerate(handle, { context, id, offset, url, title in
            guard let context else { return }
            MainActor.assumeIsolated {
                Unmanaged<HistorySnapshot>.fromOpaque(context).takeUnretainedValue().entries.append(
                    HistoryEntry(id: id, offset: offset, url: url.map { String(cString: $0) } ?? "",
                                 title: title.map { String(cString: $0) } ?? ""))
            }
        }, Unmanaged.passUnretained(snapshot).toOpaque()))
        return snapshot.entries
    }

    func gotoStableEntry(_ id: Int32) throws {
        try requireOpen()
        guard let navigate = api.go_to_history_entry else { throw EnginePageError.incompatibleBridge }
        try check(navigate(handle, id))
    }

    func stopLoading() throws {
        try requireOpen()
        guard let stop = api.stop_loading else { throw EnginePageError.incompatibleBridge }
        try check(stop(handle))
    }

    func printPage() throws {
        try requireOpen()
        guard let print = api.print_page else { throw EnginePageError.incompatibleBridge }
        try check(print(handle))
    }

    func showDevTools(_ action: BoazHostDevToolsAction) throws {
        try requireOpen()
        guard let show = api.show_devtools else { throw EnginePageError.incompatibleBridge }
        try check(show(handle, action))
    }

    func close() throws {
        guard state.lifecycle != .closed, state.lifecycle != .closing, !closeRequested else { return }
        try check(api.close_page!(handle))
        closeRequested = true
    }

    private func requireOpen() throws {
        if state.lifecycle == .closed || state.lifecycle == .closing { throw EnginePageError.closed }
    }
    func check(_ result: BoazHostResult) throws {
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
