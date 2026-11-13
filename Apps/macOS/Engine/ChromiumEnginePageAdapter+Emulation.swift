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
            continuation.resume(throwing: ChromiumEmulationError(message: "The viewport response did not match this page.")); return
        }
        let message: String
        switch status {
        case BOAZ_EMULATION_SUCCESS: continuation.resume(); return
        case BOAZ_EMULATION_INVALID: message = "Choose dimensions from 1–8192 and a pixel ratio from 0.5–4."
        case BOAZ_EMULATION_UNAVAILABLE: message = "Close Developer Tools, then try applying the viewport again."
        case BOAZ_EMULATION_TIMEOUT: message = "The viewport change timed out. Try again."
        case BOAZ_EMULATION_NAVIGATION: message = "The page navigated. Apply the viewport again after loading."
        case BOAZ_EMULATION_CLOSED: message = "This page closed before the viewport changed."
        default: message = "Chromium could not apply the viewport. Try resetting it."
        }
        continuation.resume(throwing: ChromiumEmulationError(message: message,
            resetsOverride: status != BOAZ_EMULATION_INVALID && status != BOAZ_EMULATION_UNAVAILABLE))
    }
}

extension ChromiumEnginePageAdapter {
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
            } else { appliedViewport = nil }
            emulationError = (error as? LocalizedError)?.errorDescription ?? "The viewport could not be changed. Close Developer Tools and try again."
            throw error
        }
    }
}
#endif
