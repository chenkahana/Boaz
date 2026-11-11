#if SPARKLE
import Combine
import Sparkle
import SwiftUI

/// Sparkle, in the DMG build only (project-dmg.yml): checks the appcast on GitHub Releases once a day and installs
/// updates in place. The App Store build doesn't contain Sparkle; the App Store updates it.
@Observable
final class Updates {
    static let shared = Updates()

    private(set) var canCheck = false
    @ObservationIgnored private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                                                userDriverDelegate: nil)
    @ObservationIgnored private var canCheckObservation: AnyCancellable?

    private init() {
        canCheckObservation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] canCheck in MainActor.assumeIsolated { self?.canCheck = canCheck } }
    }

    func check() { controller.checkForUpdates(nil) }
}

/// Boaz › Check for Updates…, which also starts the updater (and its daily checks) when the menu is built at launch.
struct UpdateCommands: Commands {
    private let updates = Updates.shared

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updates.check() }.disabled(!updates.canCheck)
        }
    }
}
#endif
