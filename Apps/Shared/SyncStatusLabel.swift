import BoazKit
import SwiftUI

/// The live sync state: an iCloud symbol and one line of status.
struct SyncStatusLabel: View {
    let status: LibrarySync.Status

    var body: some View {
        Label {
            // Signed out, the Sign In button beside this line says what to do; the line only says what's true.
            Text(ICloudSignIn.needsSignIn(status) ? ICloudSignIn.title(status, folder: nil) : status.summary)
        } icon: {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.isUpToDate ? Color.green : Color.secondary)
                .symbolEffect(.rotate, isActive: status == .syncing)
                .contentTransition(.symbolEffect(.replace))
        }
        .animation(.smooth, value: status)
    }
}
