import Foundation
import OSLog

/// Where a tab's page was scrolled: the window, and the inner scrollers that chat and mail sites scroll instead (their
/// root doesn't scroll). A page loaded again (unloaded to save memory, its process ended by the system, or after a
/// relaunch) goes back there. Read and put back by a script in its own content world, which pages can't see or call.
/// Lives in `Apps/Browser` so both apps compile it.
struct PageState: Codable, Equatable {
    /// Where the page was, as the script reads it.
    struct Place: Codable, Equatable {
        struct Offset: Codable, Equatable {
            /// A CSS selector for an inner scroller; nil for the window.
            var path: String?
            var top: Double
            var left: Double
            /// Within 4 px of the end: put back at the end, however much content arrived since (a chat's newest message).
            var atBottom: Bool
        }

        var url: URL
        var window: Offset
        /// The largest first, at most 8.
        var scrollers: [Offset]

        init?(json: String) {
            guard let place = try? JSONDecoder().decode(Self.self, from: Data(json.utf8)) else { return nil }
            self = place
        }
    }

    var place: Place
    var savedAt: Date

    var url: URL { place.url }

    /// The page at its very top, with no inner scroller moved: nothing to go back to.
    private var isAtStart: Bool {
        place.window.top == 0 && place.window.left == 0 && !place.window.atBottom && place.scrollers.isEmpty
    }

    // MARK: Store

    /// Each tab's state, by tab id: saved in one small file and kept a week, or (private browsing) only in memory.
    final class Store {
        private static let lifetime: TimeInterval = 7 * 86_400
        nonisolated private static let log = Logger(subsystem: "com.chenkahana.boaz", category: "page-state")
        /// Writes run in order, off the main thread.
        nonisolated private static let queue = DispatchQueue(label: "com.chenkahana.boaz.page-state", qos: .utility)

        private var states: [String: PageState]
        private let file: URL?

        /// Kept only in memory.
        init() {
            states = [:]
            file = nil
        }

        /// The states saved on this device, less those older than a week.
        private init(file: URL) {
            self.file = file
            let saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([String: PageState].self, from: $0) }
            states = (saved ?? [:]).filter { $0.value.savedAt > .now - Self.lifetime }
        }

        static func saved() -> Store {
            Store(file: URL.applicationSupportDirectory.appending(path: "Page States.json"))
        }

        subscript(tabID: String) -> PageState? { states[tabID] }

        /// A page back at its very top replaces the saved state with none. The same place is written again only
        /// once an hour, which keeps a tab in use from expiring.
        func set(_ state: PageState, for tabID: String) {
            let new = state.isAtStart ? nil : state
            if let old = states[tabID], let new, old.place == new.place, new.savedAt.timeIntervalSince(old.savedAt) < 3600 {
                return
            }
            guard states[tabID] != new else { return }
            states[tabID] = new
            save()
        }

        func remove(_ tabID: String) {
            guard states.removeValue(forKey: tabID) != nil else { return }
            save()
        }

        /// Forgets the tabs that are gone.
        func prune(keeping tabIDs: Set<String>) {
            let kept = states.filter { tabIDs.contains($0.key) }
            guard kept.count != states.count else { return }
            states = kept
            save()
        }

        /// Waits for the writes queued so far, before the app quits.
        static func flush() { queue.sync {} }

        private func save() {
            guard let file, let data = try? JSONEncoder().encode(states) else { return }
            Self.queue.async {
                do {
                    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                            withIntermediateDirectories: true)
                    try data.write(to: file, options: .atomic)
                } catch {
                    Self.log.error("Saving page states failed: \(String(describing: error))")
                }
            }
        }
    }
}
