#if BOAZ_CHROMIUM
import Foundation

struct ChromiumViewport: Equatable {
    var width = 390
    var height = 844
    var dpr = 2.0
    var mobile = true
    var touch = true
    var maxTouchPoints = 1
    var landscape = false
}

struct ChromiumUserAgentDefaults: Codable {
    struct Metadata: Codable {
        struct Brand: Codable { let brand: String; let version: String }
        let brands: [Brand]
        let fullVersionList: [Brand]
        let fullVersion: String
        let platform: String
        let platformVersion: String
        let architecture: String
        let model: String
        let bitness: String
        let mobile: Bool
        let wow64: Bool
        let formFactors: [String]
    }
    let userAgent: String
    let navigatorPlatform: String
    let metadata: Metadata
}

@MainActor
private final class UserAgentDefaultsReply {
    var values: (String, String, String)?
}

private struct ChromiumEmulationError: LocalizedError {
    let message: String
    var resetsOverride = true
    var errorDescription: String? { message }
}

@MainActor
private final class EmulationRequest {
    let page: BoazHostPage
    let id: UInt64
    let continuation: CheckedContinuation<Void, Error>
    init(page: BoazHostPage, id: UInt64, continuation: CheckedContinuation<Void, Error>) {
        self.page = page; self.id = id; self.continuation = continuation
    }
    func complete(page: BoazHostPage, id: UInt64, status: BoazHostEmulationStatus) {
        guard page == self.page, id == self.id else {
            continuation.resume(throwing: ChromiumEmulationError(message: "The override response did not match this page.")); return
        }
        let message: String
        switch status {
        case BOAZ_EMULATION_SUCCESS: continuation.resume(); return
        case BOAZ_EMULATION_INVALID: message = "Chromium rejected these override values."
        case BOAZ_EMULATION_UNAVAILABLE: message = "Close Developer Tools, then try applying the override again."
        case BOAZ_EMULATION_TIMEOUT: message = "The override change timed out. Try again."
        case BOAZ_EMULATION_NAVIGATION: message = "The page navigated. Apply the override again after loading."
        case BOAZ_EMULATION_CLOSED: message = "This page closed before the override changed."
        default: message = "Chromium could not apply the override. Try resetting it."
        }
        continuation.resume(throwing: ChromiumEmulationError(message: message,
            resetsOverride: status != BOAZ_EMULATION_INVALID && status != BOAZ_EMULATION_UNAVAILABLE))
    }
}

extension ChromiumEnginePageAdapter {
    func readUserAgentDefaults() throws {
        guard state.lifecycle == .active, let read = api.get_user_agent_defaults else { throw EnginePageError.unavailable }
        let box = UserAgentDefaultsReply()
        let context = Unmanaged.passUnretained(box).toOpaque()
        try check(read(handle, { context, userAgent, platform, metadata in
            guard let context, let userAgent, let platform, let metadata else { return }
            MainActor.assumeIsolated {
                let box = Unmanaged<UserAgentDefaultsReply>.fromOpaque(context).takeUnretainedValue()
                box.values = (String(cString: userAgent), String(cString: platform), String(cString: metadata))
            }
        }, context))
        guard let (ua, platform, json) = box.values else { throw EnginePageError.unavailable }
        userAgentDefaults = ChromiumUserAgentDefaults(userAgent: ua, navigatorPlatform: platform,
            metadata: try JSONDecoder().decode(ChromiumUserAgentDefaults.Metadata.self, from: Data(json.utf8)))
    }

