#if BOAZ_CHROMIUM
import SwiftUI

@MainActor
struct ChromiumLoadFailureView: View {
    let adapter: ChromiumEnginePageAdapter
    @State private var retryError: String?

    private var crashed: Bool { adapter.state.lifecycle == .crashed }
    private var offline: Bool { adapter.state.loadFailure?.code == -106 }
    private var canRetry: Bool {
        adapter.state.lifecycle == .active || crashed
    }

    var body: some View {
        ContentUnavailableView {
            Label(crashed ? "This Page Stopped Responding" :
                  (offline ? "You're Offline" : "Couldn't Load This Page"),
                  systemImage: crashed ? "exclamationmark.triangle" :
                    (offline ? "wifi.slash" : "globe"))
        } description: {
            VStack(spacing: 8) {
                if crashed {
                    Text("Reload the page to continue.")
                } else if offline {
                    Text("Check your internet connection, then try again.")
                } else if let host = adapter.state.loadFailure?.url?.host() {
                    Text("Boaz couldn't load the page from \(host).")
                } else {
                    Text("The page could not be loaded. Try again.")
                }
                if let retryError { Text(retryError).foregroundStyle(.red) }
            }
        } actions: {
            Button(crashed ? "Reload Page" : "Try Again") { retry() }
                .buttonStyle(.glass)
                .disabled(!canRetry || adapter.state.isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .onChange(of: adapter.state.loadFailure) { retryError = nil }
        .onChange(of: adapter.state.navigationID) { retryError = nil }
    }

    private func retry() {
        guard canRetry else { return }
        retryError = nil
        do {
            if let url = adapter.state.loadFailure?.url {
                try adapter.navigate(to: url)
            } else {
                try adapter.reload()
            }
        } catch {
            retryError = "Boaz couldn't retry this page. Please try again."
        }
    }
}
#endif
