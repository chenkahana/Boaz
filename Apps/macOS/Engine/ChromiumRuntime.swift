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
    var prepareWindow: ((ChromiumProfile) -> BoazHostWindowOptions?)?
    var windowCreated: ((BoazHostWindow, UnsafeMutableRawPointer?) -> Void)?
    var windowClosed: ((BoazHostWindow) -> Void)?
    var shutdownReady: (() -> Void)?
    var externalURLs: (([URL]) -> Void)?
    var pageActivated: ((BoazHostWindow, BoazHostPage) -> Void)?
    var pageCreated: ((BoazHostWindow, EnginePage, Bool) -> Void)?
    var pageEvent: ((BoazHostPage, BoazHostPageEvent) -> Void)?

    private static weak var callbackOwner: ChromiumRuntime?
    private var activePages: [BoazHostWindow: BoazHostPage] = [:]
    private var pages: [BoazHostPage: ChromiumEnginePageAdapter] = [:]
    private var preparedProfiles: [BoazHostProfile: ChromiumProfile] = [:]
    private var windowProfiles: [BoazHostWindow: ChromiumProfile] = [:]
    private var preparedWindowContexts: [UInt: ChromiumProfile] = [:]
    private var pendingPageEvents: [BoazHostWindow: [(BoazHostPageEvent, CopiedPageState)]] = [:]
    private var closedWindows: Set<BoazHostWindow> = []
    private var closingPages: Set<BoazHostPage> = []
    private var profileRequests: [EngineProfileIdentity: ProfileRequest] = [:]
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
        guard !started, !stopped, !inCallback, ChromiumRuntime.callbackOwner == nil else {
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
                if event == BOAZ_HOST_PAGE_CLOSING { owner.closingPages.insert(copied.page) }
                if event == BOAZ_HOST_PAGE_CLOSING || event == BOAZ_HOST_PAGE_VIEW_WILL_CHANGE {
                    owner.pages[copied.page]?.detachNativeView()
                }
                DispatchQueue.main.async { [weak owner] in
                    guard let owner, !owner.stopped else { return }
                    owner.receivePage(event, copied)
                }
            }
        }
        callbacks.external_urls = { context, values, count in
            guard let context, let values else { return }
            let urls = (0..<count).compactMap { index -> URL? in
                guard let value = values[index] else { return nil }
                return URL(string: String(cString: value))
            }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { [weak owner] in
                    guard let owner, !owner.stopped else { return }
                    owner.externalURLs?(urls)
                }
            }
        }
        callbacks.prepare_window = { context, profileHandle, output in
            guard let context, let output else { return BOAZ_HOST_INVALID_ARGUMENT }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                guard !owner.stopped, !owner.inCallback else { return BOAZ_HOST_UNAVAILABLE }
                owner.inCallback = true
                defer { owner.inCallback = false }
                guard let profile = owner.preparedProfiles[profileHandle],
                      let options = owner.prepareWindow?(profile) else { return BOAZ_HOST_UNAVAILABLE }
                guard let nativeContext = options.context else { return BOAZ_HOST_INVALID_ARGUMENT }
                let bits = UInt(bitPattern: nativeContext)
                guard owner.preparedWindowContexts[bits] == nil else { return BOAZ_HOST_INVALID_ARGUMENT }
                owner.preparedWindowContexts[bits] = profile
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
                    guard !owner.closedWindows.contains(window), let contextBits,
                          let profile = owner.preparedWindowContexts.removeValue(forKey: contextBits),
                          owner.preparedProfiles[profile.handle] == profile,
                          owner.windowProfiles[window] == nil || owner.windowProfiles[window] == profile else { return }
                    owner.windowProfiles[window] = profile
                    owner.windowCreated?(window, UnsafeMutableRawPointer(bitPattern: contextBits))
                    let events = owner.pendingPageEvents.removeValue(forKey: window) ?? []
                    for (event, state) in events { owner.receivePage(event, state) }
                }
            }
        }
        callbacks.window_closed = { context, window in
            guard let context else { return }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { [weak owner] in
                    guard let owner, !owner.stopped else { return }
                    owner.closedWindows.insert(window)
                    owner.activePages[window] = nil
                    owner.pendingPageEvents[window] = nil
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
                    owner.activePages.removeAll()
                    owner.pendingPageEvents.removeAll()
                    owner.preparedWindowContexts.removeAll()
                    owner.closingPages.removeAll()
                    let requests = Array(owner.profileRequests.values)
                    owner.profileRequests.removeAll()
                    requests.forEach { $0.cancelAll(EnginePageError.unavailable) }
                    owner.pages.values.forEach { $0.detachNativeView() }
                    owner.pages.removeAll()
                    owner.windowProfiles.removeAll()
                    owner.preparedProfiles.removeAll()
                    ChromiumRuntime.callbackOwner = nil
                    owner.shutdownReady?()
                }
            }
        }
        try check(api.set_callbacks!(&callbacks))
        started = true
        ChromiumRuntime.callbackOwner = self
    }

    private func receivePage(_ event: BoazHostPageEvent, _ copied: CopiedPageState) {
        guard !stopped, !closedWindows.contains(copied.window) else { return }
        guard let profile = windowProfiles[copied.window] else {
            pendingPageEvents[copied.window, default: []].append((event, copied))
            return
        }
        if pages[copied.page] == nil, event == BOAZ_HOST_PAGE_CREATED,
           !closingPages.contains(copied.page) {
            do {
                let adapter = try ChromiumEnginePageAdapter(api: api, handle: copied.page, profile: profile.identity)
                pages[copied.page] = adapter
                adapter.apply(event: event, snapshot: copied.snapshot)
                pageCreated?(copied.window, EnginePage(adapter: adapter), copied.active)
            } catch { return }
        } else {
            pages[copied.page]?.apply(event: event, snapshot: copied.snapshot)
        }
        if event == BOAZ_HOST_PAGE_CLOSE_CANCELLED { closingPages.remove(copied.page) }
        if pages[copied.page] != nil {
            pageEvent?(copied.page, event)
            if event != BOAZ_HOST_PAGE_CLOSING && event != BOAZ_HOST_PAGE_CLOSED &&
                !closingPages.contains(copied.page) {
                if copied.active {
                    if activePages[copied.window] != copied.page {
                        activePages[copied.window] = copied.page
                        pageActivated?(copied.window, copied.page)
                    }
                } else if activePages[copied.window] == copied.page {
                    activePages[copied.window] = nil
                }
            }
        }
        if event == BOAZ_HOST_PAGE_CLOSED {
            if activePages[copied.window] == copied.page { activePages[copied.window] = nil }
            pages.removeValue(forKey: copied.page)
            closingPages.remove(copied.page)
        }
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
        let waiter = UUID()
        let profile: ChromiumProfile = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if let request = profileRequests[identity] {
                    request.waiters[waiter] = continuation
                    return
                }
                let request = ProfileRequest(owner: self, identity: identity)
                request.waiters[waiter] = continuation
                profileRequests[identity] = request
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
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.profileRequests[identity]?.cancel(waiter)
            }
        }
        try Task.checkCancellation()
        try requireRunning()
        return profile
    }

    func createWindow(profile: ChromiumProfile, options: inout BoazHostWindowOptions) throws -> BoazHostWindow {
        try requireRunning()
        guard preparedProfiles[profile.handle] == profile else { throw EnginePageError.invalidRequest }
        guard let context = options.context else { throw EnginePageError.invalidRequest }
        let bits = UInt(bitPattern: context)
        guard preparedWindowContexts[bits] == nil else { throw EnginePageError.invalidRequest }
        preparedWindowContexts[bits] = profile
        var handle: BoazHostWindow = 0
        do {
            try check(api.create_profile_window!(profile.handle, &options, &handle))
        } catch {
            preparedWindowContexts[bits] = nil
            throw error
        }
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
        weak var owner: ChromiumRuntime?
        let identity: EngineProfileIdentity
        var waiters: [UUID: CheckedContinuation<ChromiumProfile, Error>] = [:]
        private var finished = false

        init(owner: ChromiumRuntime, identity: EngineProfileIdentity) {
            self.owner = owner
            self.identity = identity
        }
        func cancel(_ id: UUID) {
            waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
        }
        func cancelAll(_ error: Error) {
            let pending = waiters
            waiters.removeAll()
            pending.values.forEach { $0.resume(throwing: error) }
        }
        func finish(_ result: BoazHostResult, handle: BoazHostProfile) {
            guard !finished else { return }
            finished = true
            guard let owner else {
                cancelAll(EnginePageError.unavailable)
                return
            }
            if owner.profileRequests[identity] === self { owner.profileRequests[identity] = nil }
            do {
                try owner.check(result)
                try owner.requireRunning()
                guard handle != 0 else { throw EnginePageError.invalidRequest }
                let profile = ChromiumProfile(handle: handle, identity: identity)
                if let existing = owner.preparedProfiles[handle], existing != profile {
                    throw EnginePageError.invalidRequest
                }
                // Runtime owns prepared profiles; cancellation never releases a shared handle.
                owner.preparedProfiles[handle] = profile
                let pending = waiters
                waiters.removeAll()
                pending.values.forEach { $0.resume(returning: profile) }
            } catch {
                cancelAll(error)
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
            canGoForward: value.can_go_forward != 0, navigationID: value.document_generation,
            isAudible: value.audible != 0, isMuted: value.muted != 0,
            findMatchCount: Int(value.find_match_count), findActiveMatch: Int(value.find_active_match),
            findFinal: value.find_final != 0,
            loadFailure: value.load_error == 0 ? nil : EngineLoadFailure(code: Int(value.load_error),
                url: value.failed_url.flatMap { URL(string: String(cString: $0)) }))
    }
}
#endif