    func applyUserAgent(_ value: String?) async throws {
        guard !emulationPending, state.lifecycle == .active, !state.isLoading,
              let apply = api.apply_user_agent, emulationRequest < UInt64.max else {
            emulationError = "Wait for this page to finish loading before changing its user agent."
            throw EnginePageError.unavailable
        }
        if let value, value.isEmpty || value.utf8.count > 8192 || value.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "\0" }) {
            emulationError = "Enter a user agent of 1–8192 bytes without line breaks."
            throw EnginePageError.invalidRequest
        }
        emulationRequest += 1
        let request = emulationRequest
        let navigation = state.navigationID
        emulationPending = true
        emulationError = nil
        defer { emulationPending = false }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let box = EmulationRequest(page: handle, id: request, continuation: continuation)
                let context = Unmanaged.passRetained(box).toOpaque()
                let callback: BoazHostEmulationCompletion = { context, page, request, status in
                    guard let context else { return }
                    MainActor.assumeIsolated {
                        let box = Unmanaged<EmulationRequest>.fromOpaque(context).takeRetainedValue()
                        DispatchQueue.main.async { box.complete(page: page, id: request, status: status) }
                    }
                }
                let result = value.map { string in
                    string.withCString { apply(handle, $0, string.utf8.count, request, callback, context) }
                } ?? apply(handle, nil, 0, request, callback, context)
                if result != BOAZ_HOST_OK {
                    Unmanaged<EmulationRequest>.fromOpaque(context).release()
                    do { try check(result) } catch { continuation.resume(throwing: error) }
                }
            }
            guard state.lifecycle == .active, state.navigationID == navigation, !state.isLoading else {
                throw ChromiumEmulationError(message: "The page changed. Apply the override after loading.")
            }
            appliedUserAgent = value
        } catch {
            if state.navigationID != navigation || state.lifecycle != .active || state.isLoading ||
                (error as? ChromiumEmulationError)?.resetsOverride == true {
                appliedUserAgent = nil
                appliedViewport = nil
                appliedMedia = nil
            }
            emulationError = (error as? LocalizedError)?.errorDescription ?? "The user agent could not be changed. Close Developer Tools and try again."
            throw error
        }
    }

    func applyViewport(_ viewport: ChromiumViewport?) async throws {
        guard !emulationPending, state.lifecycle == .active, !state.isLoading,
              let apply = api.apply_viewport else {
            emulationError = "Wait for this page to finish loading before changing its viewport."
            throw EnginePageError.unavailable
        }
        if let value = viewport {
            guard (1...8192).contains(value.width), (1...8192).contains(value.height),
                  value.dpr.isFinite, (0.5...4).contains(value.dpr),
                  (1...10).contains(value.maxTouchPoints) else {
                emulationError = "Use dimensions from 1–8192, a pixel ratio from 0.5–4, and 1–10 touch points."
                throw EnginePageError.invalidRequest
            }
        }
        guard emulationRequest < UInt64.max else { throw EnginePageError.unavailable }
        emulationRequest += 1
        let request = emulationRequest
        let navigation = state.navigationID
        let previous = appliedViewport
        emulationPending = true
        emulationError = nil
        defer { emulationPending = false }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let box = EmulationRequest(page: handle, id: request, continuation: continuation)
                let context = Unmanaged.passRetained(box).toOpaque()
                let callback: BoazHostEmulationCompletion = { context, page, request, status in
                    guard let context else { return }
                    MainActor.assumeIsolated {
                        let box = Unmanaged<EmulationRequest>.fromOpaque(context).takeRetainedValue()
                        DispatchQueue.main.async { box.complete(page: page, id: request, status: status) }
                    }
                }
                let result: BoazHostResult
                if let viewport {
                    var native = BoazHostViewport(width: Int32(viewport.width), height: Int32(viewport.height),
                        dpr: viewport.dpr, mobile: viewport.mobile ? 1 : 0, touch: viewport.touch ? 1 : 0,
                        landscape: viewport.landscape ? 1 : 0, max_touch_points: Int32(viewport.maxTouchPoints))
                    result = apply(handle, &native, request, callback, context)
                } else { result = apply(handle, nil, request, callback, context) }
                if result != BOAZ_HOST_OK {
                    Unmanaged<EmulationRequest>.fromOpaque(context).release()
                    do { try check(result) } catch { continuation.resume(throwing: error) }
                }
            }
            guard state.lifecycle == .active, state.navigationID == navigation, !state.isLoading else {
                throw ChromiumEmulationError(message: "The page changed. Apply the viewport again after loading.")
            }
            appliedViewport = viewport
        } catch {
            if state.navigationID == navigation, state.lifecycle == .active, !state.isLoading,
               (error as? ChromiumEmulationError)?.resetsOverride != true {
                appliedViewport = previous
            } else { appliedViewport = nil; appliedUserAgent = nil; appliedMedia = nil }
            emulationError = (error as? LocalizedError)?.errorDescription ?? "The viewport could not be changed. Close Developer Tools and try again."
            throw error
        }
    }

    func applyMedia(_ media: ChromiumMedia?) async throws {
        guard !emulationPending, state.lifecycle == .active, !state.isLoading,
              let apply = api.apply_media else {
            emulationError = "Wait for this page to finish loading before changing its media."
            throw EnginePageError.unavailable
        }
        guard emulationRequest < UInt64.max else { throw EnginePageError.unavailable }
        emulationRequest += 1
        let request = emulationRequest
        let navigation = state.navigationID
        let previous = appliedMedia
        emulationPending = true
        emulationError = nil
        defer { emulationPending = false }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let box = EmulationRequest(page: handle, id: request, continuation: continuation)
                let context = Unmanaged.passRetained(box).toOpaque()
                let callback: BoazHostEmulationCompletion = { context, page, request, status in
                    guard let context else { return }
                    MainActor.assumeIsolated {
                        let box = Unmanaged<EmulationRequest>.fromOpaque(context).takeRetainedValue()
                        DispatchQueue.main.async { box.complete(page: page, id: request, status: status) }
                    }
                }
                let result: BoazHostResult
                if let media {
                    var native = media.native
                    result = apply(handle, &native, request, callback, context)
                } else { result = apply(handle, nil, request, callback, context) }
                if result != BOAZ_HOST_OK {
                    Unmanaged<EmulationRequest>.fromOpaque(context).release()
                    do { try check(result) } catch { continuation.resume(throwing: error) }
                }
            }
            guard state.lifecycle == .active, state.navigationID == navigation, !state.isLoading else {
                throw ChromiumEmulationError(message: "The page changed. Apply the media again after loading.")
            }
            appliedMedia = media
        } catch {
            if state.navigationID == navigation, state.lifecycle == .active, !state.isLoading,
               (error as? ChromiumEmulationError)?.resetsOverride != true {
                appliedMedia = previous
            } else { appliedMedia = nil; appliedUserAgent = nil; appliedViewport = nil }
            emulationError = (error as? LocalizedError)?.errorDescription ?? "The media could not be changed. Close Developer Tools and try again."
            throw error
        }
    }
}
#endif
