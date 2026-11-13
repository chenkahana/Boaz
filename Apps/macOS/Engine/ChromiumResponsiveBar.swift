#if BOAZ_CHROMIUM
import SwiftUI

@MainActor
struct ChromiumResponsiveBar: View {
    let adapter: ChromiumEnginePageAdapter
    @State private var draft = ChromiumViewport()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Viewport").font(.caption.weight(.semibold))
                TextField("Width", value: $draft.width, format: .number).frame(width: 65).accessibilityLabel("Viewport width")
                Text("×")
                TextField("Height", value: $draft.height, format: .number).frame(width: 65).accessibilityLabel("Viewport height")
                TextField("DPR", value: $draft.dpr, format: .number).frame(width: 45).accessibilityLabel("Device pixel ratio")
                Button { swap(&draft.width, &draft.height); draft.landscape.toggle() } label: {
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
                Text("User agent is unchanged.")
                if adapter.emulationPending { ProgressView().controlSize(.small) }
            }.font(.caption).foregroundStyle(.secondary)
            if let error = adapter.emulationError { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding(8)
        .background(.bar)
        .onAppear { if let applied = adapter.appliedViewport { draft = applied } }
    }

    private func change(_ value: ChromiumViewport?) {
        Task { try? await adapter.applyViewport(value) }
    }
    private func close() {
        Task {
            do {
                try await adapter.applyViewport(nil)
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
