import FolioKit
import SwiftUI
import UIKit

/// First-run setup, full screen on the cover screen and unfolded: welcome, sync, default browser, done.
/// Arc, Chrome and Safari data reaches the iPhone through sync from the Mac.
struct OnboardingView: View {
    // No default-browser step yet: iOS only offers "Default Browser App" to apps Apple has granted the
    // com.apple.developer.web-browser entitlement, which Folio doesn't have.
    enum Step: Int, CaseIterable { case welcome, sync, done }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var step = Step.welcome
    @State private var forward = true
    @State private var finished = false

    var body: some View {
        ScrollView {
            page
                .id(step)
                .transition(Onboarding.pageTransition(forward: forward, reduceMotion: reduceMotion))
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center)
        .safeAreaInset(edge: .bottom) { footer }
        .background(Theme.hero.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .sensoryFeedback(.selection, trigger: step)
        .sensoryFeedback(.success, trigger: finished)
    }

    /// The hero shrinks on short screens (cover screen in landscape) and on the middle pages.
    private func heroSize(large: Bool) -> CGFloat {
        verticalSizeClass == .compact ? 64 : (large ? 128 : 80)
    }

    // MARK: Pages

    @ViewBuilder private var page: some View {
        VStack(spacing: 24) {
            switch step {
            case .welcome:
                OnboardingHero(size: heroSize(large: true))
                OnboardingHeading(title: "Welcome to Folio",
                                  message: "Your spaces, pins and tabs, in step on your iPhone and Mac.")
            case .sync:
                OnboardingHero(size: heroSize(large: false))
                OnboardingHeading(title: "Your library syncs with iCloud",
                                  message: "Spaces, pins and tabs stay in step with Folio on your Mac, including whatever you brought in from Arc, Chrome or Safari there.")
                SyncCard()
            case .done:
                OnboardingHero(size: heroSize(large: true))
                OnboardingHeading(title: "You're all set",
                                  message: "Tap search to open your first tab.")
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 14) {
            OnboardingDots(count: Step.allCases.count, index: step.rawValue)
            Button(action: primaryAction) {
                Text(primary).font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            if let secondary {
                Button(secondary) { step == .welcome ? finish() : go(by: 1) }
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
    }

    private var primary: String {
        switch step {
        case .welcome: "Get Started"
        case .sync: "Continue"
        case .done: "Start Browsing"
        }
    }

    private var secondary: String? {
        switch step {
        case .welcome: "Skip Setup"
        case .sync: "Skip"
        case .done: nil
        }
    }

    private func primaryAction() {
        if step == .done { finish() } else { go(by: 1) }
    }

    private func go(by delta: Int) {
        guard let next = Step(rawValue: step.rawValue + delta) else { return }
        forward = delta > 0
        // Let the outgoing page pick up the new direction before it animates out.
        DispatchQueue.main.async { withAnimation(Onboarding.spring) { step = next } }
    }

    private func finish() {
        finished = true
        Onboarding.markCompleted()
        if let store = model.store { try? StarterLibrary.finishSetup(store, syncing: model.sync?.isConnected == true) }
        model.showOnboarding = false
    }
}

/// Live iCloud status with a checkmark once the library is up to date; a folder picker only when iCloud can't sync.
private struct SyncCard: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var message: String?

    var body: some View {
        if let sync = model.sync {
            VStack(spacing: 14) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sync.folderURL.map { "Syncing through \($0.lastPathComponent)" } ?? "iCloud Sync").font(.headline)
                        Text(message ?? sync.status.summary).font(.subheadline).foregroundStyle(.white.opacity(0.75))
                    }
                } icon: {
                    Image(systemName: sync.status.systemImage)
                        .foregroundStyle(sync.status.isUpToDate ? Color.green : Color.white.opacity(0.8))
                        .symbolEffect(.rotate, isActive: sync.status == .syncing)
                        .contentTransition(.symbolEffect(.replace))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(.smooth, value: sync.status)
                if sync.offersFolder {
                    Button { picking = true } label: {
                        Text(sync.folderURL == nil ? "Sync Through a Folder…" : "Change Folder…")
                            .font(.body.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.glass)
                }
            }
            .padding(18)
            .foregroundStyle(.white)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .syncFolderImporter(isPresented: $picking, sync: sync, message: $message)
            .sensoryFeedback(.success, trigger: sync.status.isUpToDate) { _, ready in ready }
        }
    }
}

extension View {
    /// Picks the fallback sync folder (Settings and first-run setup); `message` explains a folder that can't be used.
    func syncFolderImporter(isPresented: Binding<Bool>, sync: LibrarySync, message: Binding<String?>) -> some View {
        fileImporter(isPresented: isPresented, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                Task {
                    do { try await sync.setFolder(url); message.wrappedValue = nil }
                    catch { message.wrappedValue = "Couldn't use that folder: \(error.localizedDescription)" }
                }
            case .failure(let error):
                message.wrappedValue = error.localizedDescription
            }
        }
    }
}
