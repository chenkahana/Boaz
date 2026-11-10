import SwiftUI

/// Circular pull indicator: a ring that fills in as you pull, grows to "armed" at the
/// threshold (paired with a haptic from the caller), and spins while the page reloads.
struct PullToRefreshIndicator: View {
    let progress: CGFloat // 0...1+, how far past the pull distance we are relative to the threshold
    let armed: Bool
    let reloading: Bool
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.brand.opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: reloading ? 0.75 : min(progress, 1))
                .stroke(Theme.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(reloading ? (spin ? 360 : 0) : -90))
        }
        .frame(width: 26, height: 26)
        .scaleEffect(armed || reloading ? 1.1 : 0.85 + min(progress, 1) * 0.15)
        .opacity(reloading ? 1 : Double(min(progress, 1)))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: progress)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: armed)
        .animation(reloading ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: spin)
        .onChange(of: reloading, initial: true) { _, isReloading in spin = isReloading }
    }
}
