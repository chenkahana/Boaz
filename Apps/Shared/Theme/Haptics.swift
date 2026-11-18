import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Boaz's haptic map (docs/design.md). One haptic per meaningful moment: a commit, a threshold crossed, a snap. Never
/// on scrolling, hover or a plain tap that already shows a press. Call sites name the moment; the feedback for it is
/// chosen here.
enum Haptics {
    #if os(macOS)
    /// A width or divider snaps into place: the sidebar at its limits, the split at half.
    case snap
    /// A dragged row moves into a new slot or over a folder.
    case slotChanged
    /// A space swipe passes its commit point.
    case spaceCommitted
    /// A drop lands.
    case dropAccepted

    /// Plays on the trackpad (a mouse has no haptics). For drags, which aren't a SwiftUI state change.
    func play() {
        let pattern: NSHapticFeedbackManager.FeedbackPattern = switch self {
        case .snap: .alignment
        case .slotChanged, .dropAccepted: .generic
        case .spaceCommitted: .levelChange
        }
        let time: NSHapticFeedbackManager.PerformanceTime = switch self {
        case .snap, .spaceCommitted: .now
        case .slotChanged, .dropAccepted: .drawCompleted
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: time)
    }
    #else
    /// The carousel or the bar moves to another tab.
    case tabChanged
    /// A back or forward edge swipe commits.
    case pageTurned
    /// Pull to refresh passes the point where letting go reloads.
    case refreshArmed
    /// A tab closed or archived, with Undo on offer.
    case tabClosed
    /// An archive flick passes its commit threshold.
    case archiveCommitted
    /// A panel's drag-to-dismiss passes its threshold.
    case dismissCommitted

    /// For `.sensoryFeedback(_:trigger:)`, triggered by the same state change that drives the visual.
    var feedback: SensoryFeedback {
        switch self {
        case .tabChanged, .pageTurned: .selection
        case .refreshArmed, .dismissCommitted: .impact(weight: .light)
        case .tabClosed, .archiveCommitted: .impact(weight: .medium)
        }
    }
    #endif
}
