import SwiftUI
import BoazKit

/// A spinner that follows `SpinnerGate`: nothing for the first 200 ms of a load, then held for at least 300 ms.
struct DelayedProgressView: View {
    let isLoading: Bool
    var title: LocalizedStringKey?
    @State private var gate = SpinnerGate()
    @State private var visible = false

    var body: some View {
        Group {
            if visible {
                if let title { ProgressView(title) } else { ProgressView() }
            }
        }
        .task(id: isLoading) {
            gate.setLoading(isLoading, at: ProcessInfo.processInfo.systemUptime)
            while !Task.isCancelled {
                let now = ProcessInfo.processInfo.systemUptime
                visible = gate.isVisible(at: now)
                guard let wait = gate.nextChange(at: now) else { return }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }
}
