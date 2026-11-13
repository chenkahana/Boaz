#if BOAZ_CHROMIUM
import Foundation
import Darwin

enum ChromiumCaptureError: Error {
    case invalidTarget, navigation, closed, rendererFailed, timeout, busy, tooLarge, failed
    case identityMismatch, malformedResult
    case unknownStatus(UInt32)
}

extension ChromiumEnginePageAdapter {
    func captureVisible(maxWidth: Int = 1024, maxHeight: Int = 768) async throws -> Data {
        try Task.checkCancellation()
        guard state.lifecycle == .active else { throw ChromiumCaptureError.closed }
        guard maxWidth > 0, maxHeight > 0, maxWidth <= 2048, maxHeight <= 2048,
              maxWidth * maxHeight <= 2 * 1024 * 1024 else { throw ChromiumCaptureError.tooLarge }
        guard let capture = api.capture_visible, let cancel = api.cancel_capture else {
            throw EnginePageError.incompatibleBridge
        }
        return try await captureData(maxBytes: 8 * 1024 * 1024,
            signature: [137, 80, 78, 71, 13, 10, 26, 10], cancel: cancel) { request, completion, context in
                capture(handle, request, Int32(maxWidth), Int32(maxHeight), completion, context)
            }
    }

    func capturePDF() async throws -> Data {
        try Task.checkCancellation()
        guard state.lifecycle == .active else { throw ChromiumCaptureError.closed }
        guard let capture = api.capture_pdf, let cancel = api.cancel_pdf else {
            throw EnginePageError.incompatibleBridge
        }
        return try await captureData(maxBytes: 32 * 1024 * 1024,
            signature: Array("%PDF-".utf8), cancel: cancel) { request, completion, context in
                capture(handle, request, completion, context)
            }
    }

    private func captureData(maxBytes: Int, signature: [UInt8],
        cancel: @escaping @convention(c) (BoazHostPage, UInt64) -> BoazHostResult,
        start: (UInt64, BoazHostCaptureCompletion, UnsafeMutableRawPointer) -> BoazHostResult) async throws -> Data {
        let navigation = state.navigationID
        let request = ChromiumCaptureRequest(page: handle, maxBytes: maxBytes, signature: signature, cancel: cancel)
        let data = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                request.continuation = continuation
                if request.cancelled || Task.isCancelled { request.finishCancellation(); return }
                let context = Unmanaged.passRetained(request).toOpaque()
                let result = start(request.id,
                    { context, page, id, status, bytes, size in
                        guard let context else { return }
                        MainActor.assumeIsolated {
                            let request = Unmanaged<ChromiumCaptureRequest>.fromOpaque(context).takeRetainedValue()
                            let oversized = size > request.maxBytes
                            let data = !oversized && size > 0 ? bytes.map { Data(bytes: $0, count: size) } : nil
                            DispatchQueue.main.async {
                                request.finish(page: page, id: id, status: status, data: data, oversized: oversized)
                            }
                        }
                    }, context)
                if result == BOAZ_HOST_OK {
                    request.accepted = true
                } else {
                    Unmanaged<ChromiumCaptureRequest>.fromOpaque(context).release()
                    do { try check(result) } catch { request.fail(error) }
                }
            }
        } onCancel: {
            Task { @MainActor in request.cancel() }
        }
        try Task.checkCancellation()
        guard state.lifecycle == .active else { throw ChromiumCaptureError.closed }
        guard state.navigationID == navigation else { throw ChromiumCaptureError.navigation }
        return data
    }
}

@MainActor private final class ChromiumCaptureRequest {
    private static var nextID: UInt64 = 1
    let id: UInt64
    let page: BoazHostPage
    let maxBytes: Int
    let signature: [UInt8]
    let cancelOperation: @convention(c) (BoazHostPage, UInt64) -> BoazHostResult
    var continuation: CheckedContinuation<Data, Error>?
    var accepted = false
    private(set) var cancelled = false

    init(page: BoazHostPage, maxBytes: Int, signature: [UInt8], cancel: @escaping @convention(c) (BoazHostPage, UInt64) -> BoazHostResult) {
        precondition(Self.nextID < UInt64.max)
        id = Self.nextID
        Self.nextID += 1
        self.page = page
        self.maxBytes = maxBytes
        self.signature = signature
        cancelOperation = cancel
    }
    func cancel() {
        cancelled = true
        if accepted && continuation != nil { _ = cancelOperation(page, id) }
    }
    func finishCancellation() { fail(CancellationError()) }
    func fail(_ error: Error) {
        let completion = continuation
        continuation = nil
        completion?.resume(throwing: error)
    }
    func finish(page: BoazHostPage, id: UInt64, status: BoazHostCaptureStatus, data: Data?, oversized: Bool) {
        guard continuation != nil else { return }
        if cancelled { finishCancellation(); return }
        guard page == self.page, id == self.id else { fail(ChromiumCaptureError.identityMismatch); return }
        let error: Error?
        switch status {
        case BOAZ_CAPTURE_SUCCESS: error = nil
        case BOAZ_CAPTURE_INVALID_TARGET: error = ChromiumCaptureError.invalidTarget
        case BOAZ_CAPTURE_NAVIGATION: error = ChromiumCaptureError.navigation
        case BOAZ_CAPTURE_CLOSED: error = ChromiumCaptureError.closed
        case BOAZ_CAPTURE_RENDERER_FAILED: error = ChromiumCaptureError.rendererFailed
        case BOAZ_CAPTURE_TIMEOUT: error = ChromiumCaptureError.timeout
        case BOAZ_CAPTURE_BUSY: error = ChromiumCaptureError.busy
        case BOAZ_CAPTURE_TOO_LARGE: error = ChromiumCaptureError.tooLarge
        case BOAZ_CAPTURE_CANCELLED: error = CancellationError()
        case BOAZ_CAPTURE_FAILED: error = ChromiumCaptureError.failed
        default: error = ChromiumCaptureError.unknownStatus(status.rawValue)
        }
        if let error { fail(error); return }
        guard !oversized else { fail(ChromiumCaptureError.tooLarge); return }
        guard let data, data.starts(with: signature) else {
            fail(ChromiumCaptureError.malformedResult); return
        }
        let completion = continuation
        continuation = nil
        completion?.resume(returning: data)
    }
}
#endif
