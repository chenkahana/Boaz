#if BOAZ_CHROMIUM
import AppKit
import SwiftUI

@MainActor
struct ChromiumPageView: View {
    let adapter: ChromiumEnginePageAdapter
    @State private var failure: ViewFailure?

    var body: some View {
        RendererView(adapter: adapter, generation: adapter.viewGeneration,
                     lifecycle: adapter.state.lifecycle) { message in
            let next = message.map { ViewFailure(adapter: ObjectIdentifier(adapter), message: $0) }
            if failure != next { failure = next }
        }
        .overlay {
            if let failure, failure.adapter == ObjectIdentifier(adapter) {
                Text(failure.message)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(.regularMaterial)
                    .accessibilityLabel(failure.message)
            }
        }
    }

    private struct ViewFailure: Equatable {
        let adapter: ObjectIdentifier
        let message: String
    }
}

@MainActor
private struct RendererView: NSViewRepresentable {
    let adapter: ChromiumEnginePageAdapter
    let generation: Int
    let lifecycle: EnginePageLifecycle
    let report: (String?) -> Void

    final class Container: NSView {
        weak var renderer: NSView?
        func detach() {
            if renderer?.superview === self { renderer?.removeFromSuperview() }
            renderer = nil
        }
    }

    final class Coordinator {
        var revision = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> Container { Container() }

    func updateNSView(_ container: Container, context: Context) {
        let coordinator = context.coordinator
        coordinator.revision += 1
        let revision = coordinator.revision
        let message: String?
        if lifecycle == .closing || lifecycle == .closed {
            container.detach()
            message = nil
        } else {
            do {
                let renderer = try adapter.nativeView()
                if container.renderer !== renderer { container.detach() }
                if renderer.superview !== container {
                    renderer.removeFromSuperview()
                    container.addSubview(renderer)
                }
                container.renderer = renderer
                renderer.frame = container.bounds
                renderer.autoresizingMask = [.width, .height]
                message = nil
            } catch {
                container.detach()
                message = "The page could not be displayed: \(String(describing: error))."
            }
        }
        let expectedGeneration = generation
        DispatchQueue.main.async { [weak coordinator, weak container, weak adapter] in
            guard let coordinator, container != nil, let adapter,
                  coordinator.revision == revision,
                  adapter.viewGeneration == expectedGeneration,
                  adapter.state.lifecycle == lifecycle else { return }
            report(message)
        }
    }

    static func dismantleNSView(_ container: Container, coordinator: Coordinator) {
        coordinator.revision += 1
        container.detach()
    }
}
#endif
