import BoazKit
import SwiftUI
import UIKit

/// First-run setup, full screen on the cover screen and unfolded. It starts with signing in to iCloud, which is how
/// the library reaches the Mac and back; Arc, Chrome and Safari data comes to the iPhone through that sync.
struct OnboardingView: View {
    enum Step: Int, CaseIterable { case signIn, done }

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var step = Step.signIn
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
            case .signIn:
                OnboardingHero(size: heroSize(large: true))
                OnboardingHeading(title: "Welcome to Boaz",
                                  message: "Sign in to iCloud to keep your spaces, pins and tabs in step on your iPhone and Mac.")
                SignInCard()
            case .done:
                OnboardingHero(size: heroSize(large: true))
                OnboardingHeading(title: "You're all set", message: doneMessage)
            }
        }
    }

    private var status: LibrarySync.Status? { model.sync?.status }
    private var needsSignIn: Bool { status.map(ICloudSignIn.needsSignIn) ?? false }

    private var doneMessage: String {
        if status?.isUpToDate == true, model.sidebar.syncSummary != nil {
            return "Your library from iCloud is ready. Tap a tab, or search to open a new one."
        }
        return "Tap search to open your first tab."
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 14) {
            OnboardingDots(count: Step.allCases.count, index: step.rawValue)
            HStack(spacing: 12) {
                if step != .signIn {
                    Button("Back", systemImage: "chevron.left") { go(by: -1) }
                        .font(.headline)
                        .buttonStyle(.glass)
                }
                Button(action: primaryAction) {
                    Text(primary).font(.headline).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                // White on the brand color in both appearances (the app's tint is lighter in Dark Mode).
                .tint(Theme.brand)
            }
            .controlSize(.large)
            if let secondary {
                Button(secondary) { go(by: 1) }
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
        case .signIn: needsSignIn ? "Sign In to iCloud" : "Continue"
        case .done: "Start Browsing"
        }
    }

    private var secondary: String? {
        step == .signIn && needsSignIn ? "Continue Without Syncing" : nil
    }

    private func primaryAction() {
        switch step {
        case .signIn where needsSignIn: if let url = ICloudSignIn.settingsURL { UIApplication.shared.open(url) }
        case .signIn: go(by: 1)
        case .done: finish()
        }
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

/// The iCloud account and sync state; a folder picker only when iCloud can't sync.
private struct SignInCard: View {
    @Environment(AppModel.self) private var model
    @State private var picking = false
    @State private var message: String?

    var body: some View {
        if let sync = model.sync {
            ICloudSignInCard(sync: sync, library: model.sidebar.syncSummary, message: message,
                             showsSignInButton: false) {
                Button { picking = true } label: {
                    Text(sync.folderURL == nil ? "Sync Through a Folder Instead…" : "Change Folder…")
                        .font(.body.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glass)
            }
            .syncFolderImporter(isPresented: $picking, sync: sync, message: $message)
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
