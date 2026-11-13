#if BOAZ_CHROMIUM
import SwiftUI

@MainActor
struct ChromiumThrottlingControls: View {
    let adapter: ChromiumEnginePageAdapter
    @State private var preset = "custom"
    @State private var offline = false
    @State private var latency = 0.0
    @State private var downloadKB = -1.0
    @State private var uploadKB = -1.0
    @State private var cpu = 1.0

    var body: some View {
        DisclosureGroup("Network and CPU Throttling") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Network Preset", selection: $preset) {
                    Text("Custom").tag("custom")
                    Text("Offline").tag("offline")
                    Text("Slow: 400 ms, 100 KB/s down, 50 KB/s up").tag("slow")
                }
                Toggle("Offline", isOn: $offline)
                HStack {
                    number("Latency (ms)", value: $latency)
                    number("Download (KB/s)", value: $downloadKB)
                    number("Upload (KB/s)", value: $uploadKB)
                }
                Text("1 KB/s = 1,000 bytes/sec. Use -1 for unlimited bandwidth.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Apply Network") { applyNetwork() }
                HStack {
                    Picker("CPU Slowdown", selection: $cpu) {
                        Text("Normal (1×)").tag(1.0)
                        Text("4×").tag(4.0)
                        Text("6×").tag(6.0)
                        if ![1.0, 4.0, 6.0].contains(cpu) { Text("Custom").tag(cpu) }
                    }
                    number("Custom CPU (1–20×)", value: $cpu)
                    Button("Apply CPU") {
                        Task {
                            do { try await adapter.applyCPU(cpu); cpu = adapter.appliedCPURate }
                            catch { }
                        }
                    }
                }
                Button("Reset Network and CPU") {
                    Task {
                        do {
                            try await adapter.applyNetwork(nil)
                            refreshNetwork()
                            try await adapter.applyCPU(1)
                            cpu = adapter.appliedCPURate
                        } catch { }
                    }
                }
            }
            .controlSize(.small)
            .disabled(adapter.emulationPending || adapter.state.isLoading || adapter.state.lifecycle != .active)
            Text(appliedDescription).font(.caption).foregroundStyle(.secondary)
            Text("CPU and network-state emulation can affect pages sharing this renderer. Cached responses and worker requests may behave differently.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { refreshNetwork(); cpu = adapter.appliedCPURate }
        .onChange(of: adapter.appliedNetwork) { if !adapter.emulationPending { refreshNetwork() } }
        .onChange(of: adapter.appliedCPURate) { if !adapter.emulationPending { cpu = adapter.appliedCPURate } }
        .onChange(of: preset) {
            if preset == "offline" { offline = true }
            else if preset == "slow" { offline = false; latency = 400; downloadKB = 100; uploadKB = 50 }
        }
    }

    private var appliedDescription: String {
        let network: String
        if let applied = adapter.appliedNetwork {
            network = applied.offline ? "Network override: offline." :
                "Network override: \(applied.latencyMS.formatted()) ms, \(rate(applied.downloadBytesPerSecond)) down, \(rate(applied.uploadBytesPerSecond)) up."
        } else { network = "No network override." }
        return network + " CPU: \(adapter.appliedCPURate.formatted())×."
    }
    private func rate(_ value: Double) -> String {
        value == -1 ? "unlimited" : "\((value / 1000).formatted()) KB/s"
    }
    private func number(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption)
            TextField(title, value: value, format: .number).accessibilityLabel(title)
        }
    }
    private func refreshNetwork() {
        let value = adapter.appliedNetwork ?? ChromiumNetwork()
        offline = value.offline; latency = value.latencyMS
        downloadKB = value.downloadBytesPerSecond == -1 ? -1 : value.downloadBytesPerSecond / 1000
        uploadKB = value.uploadBytesPerSecond == -1 ? -1 : value.uploadBytesPerSecond / 1000
        preset = "custom"
    }
    private func applyNetwork() {
        let value = ChromiumNetwork(offline: offline, latencyMS: latency,
            downloadBytesPerSecond: downloadKB == -1 ? -1 : downloadKB * 1000,
            uploadBytesPerSecond: uploadKB == -1 ? -1 : uploadKB * 1000)
        Task {
            do { try await adapter.applyNetwork(value); refreshNetwork() }
            catch { }
        }
    }
}
#endif
