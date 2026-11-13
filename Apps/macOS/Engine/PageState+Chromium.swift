#if BOAZ_CHROMIUM
import Foundation

extension PageState {
    static func install(on adapter: ChromiumEnginePageAdapter) async throws {
        let script = trackingScript(report: "window.__boazLatestPageState = state;")
        _ = try await executePageState(on: adapter,
            function: "() => { \(script) return null; }", arguments: [:])
    }

    static func read(_ adapter: ChromiumEnginePageAdapter) async -> PageState? {
        guard let value = try? await executePageState(on: adapter,
            function: "() => window.__boazPageState?.read() ?? null", arguments: [:]),
              case .string(let json) = value, let place = Place(json: json),
              place.url == adapter.state.url else { return nil }
        return PageState(place: place, savedAt: .now)
    }

    /// Starts restoration; isolated execution does not await the JavaScript promise.
    func beginRestore(on adapter: ChromiumEnginePageAdapter) async throws {
        guard url == adapter.state.url else { throw ChromiumTrustedScriptError.identityMismatch }
        let encoded = try JSONDecoder().decode(EngineJavaScriptValue.self, from: JSONEncoder().encode(place))
        _ = try await Self.executePageState(on: adapter, function: """
            ({place}) => {
                if (place.url === location.href) window.__boazPageState?.restore(place);
                return null;
            }
            """, arguments: ["place": encoded])
    }

    /// Dispatches the return operation without claiming its eventual completion.
    static func returnToPlace(_ adapter: ChromiumEnginePageAdapter) async throws {
        _ = try await executePageState(on: adapter, function: """
            () => { window.__boazPageState?.returnToPlace(); return null; }
            """, arguments: [:])
    }

    private static func executePageState(on adapter: ChromiumEnginePageAdapter,
        function: String, arguments: [String: EngineJavaScriptValue]) async throws -> EngineJavaScriptValue {
        try Task.checkCancellation()
        let navigation = adapter.state.navigationID
        let url = adapter.state.url
        guard adapter.state.lifecycle == .active else { throw EnginePageError.unavailable }
        let value = try await adapter.executeTrusted(function: function, arguments: arguments)
        try Task.checkCancellation()
        guard adapter.state.lifecycle == .active, adapter.state.navigationID == navigation,
              adapter.state.url == url else { throw ChromiumTrustedScriptError.identityMismatch }
        return value
    }
}
#endif
