import AppKit
import SwiftUI

private struct BrowserView: NSViewRepresentable {
    let host: BZBrowserHost
    func makeNSView(context: Context) -> BZBrowserHost { host }
    func updateNSView(_ nsView: BZBrowserHost, context: Context) {}
}

private struct NavigationBar: View {
    let host: BZBrowserHost
    @State private var address = ProcessInfo.processInfo.environment["BOAZ_CEF_SPIKE_URL"] ?? "https://example.com"

    var body: some View {
        HStack {
            Button("Back") { host.goBack() }
            Button("Reload") { host.reload() }
            TextField("Address", text: $address)
                .textFieldStyle(.roundedBorder)
                .onSubmit { host.navigate(address) }
            Button("Go") { host.navigate(address) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

private struct SpikeView: View {
    let host: BZBrowserHost
    @State private var status = "Starting Chromium"

    var body: some View {
        VStack(spacing: 0) {
            NavigationBar(host: host).frame(height: 60)
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

private struct NativeSidebar: View {
    let host: BZBrowserHost
    @State private var status = "Starting Chrome-style page"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Boaz").font(.title2.weight(.semibold))
            Text("Native SwiftUI sidebar").font(.caption).foregroundStyle(.secondary)
            Button("Example Domain") { host.navigate("https://example.com") }
            Text(status).font(.caption).textSelection(.enabled)
            Spacer()
            Text("Single-page hosting experiment").font(.caption).foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial)
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

@_cdecl("BZCreateToolbar")
func createToolbar(_ opaqueHost: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
    let host = Unmanaged<BZBrowserHost>.fromOpaque(opaqueHost).takeUnretainedValue()
    return Unmanaged.passRetained(NSHostingView(rootView: NavigationBar(host: host))).toOpaque()
}

@_cdecl("BZCreateSidebar")
func createSidebar(_ opaqueHost: UnsafeMutableRawPointer) -> UnsafeMutableRawPointer {
    let host = Unmanaged<BZBrowserHost>.fromOpaque(opaqueHost).takeUnretainedValue()
    return Unmanaged.passRetained(NSHostingView(rootView: NativeSidebar(host: host))).toOpaque()
}
