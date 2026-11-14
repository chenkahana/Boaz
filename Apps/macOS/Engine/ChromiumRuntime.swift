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
    var prepareWindow: ((ChromiumProfile, BoazHostWindowRole) -> BoazHostWindowOptions?)?
    var windowCreated: ((BoazHostWindow, UnsafeMutableRawPointer?) -> Void)?
    var windowClosed: ((BoazHostWindow) -> Void)?
    var shutdownReady: (() -> Void)?
    var externalURLs: (([URL]) -> Void)?
    var reopenRequested: (() -> Void)?
    var pageActivated: ((BoazHostWindow, BoazHostPage) -> Void)?
    var pageCreated: ((BoazHostWindow, EnginePage, Bool) -> Void)?
    var pageEvent: ((BoazHostPage, BoazHostPageEvent) -> Void)?
    var devToolsDockChanged: ((BoazHostWindow, String, String) -> Void)?
    var passwordSubmission: ((ChromiumEnginePageAdapter, ChromiumCapturedDocument, URL, String, String) -> Void)?
    var passwordFocus: ((ChromiumEnginePageAdapter, UInt64, ChromiumCapturedDocument?, CGRect) -> Void)?
    var protectedMedia: ((BoazHostPage, UInt64, EngineProfileIdentity, ProtectedMediaService.KeySystem) -> Void)?

    private static weak var callbackOwner: ChromiumRuntime?
    private var downloads: [BoazHostProfile: ChromiumDownloads] = [:]
    private var activePages: [BoazHostWindow: BoazHostPage] = [:]
    private var pages: [BoazHostPage: ChromiumEnginePageAdapter] = [:]
    private var preparedProfiles: [BoazHostProfile: ChromiumProfile] = [:]
    private var windowProfiles: [BoazHostWindow: ChromiumProfile] = [:]
    private var preparedWindowContexts: [UInt: ChromiumProfile] = [:]
    private var pendingPageEvents: [BoazHostWindow: [(BoazHostPageEvent, CopiedPageState)]] = [:]
    private var pendingExtensionWindows: Set<BoazHostWindow> = []
    private var closedWindows: Set<BoazHostWindow> = []
    private var closingPages: Set<BoazHostPage> = []
    private var profileRequests: [EngineProfileIdentity: ProfileRequest] = [:]
    private var blockingRequest: BlockingRequest?
    private struct BlockingConfiguration: Equatable {
        let enabled: Bool
        let exceptionSites: [String]
    }
    private var blockingConfigurations: [BoazHostProfile: BlockingConfiguration] = [:]
    private var blockingPrepared = false
    private var blockingShutdownRequested = false
    private var cacheRequestID: UInt64 = 0
    private var clearingCacheProfiles: Set<BoazHostProfile> = []
    private var cookieRequestID: UInt64 = 0
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
              table.prepare_blocking_assets != nil, table.configure_profile_blocking != nil,
              table.create_profile_window != nil, table.release_profile != nil,
              table.create_page != nil, table.navigate != nil,
              table.go_back != nil, table.go_forward != nil, table.reload != nil,
              table.get_native_view != nil, table.close_page != nil,
              table.close_window != nil, table.request_shutdown != nil,
              table.enumerate_downloads != nil, table.download_action != nil else {
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
        callbacks.extensions_changed = { context, window in
            guard let context else { return }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                guard owner.pendingExtensionWindows.insert(window).inserted else { return }
                DispatchQueue.main.async { [weak owner] in
                    guard let owner else { return }
                    owner.pendingExtensionWindows.remove(window)
                    guard !owner.stopped, !owner.closedWindows.contains(window) else { return }
                    NotificationCenter.default.post(name: ChromiumExtensionManagement.installedExtensionsChanged,
                        object: nil, userInfo: ["window": window])
                }
            }
        }
        callbacks.devtools_dock_changed = { context, window, current, last in
            guard let context, (0...3).contains(current), (0...2).contains(last) else { return }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { [weak owner] in
                    guard let owner, !owner.stopped, !owner.closedWindows.contains(window) else { return }
                    let sides = ["right", "bottom", "left", "undocked"]
                    owner.devToolsDockChanged?(window, sides[Int(current)], sides[Int(last)])
                }
            }
        }
        callbacks.password_submission = { context, page, token, source, destination, username, usernameLength, password, passwordLength in
            guard let context else { return }
            let sourceURL = source.flatMap { URL(string: String(cString: $0)) }
            let destinationURL = destination.flatMap { URL(string: String(cString: $0)) }
            func copied(_ pointer: UnsafePointer<CChar>?, _ count: Int) -> String? {
                guard let pointer, count >= 0, count <= 65536 else { return nil }
                let bytes = UnsafeBufferPointer(start: UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self), count: count)
                return String(bytes: bytes, encoding: .utf8)
            }
            let user = copied(username, usernameLength)
            let secret = passwordLength <= 65536 - min(usernameLength, 65536) ? copied(password, passwordLength) : nil
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async {
                    guard !owner.stopped, !owner.closingPages.contains(page), token != 0,
                          let adapter = owner.pages[page], !adapter.profile.isPrivate,
                          let sourceURL, let destinationURL, let user, let secret, !secret.isEmpty,
                          ["http", "https"].contains(sourceURL.scheme ?? ""), sourceURL.host != nil,
                          ["http", "https"].contains(destinationURL.scheme ?? ""), destinationURL.host != nil,
                          let handler = owner.passwordSubmission else {
                        if token != 0 { _ = owner.api.release_document?(page, token) }
                        return
                    }
                    handler(adapter, ChromiumCapturedDocument(owner: adapter, origin: destinationURL, token: token),
                        sourceURL, user, secret)
                }
            }
        }
        callbacks.password_focus = { context, page, sequence, token, origin, x, y, width, height in
            guard let context else { return }
            let copiedOrigin = origin.map { String(cString: $0) }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async {
                    guard !owner.stopped, !owner.closingPages.contains(page),
                          let adapter = owner.pages[page], let handler = owner.passwordFocus else {
                        if token != 0 { _ = owner.api.release_document?(page, token) }
                        return
                    }
                    var target: ChromiumCapturedDocument?
                    if token != 0 {
                        guard let copiedOrigin, let url = URL(string: copiedOrigin),
                              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
                              url.host != nil else {
                            _ = owner.api.release_document?(page, token)
                            return
                        }
                        target = ChromiumCapturedDocument(owner: adapter, origin: url, token: token)
                    }
                    handler(adapter, sequence, target, CGRect(x: x, y: y, width: width, height: height))
                }
            }
        }
        callbacks.protected_media = { context, page, navigation, profile, system in
            guard let context else { return }
            let key: ProtectedMediaService.KeySystem
            switch system {
            case BOAZ_KEY_WIDEVINE: key = .widevine
            case BOAZ_KEY_PLAYREADY: key = .playReady
            default: return
            }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { [weak owner] in
                    guard let owner, !owner.stopped, let identity = owner.preparedProfiles[profile]?.identity,
                          let adapter = owner.pages[page], adapter.profile == identity,
                          adapter.state.navigationID == navigation, adapter.state.lifecycle == .active else { return }
                    owner.protectedMedia?(page, navigation, identity, key)
                }
            }
        }
        callbacks.download_changed = { context, profile, pointer in
            guard let context, let pointer else { return }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                let copied = ChromiumDownload(pointer.pointee)
                DispatchQueue.main.async { [weak owner] in
                    guard let owner, !owner.stopped, owner.preparedProfiles[profile] != nil else { return }
                    owner.downloadModel(profile).update(copied)
                }
            }
        }
        callbacks.reopen_requested = { context in
            guard let context else { return }
            MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                DispatchQueue.main.async { [weak owner] in
                    guard let owner, !owner.stopped else { return }
                    owner.reopenRequested?()
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
        callbacks.prepare_window = { context, profileHandle, role, output in
            guard let context, let output else { return BOAZ_HOST_INVALID_ARGUMENT }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<ChromiumRuntime>.fromOpaque(context).takeUnretainedValue()
                guard !owner.stopped, !owner.inCallback else { return BOAZ_HOST_UNAVAILABLE }
                owner.inCallback = true
                defer { owner.inCallback = false }
                guard let profile = owner.preparedProfiles[profileHandle],
                      owner.blockingConfigurations[profileHandle] != nil,
                      let options = owner.prepareWindow?(profile, role) else { return BOAZ_HOST_UNAVAILABLE }
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
                    owner.blockingPrepared = false
                    owner.blockingRequest?.cancelAll(EnginePageError.unavailable)
                    owner.blockingRequest = nil
                    owner.downloads.values.forEach { $0.dispose() }
                    owner.downloads.removeAll()
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
                    owner.blockingConfigurations.removeAll()
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
        if event == BOAZ_HOST_PAGE_CLOSE_CANCELLED {
            closingPages.remove(copied.page)
            blockingShutdownRequested = false
        }
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

    func createPage(window: BoazHostWindow, url: URL, profile: EngineProfileIdentity, javaScriptDisabled: Bool = false) throws -> EnginePage {
        try requireRunning()
        guard let verified = windowProfiles[window], verified.identity == profile,
              preparedProfiles[verified.handle] == verified else { throw EnginePageError.invalidRequest }
        var handle: BoazHostPage = 0
        let initialURL = javaScriptDisabled ? "about:blank" : url.absoluteString
        try initialURL.withCString { try check(api.create_page!(window, $0, &handle)) }
        guard handle != 0, pages[handle] == nil else { throw EnginePageError.invalidRequest }
        do {
            if javaScriptDisabled {
                guard let set = api.set_javascript_disabled else { throw EnginePageError.incompatibleBridge }
                try check(set(handle, 1))
                try url.absoluteString.withCString { try check(api.navigate!(handle, $0)) }
            }
            let adapter = try ChromiumEnginePageAdapter(api: api, handle: handle, profile: profile)
            adapter.javaScriptDisabled = javaScriptDisabled
            pages[handle] = adapter
            return EnginePage(adapter: adapter)
        } catch {
            closingPages.insert(handle)
            let result = api.close_page!(handle)
            if result != BOAZ_HOST_OK { closingPages.remove(handle) }
            throw error
        }
    }

    func prepareBlockingAssets() async throws {
        try requireRunning()
        try Task.checkCancellation()
        guard !blockingShutdownRequested else { throw EnginePageError.unavailable }
        if blockingPrepared { return }
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("BoazBlocking", isDirectory: true),
              (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw NSError(domain: "Boaz.BlockingAssets", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Boaz’s bundled content-blocking resources are missing."])
        }
        let waiter = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if let request = blockingRequest {
                    request.waiters[waiter] = continuation
                    return
                }
                let request = BlockingRequest(owner: self)
                request.waiters[waiter] = continuation
                blockingRequest = request
                let context = Unmanaged.passRetained(request).toOpaque()
                let result = directory.path.withCString {
                    api.prepare_blocking_assets!($0, { context, result in
                        guard let context else { return }
                        MainActor.assumeIsolated {
                            let request = Unmanaged<BlockingRequest>.fromOpaque(context).takeRetainedValue()
                            DispatchQueue.main.async { request.finish(result) }
                        }
                    }, context)
                }
                if result != BOAZ_HOST_OK {
                    Unmanaged<BlockingRequest>.fromOpaque(context).release()
                    request.finish(result)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.blockingRequest?.cancel(waiter) }
        }
        try Task.checkCancellation()
        try requireRunning()
        guard blockingPrepared, !blockingShutdownRequested else { throw EnginePageError.unavailable }
    }

    private final class BlockingRequest {
        weak var owner: ChromiumRuntime?
        var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
        private var finished = false
        init(owner: ChromiumRuntime) { self.owner = owner }
        func cancel(_ id: UUID) { waiters.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
        func cancelAll(_ error: Error) {
            finished = true
            let pending = waiters
            waiters.removeAll()
            pending.values.forEach { $0.resume(throwing: error) }
        }
        func finish(_ result: BoazHostResult) {
            guard !finished else { return }
            finished = true
            guard let owner else { cancelAll(EnginePageError.unavailable); return }
            if owner.blockingRequest === self { owner.blockingRequest = nil }
            do {
                try owner.check(result)
                try owner.requireRunning()
                guard !owner.blockingShutdownRequested else { throw EnginePageError.unavailable }
                owner.blockingPrepared = true
                let pending = waiters
                waiters.removeAll()
                pending.values.forEach { $0.resume() }
            } catch { cancelAll(error) }
        }
    }

    func prepareProfile(_ identity: EngineProfileIdentity) async throws -> ChromiumProfile {
        try requireRunning()
        try Task.checkCancellation()
        guard !identity.id.isEmpty, !identity.id.contains("\0") else { throw EnginePageError.invalidRequest }
        if let existing = preparedProfiles.values.first(where: { $0.identity == identity }) {
            if blockingConfigurations[existing.handle] == nil {
                try configureBlocking(profile: existing, enabled: Preferences.blockTrackers, exceptionSites: [])
            }
            return existing
        }
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
        guard preparedProfiles[profile.handle] == profile,
              blockingConfigurations[profile.handle] != nil else { throw EnginePageError.invalidRequest }
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

    static func automationStatus() throws -> ChromiumAutomationStatus {
        guard let owner = callbackOwner else { throw EnginePageError.unavailable }
        try owner.requireRunning()
        guard let read = owner.api.automation_status else { throw EnginePageError.unavailable }
        final class Box { var value: ChromiumAutomationStatus? }
        let box = Box()
        let result = read({ context, state, requested, _, error in
            guard let context else { return }
            let copiedError = error.map { String(cString: $0) }
            MainActor.assumeIsolated {
                let box = Unmanaged<Box>.fromOpaque(context).takeUnretainedValue()
                let mapped: ChromiumAutomationStatus.State
                switch state {
                case BOAZ_AUTOMATION_DISABLED: mapped = .disabled
                case BOAZ_AUTOMATION_STARTING: mapped = .starting
                case BOAZ_AUTOMATION_READY: mapped = .ready
                default: mapped = .failed
                }
                box.value = ChromiumAutomationStatus(state: mapped, requestedAtStartup: requested != 0,
                    error: copiedError.flatMap { $0.isEmpty ? nil : $0 })
            }
        }, Unmanaged.passUnretained(box).toOpaque())
        try owner.check(result)
        guard let value = box.value else { throw EnginePageError.unavailable }
        return value
    }

    static func clearCaches(for identity: EngineProfileIdentity) async throws {
        guard let owner = callbackOwner else { throw EnginePageError.unavailable }
        try await owner.clearCache(profile: identity)
    }

    func clearCache(profile identity: EngineProfileIdentity) async throws {
        try requireRunning()
        guard let profile = preparedProfiles.values.first(where: { $0.identity == identity }),
              !clearingCacheProfiles.contains(profile.handle), cacheRequestID < UInt64.max,
              let clear = api.clear_cache else { throw EnginePageError.unavailable }
        cacheRequestID += 1
        let requestID = cacheRequestID
        clearingCacheProfiles.insert(profile.handle)
        defer { clearingCacheProfiles.remove(profile.handle) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let box = CacheRequest(profile: profile.handle, request: requestID, continuation: continuation)
            let context = Unmanaged.passRetained(box).toOpaque()
            let result = clear(profile.handle, requestID, { context, profile, request, status in
                guard let context else { return }
                MainActor.assumeIsolated {
                    let box = Unmanaged<CacheRequest>.fromOpaque(context).takeRetainedValue()
                    DispatchQueue.main.async {
                        guard profile == box.profile, request == box.request, status == BOAZ_CACHE_SUCCESS else {
                            box.continuation.resume(throwing: EnginePageError.unavailable)
                            return
                        }
                        box.continuation.resume()
                    }
                }
            }, context)
            if result != BOAZ_HOST_OK {
                Unmanaged<CacheRequest>.fromOpaque(context).release()
                do { try check(result) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private final class CacheRequest {
        let profile: BoazHostProfile
        let request: UInt64
        let continuation: CheckedContinuation<Void, Error>
        init(profile: BoazHostProfile, request: UInt64, continuation: CheckedContinuation<Void, Error>) {
            self.profile = profile; self.request = request; self.continuation = continuation
        }
    }

    func importCookies(profile: ChromiumProfile, cookies: [HTTPCookie]) async throws -> (imported: UInt32, rejected: UInt32) {
        try requireRunning()
        guard preparedProfiles[profile.handle] == profile, cookieRequestID < UInt64.max,
              let importCookies = api.import_cookies else { throw EnginePageError.unavailable }
        cookieRequestID += 1
        let requestID = cookieRequestID
        let strings = cookies.map { [$0.name, $0.value, $0.domain, $0.path].map { strdup($0) } }
        defer { strings.joined().forEach { free($0) } }
        let values = zip(cookies, strings).map { cookie, text in
            let sameSite: Int32 = cookie.sameSitePolicy == .sameSiteLax ? 2 : cookie.sameSitePolicy == .sameSiteStrict ? 3 : 0
            return BoazHostCookie(name: UnsafePointer(text[0]), value: UnsafePointer(text[1]),
                domain: UnsafePointer(text[2]), path: UnsafePointer(text[3]),
                expires_unix: cookie.isSessionOnly ? 0 : cookie.expiresDate?.timeIntervalSince1970 ?? 0,
                secure: cookie.isSecure ? 1 : 0, http_only: cookie.isHTTPOnly ? 1 : 0, same_site: sameSite)
        }
        return try await withCheckedThrowingContinuation { continuation in
            let box = CookieImportRequest(request: requestID, continuation: continuation)
            let context = Unmanaged.passRetained(box).toOpaque()
            let result = values.withUnsafeBufferPointer {
                importCookies(profile.handle, $0.baseAddress, $0.count, requestID, { context, request, status, imported, rejected in
                    guard let context else { return }
                    MainActor.assumeIsolated {
                        let box = Unmanaged<CookieImportRequest>.fromOpaque(context).takeRetainedValue()
                        DispatchQueue.main.async {
                            guard request == box.request, status == BOAZ_HOST_OK else {
                                box.continuation.resume(throwing: EnginePageError.unavailable)
                                return
                            }
                            box.continuation.resume(returning: (imported, rejected))
                        }
                    }
                }, context)
            }
            if result != BOAZ_HOST_OK {
                Unmanaged<CookieImportRequest>.fromOpaque(context).release()
                do { try check(result) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private final class CookieImportRequest {
        let request: UInt64
        let continuation: CheckedContinuation<(imported: UInt32, rejected: UInt32), Error>
        init(request: UInt64, continuation: CheckedContinuation<(imported: UInt32, rejected: UInt32), Error>) {
            self.request = request; self.continuation = continuation
        }
    }

    static func showDownloads(for identity: EngineProfileIdentity) {
        guard let owner = callbackOwner, !owner.stopped,
              let profile = owner.preparedProfiles.values.first(where: { $0.identity == identity }) else { return }
        let model = owner.downloadModel(profile.handle)
        do {
            try owner.requireRunning()
            let collector = ChromiumDownloadSnapshotCollector()
            let context = Unmanaged.passUnretained(collector).toOpaque()
            try owner.check(owner.api.enumerate_downloads!(profile.handle, { context, _, pointer in
                guard let context, let pointer else { return }
                MainActor.assumeIsolated {
                    let copied = ChromiumDownload(pointer.pointee)
                    Unmanaged<ChromiumDownloadSnapshotCollector>.fromOpaque(context).takeUnretainedValue().items.append(copied)
                }
            }, context))
            collector.items.forEach { model.update($0) }
        } catch { model.error = "Downloads could not be refreshed. Please try again." }
        model.show(isPrivate: identity.isPrivate)
    }

    private func downloadModel(_ profile: BoazHostProfile) -> ChromiumDownloads {
        if let model = downloads[profile] { return model }
        let model = ChromiumDownloads()
        model.perform = { [weak self] id, action in
            guard let self, preparedProfiles[profile] != nil else { throw EnginePageError.unavailable }
            try requireRunning()
            try check(api.download_action!(profile, id, action))
        }
        downloads[profile] = model
        return model
    }

    func configureBlocking(profile: ChromiumProfile, enabled: Bool, exceptionSites: [String]) throws {
        try requireRunning()
        guard blockingPrepared, !blockingShutdownRequested,
              preparedProfiles[profile.handle] == profile else { throw EnginePageError.invalidRequest }
        guard exceptionSites.count <= 10_000,
              exceptionSites.allSatisfy({ !$0.isEmpty && !$0.contains("\0") && $0.utf8.count <= 2048 }) else {
            throw EnginePageError.invalidRequest
        }
        let config = BlockingConfiguration(enabled: enabled, exceptionSites: exceptionSites)
        if blockingConfigurations[profile.handle] == config { return }
        let data = try JSONSerialization.data(withJSONObject: exceptionSites)
        guard let json = String(data: data, encoding: .utf8) else { throw EnginePageError.invalidRequest }
        try json.withCString { try check(api.configure_profile_blocking!(profile.handle, enabled ? 1 : 0, $0)) }
        blockingConfigurations[profile.handle] = config
    }

    func applyBlockingPreference(_ enabled: Bool) throws {
        try requireRunning()
        var firstFailure: Error?
        for profile in preparedProfiles.values.sorted(by: { $0.handle < $1.handle }) {
            do {
                try configureBlocking(profile: profile, enabled: enabled,
                                      exceptionSites: blockingConfigurations[profile.handle]?.exceptionSites ?? [])
            } catch { if firstFailure == nil { firstFailure = error } }
        }
        if let firstFailure { throw firstFailure }
    }

    func releaseProfile(_ profile: ChromiumProfile) throws {
        try requireRunning()
        guard preparedProfiles[profile.handle] == profile else { throw EnginePageError.invalidRequest }
        guard !windowProfiles.values.contains(profile) else { throw EnginePageError.unavailable }
        try check(api.release_profile!(profile.handle))
        preparedProfiles.removeValue(forKey: profile.handle)
        blockingConfigurations.removeValue(forKey: profile.handle)
        downloads.removeValue(forKey: profile.handle)?.dispose()
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
                if owner.blockingConfigurations[handle] == nil {
                    do {
                        try owner.configureBlocking(profile: profile, enabled: Preferences.blockTrackers, exceptionSites: [])
                    } catch {
                        // Failed cleanup stays owned but cannot create windows without a published policy.
                        try? owner.releaseProfile(profile)
                        throw error
                    }
                }
                let pending = waiters
                waiters.removeAll()
                pending.values.forEach { $0.resume(returning: profile) }
            } catch {
                cancelAll(error)
            }
        }
    }

    func restoreDevToolsDockPreferences(window: BoazHostWindow, current: String, last: String) throws {
        let sides = ["right", "bottom", "left", "undocked"]
        guard !stopped, let set = api.set_devtools_dock_preferences,
              let currentIndex = sides.firstIndex(of: current),
              let lastIndex = sides.prefix(3).firstIndex(of: last) else {
            throw EnginePageError.invalidRequest
        }
        try check(set(window, Int32(currentIndex), Int32(lastIndex)))
    }

    func adapter(for handle: BoazHostPage) -> ChromiumEnginePageAdapter? { pages[handle] }

    func requestShutdown() throws {
        try requireRunning()
        try check(api.request_shutdown!())
        blockingShutdownRequested = true
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
