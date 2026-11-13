#if BOAZ_CHROMIUM
import Foundation

struct ChromiumProfile: Equatable {
    let handle: BoazHostProfile
    let identity: EngineProfileIdentity
    fileprivate init(handle: BoazHostProfile, identity: EngineProfileIdentity) {
        self.handle = handle
        self.identity = identity
    }
}

/// The application retains this sole callback owner until shutdownReady runs.
@MainActor
final class ChromiumRuntime {
    let api: BoazHostAPI
    var prepareWindow: (() -> BoazHostWindowOptions?)?
    var windowCreated: ((BoazHostWindow, UnsafeMutableRawPointer?) -> Void)?
    var windowClosed: ((BoazHostWindow) -> Void)?
    var shutdownReady: (() -> Void)?
    var pageEvent: ((BoazHostPage, BoazHostPageEvent) -> Void)?

    private static weak var callbackOwner: ChromiumRuntime?
    private var pages: [BoazHostPage: ChromiumEnginePageAdapter] = [:]
    private var preparedProfiles: [BoazHostProfile: ChromiumProfile] = [:]
    private var windowProfiles: [BoazHostWindow: ChromiumProfile] = [:]
    private var preparingIdentities: Set<EngineProfileIdentity> = []
    private var started = false
    private var stopped = false
    private var inCallback = false

    init(api pointer: UnsafePointer<BoazHostAPI>) throws {
        guard pointer.pointee.size >= MemoryLayout<BoazHostAPI>.size,
              pointer.pointee.version == BOAZ_HOST_ABI_VERSION else {
            throw EnginePageError.incompatibleBridge
        }
        let table = pointer.pointee
        guard table.set_callbacks != nil, table.prepare_profile != nil,
              table.create_profile_window != nil, table.release_profile != nil,
              table.create_page != nil, table.navigate != nil,
              table.go_back != nil, table.go_forward != nil, table.reload != nil,
              table.get_native_view != nil, table.close_page != nil,
              table.close_window != nil, table.request_shutdown != nil else {
            throw EnginePageError.incompatibleBridge
        }
        api = table
    }

