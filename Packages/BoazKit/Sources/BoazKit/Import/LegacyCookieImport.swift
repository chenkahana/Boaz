import Foundation

/// Decides, once per launch, what to do with one source of the previous Boaz's WebKit cookies. Chromium keeps a
/// cookie it can't encrypt (a denied Keychain prompt) in memory only, so an import counts as done only once a later
/// launch finds what it imported in the profile's cookie file on disk.
public enum LegacyCookieImport {
    /// Launches that may check and import again before Boaz gives up, leaving the old cookies where they are.
    public static let attemptLimit = 10
    /// Imported cookies remembered for the check on the next launch: any one of them on disk is enough.
    static let rememberedKeys = 50

    /// A cookie's identity in Chromium's store: importing never replaces a cookie with the same one.
    public struct Key: Hashable, Codable, Sendable {
        public var host: String, name: String, path: String
        public init(host: String, name: String, path: String) { self.host = host; self.name = name; self.path = path }
    }

    public struct State: Equatable, Codable, Sendable {
        public enum Phase: String, Codable, Sendable { case new, pending, done, stopped }
        public var phase: Phase
        public var attempts: Int
        /// Some of the cookies the last attempt imported; empty for one done before Boaz checked the disk.
        public var imported: [Key]

        public init(phase: Phase = .new, attempts: Int = 0, imported: [Key] = []) {
            self.phase = phase; self.attempts = attempts; self.imported = imported
        }

        /// The state saved as `data`, or for a source the old one-time marker closed, one still to be checked.
        public init(stored data: Data?, closedByOldMarker: Bool) {
            if let data, let state = try? JSONDecoder().decode(State.self, from: data) { self = state }
            else { self = closedByOldMarker ? State(phase: .pending) : State() }
        }

        public var stored: Data { (try? JSONEncoder().encode(self)) ?? Data() }
        public var isFinished: Bool { phase == .done || phase == .stopped }
    }

    public enum Action: Equatable, Sendable {
        /// Nothing to do this launch.
        case none
        /// Import these, by index into the source's cookies.
        case importCookies([Int])
    }

    /// - Parameters:
    ///   - source: the source's unexpired cookies, as read this launch.
    ///   - excluded: cookies a source that wins over this one is importing this launch.
    ///   - destination: the profile's cookies on disk, or nil when its cookie file couldn't be read.
    public static func plan(_ state: State, source: [Key], excluded: Set<Key> = [],
                            destination: Set<Key>?) -> (action: Action, state: State) {
        guard !state.isFinished else { return (.none, state) }
        let candidates = source.indices.filter { !excluded.contains(source[$0]) }
        if candidates.isEmpty { return (.none, State(phase: .done, attempts: state.attempts)) }
        let attempts = state.attempts + 1
        guard let destination else {
            return (.none, State(phase: attempts >= attemptLimit ? .stopped : .pending, attempts: attempts,
                                 imported: state.imported))
        }
        if state.phase == .pending {
            let check = state.imported.isEmpty ? candidates.map { source[$0] } : state.imported
            if check.contains(where: destination.contains) {
                return (.none, State(phase: .done, attempts: state.attempts, imported: state.imported))
            }
        }
        let missing = candidates.filter { !destination.contains(source[$0]) }
        if missing.isEmpty { return (.none, State(phase: .done, attempts: state.attempts)) }
        if state.attempts >= attemptLimit { return (.none, State(phase: .stopped, attempts: state.attempts)) }
        return (.importCookies(missing),
                State(phase: .pending, attempts: attempts, imported: missing.prefix(rememberedKeys).map { source[$0] }))
    }
}
