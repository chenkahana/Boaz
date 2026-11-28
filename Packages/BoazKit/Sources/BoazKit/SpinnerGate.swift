import Foundation

/// Decides when a loading spinner may be on screen. A load that finishes inside `showDelay` never shows one, and a
/// spinner that did appear stays at least `minVisible`, so it never flashes. Time is passed in, so the rule is
/// deterministic and unit-testable. Values follow the Nielsen Norman response-time guidance in plan/design-principles.md.
public struct SpinnerGate: Sendable, Equatable {
    public let showDelay: TimeInterval
    public let minVisible: TimeInterval
    private var loading = false
    private var loadingSince: TimeInterval?
    private var shownAt: TimeInterval?

    public init(showDelay: TimeInterval = 0.2, minVisible: TimeInterval = 0.3) {
        self.showDelay = showDelay
        self.minVisible = minVisible
    }

    public mutating func setLoading(_ isLoading: Bool, at now: TimeInterval) {
        guard isLoading != loading else { return }
        loading = isLoading
        if isLoading {
            if shownAt == nil { loadingSince = now }
        } else {
            loadingSince = nil
        }
    }

    public mutating func isVisible(at now: TimeInterval) -> Bool {
        if shownAt == nil, loading, let since = loadingSince, now - since >= showDelay {
            shownAt = since + showDelay
        }
        guard let shown = shownAt else { return false }
        if loading || now - shown < minVisible { return true }
        shownAt = nil
        return false
    }

    /// Seconds until the answer of `isVisible` can change with no new input, or nil when it is settled.
    public func nextChange(at now: TimeInterval) -> TimeInterval? {
        if let shown = shownAt { return loading ? nil : max(0, shown + minVisible - now) }
        if loading, let since = loadingSince { return max(0, since + showDelay - now) }
        return nil
    }
}
