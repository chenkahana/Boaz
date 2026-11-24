#if BOAZ_CHROMIUM
import Foundation

/// What Boaz keeps of a page past the live-page budget: the page itself, frozen, and before it has to close, the
/// document as presented, saved as MHTML (`TabSnapshots`).
extension ChromiumEnginePageAdapter {
    /// Freezes the page while it's hidden (Chromium's page lifecycle: its tasks stop, its DOM stays), or thaws it.
    /// Showing a page thaws it.
    func setFrozen(_ frozen: Bool) throws {
        try requireOpen()
        guard let set = api.set_page_frozen else { throw EnginePageError.incompatibleBridge }
        try check(set(handle, frozen ? 1 : 0))
    }

    /// Writes the page as presented to `file` (an .mhtml in an existing directory) and returns its size.
    func saveMHTML(to file: URL) async throws -> Int64 {
        try requireOpen()
        guard let save = api.save_mhtml else { throw EnginePageError.incompatibleBridge }
        let navigation = state.navigationID
        let reply = ChromiumSnapshotReply<Int64>()
        let size = try await withCheckedThrowingContinuation { continuation in
            reply.continuation = continuation
            let context = Unmanaged.passRetained(reply).toOpaque()
            let result = file.path.withCString { path in
                save(handle, reply.id, path, { context, _, _, status, size in
                    guard let context else { return }
                    MainActor.assumeIsolated {
                        Unmanaged<ChromiumSnapshotReply<Int64>>.fromOpaque(context).takeRetainedValue()
                            .finish(status, size)
                    }
                }, context)
            }
            if result != BOAZ_HOST_OK {
                Unmanaged<ChromiumSnapshotReply<Int64>>.fromOpaque(context).release()
                do { try check(result) } catch { reply.fail(error) }
            }
        }
        guard state.navigationID == navigation else { throw ChromiumCaptureError.navigation }
        return size
    }

    /// Where the page is scrolled, in CSS pixels, read from its layout: it works on a saved page, whose scripts are off.
    func scrollPosition() async throws -> CGPoint {
        try requireOpen()
        guard let read = api.read_scroll_position else { throw EnginePageError.incompatibleBridge }
        let reply = ChromiumSnapshotReply<CGPoint>()
        return try await withCheckedThrowingContinuation { continuation in
            reply.continuation = continuation
            let context = Unmanaged.passRetained(reply).toOpaque()
            let result = read(handle, reply.id, { context, _, _, status, x, y in
                guard let context else { return }
                MainActor.assumeIsolated {
                    Unmanaged<ChromiumSnapshotReply<CGPoint>>.fromOpaque(context).takeRetainedValue()
                        .finish(status, CGPoint(x: x, y: y))
                }
            }, context)
            if result != BOAZ_HOST_OK {
                Unmanaged<ChromiumSnapshotReply<CGPoint>>.fromOpaque(context).release()
                do { try check(result) } catch { reply.fail(error) }
            }
        }
    }
}

@MainActor private final class ChromiumSnapshotReply<Value: Sendable> {
    let id = ChromiumSnapshotRequests.next()
    var continuation: CheckedContinuation<Value, Error>?

    func fail(_ error: Error) {
        let completion = continuation
        continuation = nil
        completion?.resume(throwing: error)
    }

    func finish(_ status: BoazHostCaptureStatus, _ value: Value) {
        switch status {
        case BOAZ_CAPTURE_SUCCESS:
            let completion = continuation
            continuation = nil
            completion?.resume(returning: value)
        case BOAZ_CAPTURE_NAVIGATION: fail(ChromiumCaptureError.navigation)
        case BOAZ_CAPTURE_CLOSED: fail(ChromiumCaptureError.closed)
        case BOAZ_CAPTURE_TIMEOUT: fail(ChromiumCaptureError.timeout)
        case BOAZ_CAPTURE_BUSY: fail(ChromiumCaptureError.busy)
        default: fail(ChromiumCaptureError.failed)
        }
    }
}

@MainActor private enum ChromiumSnapshotRequests {
    private static var last: UInt64 = 0
    static func next() -> UInt64 {
        precondition(last < UInt64.max)
        last += 1
        return last
    }
}
#endif
