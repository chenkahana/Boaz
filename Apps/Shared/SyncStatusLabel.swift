import FolioKit
import SwiftUI

/// The live sync state: an iCloud symbol and one line of status.
struct SyncStatusLabel: View {
    let status: LibrarySync.Status

    var body: some View {
        Label {
            Text(status.summary)
        } icon: {
            Image(systemName: status.systemImage)
                .foregroundStyle(status.isUpToDate ? Color.green : Color.secondary)
                .symbolEffect(.rotate, isActive: status == .syncing)
                .contentTransition(.symbolEffect(.replace))
        }
        .animation(.smooth, value: status)
    }
}
