import FolioKit
import SwiftUI
#if os(iOS)
import UIKit
#endif

/// The iCloud account behind sync, as setup and Settings present it. Folio has no account of its own: signing in
/// means signing in to iCloud, which only the system can do, so "Sign In" opens Settings.
enum ICloudSignIn {
    /// The device's own name for where the Apple Account lives.
    static var settingsName: String {
        #if os(macOS)
        "System Settings"
        #else
        "Settings"
        #endif
    }

    static var otherDevice: String {
        #if os(macOS)
        "iPhone"
        #else
        "Mac"
        #endif
    }

    /// The system's Apple Account settings on macOS; on iOS, Settings (there's no public link to the account page).
    /// Opened through SwiftUI's `openURL`, which the app extensions that share this file can also use.
    static var settingsURL: URL? {
        #if os(macOS)
        URL(string: "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings")
        #else
        URL(string: UIApplication.openSettingsURLString)
        #endif
    }

    static func needsSignIn(_ status: LibrarySync.Status) -> Bool { status == .signedOut }

    static func title(_ status: LibrarySync.Status, folder: URL?) -> String {
        if let folder { return "Syncing through \(folder.lastPathComponent)" }
        return switch status {
        case .starting: "Checking your iCloud account…"
        case .syncing: "Signed in to iCloud"
        case .upToDate: "Signed in to iCloud"
        case .signedOut: "Not signed in to iCloud"
        case .unavailable: "iCloud isn't available"
        case .error: "iCloud sync needs attention"
        }
    }

    /// One line under the title; `library` describes what's synced, e.g. "3 spaces, 24 tabs".
    static func detail(_ status: LibrarySync.Status, library: String?) -> String {
        switch status {
        case .starting: "Folio syncs through your private iCloud. Nobody else, including us, can see it."
        case .syncing: "Bringing your library up to date…"
        case .upToDate: library.map { "In step with your \(otherDevice) · \($0)" } ?? "In step with your \(otherDevice)."
        case .signedOut:
            #if os(macOS)
            "Sign in with your Apple Account in System Settings, then come back here."
            #else
            "In Settings, tap Apple Account at the top and sign in, then come back to Folio."
            #endif
        case .unavailable(let reason): reason
        case .error(let message): message
        }
    }
}

/// Live iCloud account and sync state with a sign-in action, for setup's first page and Settings.
/// `folderAction` is the platform's fallback-folder picker, offered only while iCloud can't sync.
struct ICloudSignInCard<FolderAction: View>: View {
    @Environment(\.openURL) private var openURL
    let sync: LibrarySync
    /// What's in the library ("3 spaces, 24 tabs"), shown once it's in sync.
    var library: String?
    var message: String?
    /// Off where the screen already has its own sign-in button (setup's footer).
    var showsSignInButton = true
    @ViewBuilder var folderAction: () -> FolderAction

    var body: some View {
        let status = sync.status
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon(status))
                    .font(.title2)
                    .foregroundStyle(status.isUpToDate || status == .syncing ? Color.green : Color.white.opacity(0.85))
                    .symbolEffect(.rotate, isActive: status == .syncing || status == .starting)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 32)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ICloudSignIn.title(status, folder: sync.folderURL)).font(.headline)
                    Text(message ?? ICloudSignIn.detail(status, library: library))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if showsSignInButton, ICloudSignIn.needsSignIn(status) {
                Button("Sign In to iCloud", systemImage: "person.crop.circle") {
                    if let url = ICloudSignIn.settingsURL { openURL(url) }
                }
                    .buttonStyle(.glassProminent)
                    .tint(.white.opacity(0.25))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if sync.offersFolder { folderAction() }
        }
        .padding(18)
        .foregroundStyle(.white)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .animation(.smooth, value: status)
        .sensoryFeedback(.success, trigger: status.isUpToDate) { _, ready in ready }
    }

    private func icon(_ status: LibrarySync.Status) -> String {
        switch status {
        case .starting: "arrow.triangle.2.circlepath.icloud"
        case .syncing, .upToDate: "checkmark.icloud.fill"
        default: status.systemImage
        }
    }
}

extension Sidebar {
    /// "3 spaces, 24 tabs", for the sign-in card. Nil for an empty library.
    var syncSummary: String? {
        let spaceCount = spaces.count
        let tabs = items.filter { $0.kind == .tab }.count
        guard spaceCount + tabs > 0 else { return nil }
        let s = spaceCount == 1 ? "1 space" : "\(spaceCount) spaces"
        let t = tabs == 1 ? "1 tab" : "\(tabs) tabs"
        return "\(s), \(t)"
    }
}
