import AppKit
import SwiftUI

private struct BrowserView: NSViewRepresentable {
    let host: BZBrowserHost
    func makeNSView(context: Context) -> BZBrowserHost { host }
    func updateNSView(_ nsView: BZBrowserHost, context: Context) {}
}

private struct SpikeView: View {
    let host: BZBrowserHost
    @State private var address = ProcessInfo.processInfo.environment["BOAZ_CEF_SPIKE_URL"] ?? "https://example.com"
    @State private var status = "Starting Chromium"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back") { host.goBack() }
                Button("Reload") { host.reload() }
                TextField("Address", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { host.navigate(address) }
                Button("Go") { host.navigate(address) }
            }
            .padding(12)
            Divider()
            BrowserView(host: host)
            Divider()
            HStack {
                Text(status).font(.caption).textSelection(.enabled)
                Spacer()
                Text("Isolated CEF feasibility app").font(.caption)
            }
            .padding(8)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("BoazCEFSpikeStatus"))) { note in
            status = note.userInfo?["status"] as? String ?? status
        }
    }
}

@_cdecl("BZCreateRootView")
func createRootView(_ opaqueHost: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
    let host = Unmanaged<BZBrowserHost>.fromOpaque(opaqueHost).takeUnretainedValue()
    let view = NSHostingView(rootView: SpikeView(host: host))
    return Unmanaged.passRetained(view).toOpaque()
}
