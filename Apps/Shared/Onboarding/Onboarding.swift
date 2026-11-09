import BoazKit
import SwiftUI

/// First-run setup, shared by the Mac and iPhone flows.
enum Onboarding {
    static let completedKey = "onboardingCompleted"
    /// `-BoazResetOnboarding YES` shows the flow again without touching the library.
    static let resetArgument = "BoazResetOnboarding"

    /// Shown once, and never to people who already have their own spaces or tabs.
    static func shouldShow(_ store: BoazStore) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: resetArgument) { return true }
        guard !defaults.bool(forKey: completedKey) else { return false }
        if (try? StarterLibrary.hasUserContent(store)) == true {
            markCompleted()
            return false
        }
        return true
    }

    static func markCompleted() { UserDefaults.standard.set(true, forKey: completedKey) }

    static let spring = Animation.spring(response: 0.5, dampingFraction: 0.86)

    /// Pages slide in the direction of travel; with Reduce Motion they only fade.
    static func pageTransition(forward: Bool, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }
}

/// The app icon floating on the brand gradient.
struct OnboardingHero: View {
    var size: CGFloat = 112
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        icon
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            #if os(iOS)
            // The macOS app icon arrives already masked; the iOS artwork is full-bleed, so give it the home-screen shape.
            .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
            #endif
            .shadow(color: Theme.indigo(12).opacity(0.45), radius: size / 5, y: size / 10)
            .offset(y: floating ? -size / 28 : 0)
            .animation(reduceMotion ? nil : .easeInOut(duration: 2.6).repeatForever(autoreverses: true), value: floating)
            .onAppear { floating = !reduceMotion }
            .accessibilityHidden(true)
    }

    private var icon: Image {
        #if os(macOS)
        Image(nsImage: NSApplication.shared.applicationIconImage)
        #else
        UIImage(named: "AppIcon-Preview").map { Image(uiImage: $0) } ?? Image(systemName: "eyes")
        #endif
    }
}

/// Step indicator; VoiceOver reads it as "Step 2 of 4".
struct OnboardingDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(.white.opacity(i == index ? 0.95 : 0.4))
                    .frame(width: i == index ? 18 : 6, height: 6)
            }
        }
        .animation(Onboarding.spring, value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}

/// Title and explanation at the top of each page.
struct OnboardingHeading: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
    }
}
