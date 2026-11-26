import Foundation

/// Which live pages a browser closes to save memory, and how many it keeps. Pure: the apps gather what each page is
/// doing and close what this returns.
public enum PageResidencyPolicy {
    /// A live page as the policy sees it.
    public struct Page: Equatable, Sendable {
        public var id: String
        /// Playing, in Picture in Picture, recording or in full screen: closing it would stop what the user hears or sees.
        public var isBusy: Bool
        public var isPrivate: Bool
        /// The user typed into it since it last loaded (a half-filled form).
        public var hasInput: Bool

        public init(id: String, isBusy: Bool = false, isPrivate: Bool = false, hasInput: Bool = false) {
            self.id = id
            self.isBusy = isBusy
            self.isPrivate = isPrivate
            self.hasInput = hasInput
        }
    }

    /// The iPhone's live-page limit: two pages per gigabyte of memory, from 6 to 16.
    public static func phoneLimit(physicalMemory: UInt64) -> Int {
        let gigabytes = Int((Double(physicalMemory) / 1_000_000_000).rounded())
        return min(max(gigabytes * 2, 6), 16)
    }

    /// The pages to close until `target` of the `recency` pages remain. `recency` runs from least to most recently
    /// used. Pages in `kept` (on screen) and busy pages never close. Normal pages close before private ones, which
    /// come back from nothing on disk, and within each, pages without typed input go first. With `closesInput` false
    /// (the plain limit, as opposed to a memory warning), a page with typed input stays however many are open.
    public static func pagesToClose(_ recency: [Page], target: Int, keeping kept: Set<String>,
                                    closesInput: Bool) -> [String] {
        var excess = recency.count - target
        guard excess > 0 else { return [] }
        let candidates = recency.filter { !kept.contains($0.id) && !$0.isBusy && (closesInput || !$0.hasInput) }
        let order = candidates.enumerated().sorted { a, b in
            let rankA = (a.element.isPrivate ? 2 : 0) + (a.element.hasInput ? 1 : 0)
            let rankB = (b.element.isPrivate ? 2 : 0) + (b.element.hasInput ? 1 : 0)
            return rankA != rankB ? rankA < rankB : a.offset < b.offset
        }
        var close: [String] = []
        for (_, page) in order where excess > 0 {
            close.append(page.id)
            excess -= 1
        }
        return close
    }
}

/// When a page whose content the system ended loads again on its own: once per ending, and not at all when the
/// ending before it was less than a minute earlier. A page that keeps ending stays on its failure screen, with
/// Try Again, rather than reloading in a loop. Loads finishing never reset it.
public struct CrashRestoreBudget: Sendable {
    public static let quietPeriod: TimeInterval = 60

    private var lastEnded: [String: Date] = [:]
    private var owed: Set<String> = []

    public init() {}

    /// Records that `id`'s content ended at `date`. Returns whether it is owed an automatic restore.
    @discardableResult
    public mutating func contentEnded(_ id: String, at date: Date) -> Bool {
        let tooSoon = lastEnded[id].map { date.timeIntervalSince($0) < Self.quietPeriod } ?? false
        lastEnded[id] = date
        if tooSoon { owed.remove(id) } else { owed.insert(id) }
        return !tooSoon
    }

    /// Whether `id` is owed a restore; a yes spends it.
    public mutating func takeRestore(_ id: String) -> Bool { owed.remove(id) != nil }

    /// Whether `id` waits for its restore (its content ended, and it hasn't loaded again since).
    public func owesRestore(_ id: String) -> Bool { owed.contains(id) }

    /// Drops a closed tab's record.
    public mutating func forget(_ id: String) {
        lastEnded[id] = nil
        owed.remove(id)
    }
}
