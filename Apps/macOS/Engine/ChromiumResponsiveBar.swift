#if BOAZ_CHROMIUM
import SwiftUI

@MainActor
struct ChromiumResponsiveBar: View {
    let adapter: ChromiumEnginePageAdapter
    @State private var draft = ChromiumViewport()
    @State private var customUserAgent = ""
    @State private var defaultsError: String?
    @State private var presets: [ChromiumViewportPresets.Preset] = []
    @State private var selectedPreset = ""
    @State private var presetName = ""
    @State private var presetError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Picker("Saved Viewport", selection: $selectedPreset) {
                    Text("Custom size").tag("")
                    ForEach(presets) { Text($0.name).tag($0.id.uuidString) }
                }.accessibilityLabel("Saved viewport preset")
                TextField("Preset name", text: $presetName).accessibilityLabel("New viewport preset name")
                Button("Save") { savePreset() }.disabled(adapter.profile.isPrivate)
                Button("Remove") { removePreset() }.disabled(adapter.profile.isPrivate || selectedPreset.isEmpty)
            }.controlSize(.small)
            if adapter.profile.isPrivate {
                Text("Private windows can use saved presets but cannot change them.").font(.caption).foregroundStyle(.secondary)
            }
            if let presetError { Text(presetError).font(.caption).foregroundStyle(.red) }
            HStack(spacing: 8) {
                Text("Viewport").font(.caption.weight(.semibold))
                TextField("Width", value: $draft.width, format: .number).frame(width: 65).accessibilityLabel("Viewport width")
                Text("×")
                TextField("Height", value: $draft.height, format: .number).frame(width: 65).accessibilityLabel("Viewport height")
                TextField("DPR", value: $draft.dpr, format: .number).frame(width: 45).accessibilityLabel("Device pixel ratio")
                Button { let width = draft.width; draft.width = draft.height; draft.height = width; draft.landscape.toggle() } label: {
                    Image(systemName: "rotate.right")
                }.help("Rotate viewport").accessibilityLabel("Rotate viewport")
                Toggle("Mobile", isOn: $draft.mobile)
                Toggle("Touch", isOn: $draft.touch)
                Button("Apply") { change(draft) }
                Button("Reset") { change(nil) }
                Spacer(minLength: 0)
                Button { close() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Exit responsive mode")
            }
            .disabled(adapter.emulationPending || adapter.state.isLoading || adapter.state.lifecycle != .active)
            .controlSize(.small)
            HStack {
                Text(adapter.appliedViewport == nil ? "No viewport override applied." : "Viewport override active.")
                Text(adapter.appliedUserAgent == nil ? "Native user agent." : "Custom user agent; Client Hints suppressed.")
                if adapter.emulationPending { ProgressView().controlSize(.small) }
            }.font(.caption).foregroundStyle(.secondary)
            ChromiumSensorControls(adapter: adapter)
            ChromiumThrottlingControls(adapter: adapter)
            ChromiumMediaControls(adapter: adapter)
            DisclosureGroup("User Agent") {
                VStack(alignment: .leading, spacing: 6) {
                    if let defaults = adapter.userAgentDefaults {
                        Text("Native: \(defaults.userAgent)").textSelection(.enabled)
                        Text("Platform: \(defaults.navigatorPlatform) · \(defaults.metadata.platform) \(defaults.metadata.platformVersion) · \(defaults.metadata.architecture)")
                        Text("Model: \(defaults.metadata.model) · Bitness: \(defaults.metadata.bitness) · Mobile: \(defaults.metadata.mobile ? "yes" : "no") · WOW64: \(defaults.metadata.wow64 ? "yes" : "no")")
                        Text("Form factors: " + defaults.metadata.formFactors.joined(separator: ", "))
                        Text("Brands: " + defaults.metadata.fullVersionList.map { "\($0.brand) \($0.version)" }.joined(separator: ", "))
                    }
                    if let defaultsError { Text(defaultsError).foregroundStyle(.red) }
                    TextField("Custom user agent", text: $customUserAgent).accessibilityLabel("Custom user agent")
                    HStack {
                        Button("Apply Custom") { Task { try? await adapter.applyUserAgent(customUserAgent) } }
                        Button("Use Native Defaults") { Task { try? await adapter.applyUserAgent(nil) } }
                        Text("Custom overrides suppress Client Hints; they do not change the rendering engine.")
                    }
                    .disabled(adapter.emulationPending || adapter.state.isLoading || adapter.state.lifecycle != .active)
                }.font(.caption)
            }
            if let error = adapter.emulationError { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(8)
        .background(.bar)
        .onChange(of: selectedPreset) {
            if let preset = presets.first(where: { $0.id.uuidString == selectedPreset }) { draft = preset.viewport }
        }
        .onChange(of: draft) {
            if let preset = presets.first(where: { $0.id.uuidString == selectedPreset }), preset.viewport != draft {
                selectedPreset = ""
            }
        }
        .onAppear {
            do { presets = try ChromiumViewportPresets.load(); presetError = nil }
            catch { presetError = error.localizedDescription }
            if let applied = adapter.appliedViewport { draft = applied }
            customUserAgent = adapter.appliedUserAgent ?? ""
            do { try adapter.readUserAgentDefaults() }
            catch { defaultsError = "Native user-agent details are unavailable." }
        }
    }

    private func savePreset() {
        guard !adapter.profile.isPrivate else { return }
        do {
            let saved = try ChromiumViewportPresets.save(name: presetName, viewport: draft)
            presets = try ChromiumViewportPresets.load()
            selectedPreset = saved.id.uuidString
            presetName = ""
            presetError = nil
        } catch { presetError = error.localizedDescription }
    }
    private func removePreset() {
        guard !adapter.profile.isPrivate, let id = UUID(uuidString: selectedPreset) else { return }
        do {
            try ChromiumViewportPresets.remove(id: id)
            presets = try ChromiumViewportPresets.load()
            selectedPreset = ""
            presetError = nil
        } catch { presetError = error.localizedDescription }
    }

    private func change(_ value: ChromiumViewport?) {
        Task { try? await adapter.applyViewport(value) }
    }
    private func close() {
        Task {
            do {
                try await adapter.applyViewport(nil)
                try await adapter.applyUserAgent(nil)
                try await adapter.applyMedia(nil)
                try await adapter.applyNetwork(nil)
                try await adapter.applyCPU(1)
                try await adapter.applySensors(nil)
                adapter.responsiveVisible = false
            } catch { }
        }
    }
}

struct ChromiumViewportLayout: ViewModifier {
    let viewport: ChromiumViewport?
    func body(content: Content) -> some View {
        if let viewport {
            GeometryReader { geometry in
                let width = CGFloat(viewport.width)
                let height = CGFloat(viewport.height)
                let scale = min(1, min(geometry.size.width / width, geometry.size.height / height))
                content.frame(width: width, height: height)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: width * scale, height: height * scale, alignment: .topLeading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }.clipped()
        } else { content }
    }
}
#endif
