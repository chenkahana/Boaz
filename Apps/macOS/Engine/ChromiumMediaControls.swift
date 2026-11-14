#if BOAZ_CHROMIUM
import SwiftUI

@MainActor
struct ChromiumMediaControls: View {
    let adapter: ChromiumEnginePageAdapter
    @State private var draft = ChromiumMedia()

    var body: some View {
        DisclosureGroup("Media and Vision") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Media Type", selection: $draft.type) {
                    Text("Screen").tag(ChromiumMedia.MediaType.screen)
                    Text("Print").tag(ChromiumMedia.MediaType.print)
                }.accessibilityLabel("Emulated media type")
                preference("Appearance", selection: $draft.colorScheme, first: "Light", second: "Dark")
                preference("Motion", selection: $draft.reducedMotion, first: "No preference", second: "Reduce motion")
                preference("Contrast", selection: $draft.contrast, first: "No preference", second: "More contrast")
                Toggle("Forced Colors", isOn: $draft.forcedColors).accessibilityLabel("Emulate forced colors")
                Picker("Vision", selection: $draft.vision) {
                    ForEach(ChromiumMedia.Vision.allCases, id: \.self) { vision in
                        Text(vision.title).tag(vision)
                    }
                }.accessibilityLabel("Vision simulation")
                HStack {
                    Button("Apply Media and Vision") { apply(draft) }
                    Button("Reset Media and Vision") { apply(nil) }
                }
            }
            .controlSize(.small)
            .disabled(adapter.emulationPending || adapter.state.isLoading || adapter.state.lifecycle != .active)
            Text(adapter.appliedMedia == nil ? "No media or vision override applied." : "Media and vision overrides active.")
                .font(.caption).foregroundStyle(.secondary)
                .accessibilityLabel(adapter.appliedMedia == nil ? "Media and vision defaults active" : "Media and vision overrides applied")
        }
        .onAppear { draft = adapter.appliedMedia ?? ChromiumMedia() }
        .onChange(of: adapter.appliedMedia) { draft = adapter.appliedMedia ?? ChromiumMedia() }
    }

    private func preference(_ title: String, selection: Binding<ChromiumMedia.Preference>,
                            first: String, second: String) -> some View {
        Picker(title, selection: selection) {
            Text("System").tag(ChromiumMedia.Preference.system)
            Text(first).tag(ChromiumMedia.Preference.first)
            Text(second).tag(ChromiumMedia.Preference.second)
        }.accessibilityLabel("Emulated \(title.lowercased()) preference")
    }

    private func apply(_ value: ChromiumMedia?) {
        Task {
            do {
                try await adapter.applyMedia(value)
                draft = adapter.appliedMedia ?? ChromiumMedia()
            } catch { }
        }
    }
}
#endif
