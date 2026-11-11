#if SPARKLE
import Combine
import Sparkle
import SwiftUI

/// Sparkle, in the DMG build only (project-dmg.yml): checks the appcast on GitHub Releases once a day and installs
/// updates in place. The App Store build doesn't contain Sparkle; the App Store updates it.
@Observable
final class Updates {
    static let shared = Updates()

    /// Until project-dmg.yml carries the real public key, a build can't verify an update: no updater, no menu item.
    static let isConfigured = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
        .map { !$0.isEmpty && $0 != "SPARKLE_PUBLIC_ED_KEY_PLACEHOLDER" } ?? false

    private(set) var canCheck = false
    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    @ObservationIgnored private var canCheckObservation: AnyCancellable?

    private init() {
        controller = Self.isConfigured
            ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) : nil
        canCheckObservation = controller?.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canCheck in MainActor.assumeIsolated { self?.canCheck = canCheck } }
    }

    func check() { controller?.checkForUpdates(nil) }
}

/// Boaz › Check for Updates…, which also starts the updater (and its daily checks) when the menu is built at launch.
struct UpdateCommands: Commands {
    private let updates = Updates.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if Updates.isConfigured {
                Button("Check for Updates…") { updates.check() }.disabled(!updates.canCheck)
            }
        }
    }
}
#endif
