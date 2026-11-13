#if BOAZ_CHROMIUM
import Foundation

@MainActor
final class ChromiumCapturedDocument {
    let origin: URL
    let page: BoazHostPage
    let profile: EngineProfileIdentity
    let navigationID: UInt64
    private let owner: ChromiumEnginePageAdapter
    private var token: BoazHostDocument?

    init(owner: ChromiumEnginePageAdapter, origin: URL, token: BoazHostDocument) {
        self.owner = owner
        self.origin = origin
        page = owner.handle
        profile = owner.profile
        navigationID = owner.state.navigationID
        self.token = token
    }

    isolated deinit { release() }

    func release() {
        guard let token else { return }
        self.token = nil
        _ = owner.api.release_document?(page, token)
    }

    func validatedToken(for adapter: ChromiumEnginePageAdapter) throws -> BoazHostDocument {
        guard owner === adapter, page == adapter.handle, profile == adapter.profile,
              let token else { throw ChromiumTrustedScriptError.invalidTarget }
        guard adapter.state.lifecycle == .active else { throw ChromiumTrustedScriptError.closed }
        guard navigationID == adapter.state.navigationID else { throw ChromiumTrustedScriptError.navigation }
        return token
    }

    func consumed() { token = nil }
}
#endif
