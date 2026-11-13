#if BOAZ_CHROMIUM
import Foundation
import Darwin

enum ChromiumTrustedScriptError: Error {
    case invalidTarget, navigation, closed, rendererFailed, timeout, invalidArgument, busy
    case identityMismatch, malformedResult, resultTooLarge
    case unknownStatus(UInt32)
}

extension ChromiumEnginePageAdapter {
    /// Accepts bundled application function source only, never page-provided code.
    /// The host supplies its isolated world, document validation and five-second timeout.
    func executeTrusted(function: String, arguments: [String: EngineJavaScriptValue]) async throws -> EngineJavaScriptValue {
        try Task.checkCancellation()
        guard state.lifecycle != .closed, state.lifecycle != .closing else { throw EnginePageError.closed }
        guard let capture = api.capture_document, let execute = api.execute_trusted,
              let release = api.release_document else { throw EnginePageError.incompatibleBridge }
        let argumentData: Data
        do { argumentData = try JSONEncoder().encode(arguments) }
        catch { throw ChromiumTrustedScriptError.invalidArgument }
        guard !function.isEmpty, function.utf16.count <= 32 * 1024,
              function.utf8.count <= 64 * 1024, argumentData.count <= 64 * 1024 else {
            throw ChromiumTrustedScriptError.invalidArgument
        }
        let argumentJSON = String(decoding: argumentData, as: UTF8.self)
        var document: BoazHostDocument = 0
        try check(capture(handle, &document))
        guard document != 0 else { throw ChromiumTrustedScriptError.invalidTarget }
        do {
            let value: EngineJavaScriptValue = try await withCheckedThrowingContinuation { continuation in
                let request = TrustedScriptRequest(page: handle, document: document, continuation: continuation)
                let context = Unmanaged.passRetained(request).toOpaque()
                let result = function.withCString { source in
                    argumentJSON.withCString { json in
                        execute(handle, document, source, function.utf8.count, json, argumentData.count,
                            { context, page, document, status, json in
                                guard let context else { return }
                                // Copy only the bounded borrowed result while still inside the callback.
                                let count = json.map { strnlen($0, 64 * 1024 + 1) }
                                let oversized = (count ?? 0) > 64 * 1024
                                let copied: Data? = !oversized ? json.flatMap { pointer in
                                    count.map { Data(bytes: pointer, count: $0) }
                                } : nil
                                MainActor.assumeIsolated {
                                    let request = Unmanaged<TrustedScriptRequest>.fromOpaque(context).takeRetainedValue()
                                    DispatchQueue.main.async {
                                        request.finish(page: page, document: document, status: status,
                                                       data: copied, oversized: oversized)
                                    }
                                }
                            }, context)
                    }
                }
                if result != BOAZ_HOST_OK {
                    // A rejected call promises no callback and has not consumed the token.
                    Unmanaged<TrustedScriptRequest>.fromOpaque(context).release()
                    _ = release(handle, document)
                    do { try check(result) }
                    catch { request.fail(error) }
                }
            }
            try Task.checkCancellation()
            return value
        } catch {
            // Accepted operations retain their completion until the host finishes or cancels.
            // Cancellation does not release a token already consumed by execution.
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
    }
}

@MainActor private final class TrustedScriptRequest {
    let page: BoazHostPage
    let document: BoazHostDocument
    private var continuation: CheckedContinuation<EngineJavaScriptValue, Error>?
    init(page: BoazHostPage, document: BoazHostDocument,
         continuation: CheckedContinuation<EngineJavaScriptValue, Error>) {
        self.page = page
        self.document = document
        self.continuation = continuation
    }
    func fail(_ error: Error) {
        let completion = continuation
        continuation = nil
        completion?.resume(throwing: error)
    }
    func finish(page: BoazHostPage, document: BoazHostDocument,
                status: BoazHostScriptStatus, data: Data?, oversized: Bool) {
        guard let completion = continuation else { return }
        continuation = nil
        do {
            guard page == self.page, document == self.document else { throw ChromiumTrustedScriptError.identityMismatch }
            switch status {
            case BOAZ_SCRIPT_SUCCESS: break
            case BOAZ_SCRIPT_INVALID_TARGET: throw ChromiumTrustedScriptError.invalidTarget
            case BOAZ_SCRIPT_NAVIGATION: throw ChromiumTrustedScriptError.navigation
            case BOAZ_SCRIPT_CLOSED: throw ChromiumTrustedScriptError.closed
            case BOAZ_SCRIPT_RENDERER_FAILED: throw ChromiumTrustedScriptError.rendererFailed
            case BOAZ_SCRIPT_TIMEOUT: throw ChromiumTrustedScriptError.timeout
            case BOAZ_SCRIPT_INVALID_ARGUMENT: throw ChromiumTrustedScriptError.invalidArgument
            case BOAZ_SCRIPT_BUSY: throw ChromiumTrustedScriptError.busy
            default: throw ChromiumTrustedScriptError.unknownStatus(status.rawValue)
            }
            guard !oversized else { throw ChromiumTrustedScriptError.resultTooLarge }
            guard let data else { throw ChromiumTrustedScriptError.malformedResult }
            let result: EngineJavaScriptValue
            do { result = try JSONDecoder().decode(EngineJavaScriptValue.self, from: data) }
            catch { throw ChromiumTrustedScriptError.malformedResult }
            completion.resume(returning: result)
        } catch {
            completion.resume(throwing: error)
        }
    }
}
#endif
