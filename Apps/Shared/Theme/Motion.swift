import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Boaz's motion tokens (docs/design.md). Views and models name a token instead of writing a curve, and the token
/// reads Reduce Motion itself: with it on, anything that would move becomes a short cross-fade.
enum Motion {
    /// Hover, press, selection, symbol swaps and small toggles. Nothing travels, so Reduce Motion keeps it.
    case quick
    /// Panels and popovers in and out, list inserts and removals, toasts, split open and close.
    case standard
    /// Presenting a hero: carousel, page menu, command bar, space switch, peek.
    case emphasized
    /// Anything a finger or trackpad lets go of; `velocity` is the release speed ÷ the distance left to travel.
    case gesture(velocity: Double)

    var animation: Animation { animation(reduceMotion: Self.reduceMotion) }

    func animation(reduceMotion: Bool) -> Animation {
        switch (self, reduceMotion) {
        case (.quick, _): Self.quickCurve
        case (.standard, false): Self.standardCurve
        case (.emphasized, false): Self.emphasizedCurve
        case let (.gesture(velocity), false):
            .interpolatingSpring(duration: 0.42, bounce: 0.1, initialVelocity: velocity)
        case (.standard, true): .easeInOut(duration: 0.2)
        case (.emphasized, true): .easeInOut(duration: 0.25)
        case (.gesture, true): .easeOut(duration: 0.2)
        }
    }

    #if os(macOS)
    private static let quickCurve = Animation.smooth(duration: 0.2)
    private static let standardCurve = Animation.smooth(duration: 0.25)
    private static let emphasizedCurve = Animation.spring(duration: 0.4, bounce: 0.1)
    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    #else
    private static let quickCurve = Animation.snappy(duration: 0.2)
    private static let standardCurve = Animation.smooth(duration: 0.3)
    private static let emphasizedCurve = Animation.spring(duration: 0.45, bounce: 0.12)
    static var reduceMotion: Bool { UIAccessibility.isReduceMotionEnabled }
    #endif
}

/// `withAnimation` with a motion token, for models and actions outside a view.
@discardableResult
func withMotion<Result>(_ motion: Motion, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(motion.animation, body)
}

extension View {
    /// `.animation(_:value:)` with a motion token.
    func motion(_ motion: Motion, value: some Equatable) -> some View {
        modifier(MotionModifier(motion: motion, value: value))
    }
}

private struct MotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let motion: Motion
    let value: Value

    func body(content: Content) -> some View {
        content.animation(motion.animation(reduceMotion: reduceMotion), value: value)
    }
}