    func startCallbacks() throws {
        guard !started, !stopped, !inCallback, Self.callbackOwner == nil else {
            throw EnginePageError.unavailable
        }
        var callbacks = BoazHostCallbacks()
        callbacks.size = MemoryLayout<BoazHostCallbacks>.size
        callbacks.context = Unmanaged.passUnretained(self).toOpaque()
        callbacks.page_event = { context, event, pointer in
            guard let context, let pointer,
                  pointer.pointee.size >= MemoryLayout<BoazHostPageState>.size else { return }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                owner.inCallback = true
                defer { owner.inCallback = false }
                let copied = CopiedPageState(pointer.pointee)
                if event == BOAZ_HOST_PAGE_CLOSING || event == BOAZ_HOST_PAGE_VIEW_WILL_CHANGE {
                    owner.pages[copied.page]?.detachNativeView()
                }
                DispatchQueue.main.async { [weak owner] in
                    guard let owner, !owner.stopped, let adapter = owner.pages[copied.page] else { return }
                    adapter.apply(event: event, snapshot: copied.snapshot)
                    owner.pageEvent?(copied.page, event)
                    if event == BOAZ_HOST_PAGE_CLOSED { owner.pages.removeValue(forKey: copied.page) }
                }
            }
        }
        callbacks.prepare_window = { context, output in
            guard let context, let output else { return BOAZ_HOST_INVALID_ARGUMENT }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                guard !owner.stopped, !owner.inCallback else { return BOAZ_HOST_UNAVAILABLE }
                owner.inCallback = true
                defer { owner.inCallback = false }
                guard let options = owner.prepareWindow?() else { return BOAZ_HOST_UNAVAILABLE }
                output.pointee = options
                return BOAZ_HOST_OK
            }
        }
        callbacks.window_created = { context, window, windowContext in
            guard let context else { return }
            let contextBits = windowContext.map { UInt(bitPattern: $0) }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { [weak owner] in
                    guard let owner, !owner.stopped else { return }
                    owner.windowCreated?(window, contextBits.flatMap { UnsafeMutableRawPointer(bitPattern: $0) })
                }
            }
        }
        callbacks.window_closed = { context, window in
            guard let context else { return }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { [weak owner] in
                    guard let owner, !owner.stopped else { return }
                    owner.windowProfiles.removeValue(forKey: window)
                    owner.windowClosed?(window)
                }
            }
        }
        callbacks.shutdown_ready = { context in
            guard let context else { return }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async {
                    guard !owner.stopped else { return }
                    owner.stopped = true
                    owner.pages.values.forEach { $0.detachNativeView() }
                    owner.pages.removeAll()
                    owner.windowProfiles.removeAll()
                    owner.preparedProfiles.removeAll()
                    Self.callbackOwner = nil
                    owner.shutdownReady?()
                }
            }
        }
        try check(api.set_callbacks!(&callbacks))
        started = true
        Self.callbackOwner = self
    }

    func createPage(window: BoazHostWindow, url: URL, profile: EngineProfileIdentity) throws -> EnginePage {
        try requireRunning()
        guard let verified = windowProfiles[window], verified.identity == profile,
              preparedProfiles[verified.handle] == verified else { throw EnginePageError.invalidRequest }
        var handle: BoazHostPage = 0
        try url.absoluteString.withCString { try check(api.create_page!(window, $0, &handle)) }
        guard handle != 0, pages[handle] == nil else { throw EnginePageError.invalidRequest }
        let adapter = try ChromiumEnginePageAdapter(api: api, handle: handle, profile: profile)
        pages[handle] = adapter
        return EnginePage(adapter: adapter)
    }

    func prepareProfile(_ identity: EngineProfileIdentity) async throws -> ChromiumProfile {
        try requireRunning()
        try Task.checkCancellation()
        guard !identity.id.isEmpty, !identity.id.contains("\0") else { throw EnginePageError.invalidRequest }
        if let existing = preparedProfiles.values.first(where: { $0.identity == identity }) { return existing }
        guard preparingIdentities.insert(identity).inserted else { throw EnginePageError.unavailable }
        defer { preparingIdentities.remove(identity) }
        let profile: ChromiumProfile = try await withCheckedThrowingContinuation { continuation in
            let request = ProfileRequest(owner: self, identity: identity, continuation: continuation)
            let context = Unmanaged.passRetained(request).toOpaque()
            let result = identity.id.withCString {
                api.prepare_profile!($0, identity.isPrivate ? 1 : 0, { context, result, handle in
                    guard let context else { return }
                    MainActor.assumeIsolated {
                        let request = Unmanaged<ProfileRequest>.fromOpaque(context).takeRetainedValue()
                        DispatchQueue.main.async { request.finish(result, handle: handle) }
                    }
                }, context)
            }
            if result != BOAZ_HOST_OK {
                Unmanaged<ProfileRequest>.fromOpaque(context).release()
                request.finish(result, handle: 0)
            }
        }
        if Task.isCancelled {
            if !windowProfiles.values.contains(profile) { try? releaseProfile(profile) }
            throw CancellationError()
        }
        return profile
    }

    func createWindow(profile: ChromiumProfile, options: inout BoazHostWindowOptions) throws -> BoazHostWindow {
        try requireRunning()
        guard preparedProfiles[profile.handle] == profile else { throw EnginePageError.invalidRequest }
        var handle: BoazHostWindow = 0
        try check(api.create_profile_window!(profile.handle, &options, &handle))
        guard handle != 0, windowProfiles[handle] == nil else { throw EnginePageError.invalidRequest }
        windowProfiles[handle] = profile
        return handle
    }

    func createWindow(options: inout BoazHostWindowOptions) throws -> BoazHostWindow {
        throw EnginePageError.unavailable
    }

    func releaseProfile(_ profile: ChromiumProfile) throws {
        try requireRunning()
        guard preparedProfiles[profile.handle] == profile else { throw EnginePageError.invalidRequest }
        guard !windowProfiles.values.contains(profile) else { throw EnginePageError.unavailable }
        try check(api.release_profile!(profile.handle))
        preparedProfiles.removeValue(forKey: profile.handle)
    }

    private final class ProfileRequest {
        let owner: ChromiumRuntime
        let identity: EngineProfileIdentity
        var continuation: CheckedContinuation<ChromiumProfile, Error>?
        init(owner: ChromiumRuntime, identity: EngineProfileIdentity,
             continuation: CheckedContinuation<ChromiumProfile, Error>) {
            self.owner = owner
            self.identity = identity
            self.continuation = continuation
        }
        func finish(_ result: BoazHostResult, handle: BoazHostProfile) {
            guard let continuation else { return }
            self.continuation = nil
            do {
                try owner.check(result)
                try owner.requireRunning()
                guard handle != 0 else { throw EnginePageError.invalidRequest }
                let profile = ChromiumProfile(handle: handle, identity: identity)
                if let existing = owner.preparedProfiles[handle], existing != profile {
                    throw EnginePageError.invalidRequest
                }
                owner.preparedProfiles[handle] = profile
                continuation.resume(returning: profile)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    func adapter(for handle: BoazHostPage) -> ChromiumEnginePageAdapter? { pages[handle] }

    func requestShutdown() throws {
        try requireRunning()
        try check(api.request_shutdown!())
    }

    private func requireRunning() throws {
        guard started, !stopped, !inCallback else { throw EnginePageError.unavailable }
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

private struct CopiedPageState {
    let page: BoazHostPage
    let window: BoazHostWindow
    let documentGeneration: UInt64
    let extensionTabID: Int32
    let extensionWindowID: Int32
    let active: Bool
    let snapshot: EnginePageState

    init(_ value: BoazHostPageState) {
        page = value.page
        window = value.window
        documentGeneration = value.document_generation
        extensionTabID = value.extension_tab_id
        extensionWindowID = value.extension_window_id
        active = value.active != 0
        let url = value.url.map { String(cString: $0) }
        snapshot = EnginePageState(url: url.flatMap(URL.init(string:)),
            title: value.title.map { String(cString: $0) } ?? "",
            isLoading: value.loading != 0, canGoBack: value.can_go_back != 0,
            canGoForward: value.can_go_forward != 0)
    }
}
#endif
