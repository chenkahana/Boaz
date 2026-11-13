#if BOAZ_CHROMIUM
import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class ChromiumExtensionActionsModel {
    struct Action: Identifiable { let id: String; let name: String }
    private(set) var actions: [Action] = []
    var failure: String?
    @ObservationIgnored private let api: BoazHostAPI
    @ObservationIgnored private let window: BoazHostWindow
    @ObservationIgnored private let activePage: () -> ChromiumEnginePageAdapter?

    init(api: BoazHostAPI, window: BoazHostWindow,
         activePage: @escaping () -> ChromiumEnginePageAdapter?) {
        self.api = api
        self.window = window
        self.activePage = activePage
    }
    var activeHandle: BoazHostPage? { activePage()?.handle }

    private final class Snapshot { var actions: [Action] = [] }
    func refresh() {
        guard api.size >= MemoryLayout<BoazHostAPI>.size,
              api.version == BOAZ_HOST_ABI_VERSION,
              let enumerate = api.enumerate_extensions, api.invoke_extension != nil else {
            actions = []
            failure = "Extension actions are unavailable in this browser bridge."
            return
        }
        let snapshot = Snapshot()
        let result = enumerate(window, { context, id, name in
            guard let context, let id, let name else { return }
            MainActor.assumeIsolated {
                Unmanaged<Snapshot>.fromOpaque(context).takeUnretainedValue().actions.append(
                    Action(id: String(cString: id), name: String(cString: name)))
            }
        }, Unmanaged.passUnretained(snapshot).toOpaque())
        guard result == BOAZ_HOST_OK else {
            actions = []
            failure = "Could not load extensions (\(result.rawValue))."
            return
        }
        actions = snapshot.actions
        failure = nil
    }

    fileprivate func invoke(_ id: String, anchor: NSButton) {
        guard let page = activePage(), page.state.lifecycle == .active,
              actions.contains(where: { $0.id == id }), anchor.window != nil,
              let invoke = api.invoke_extension else {
            failure = "The extension action has no active page or window."
            return
        }
        let bounds = anchor.bounds
        guard let x = Int32(exactly: bounds.minX.rounded(.down)),
              let y = Int32(exactly: bounds.minY.rounded(.down)),
              let width = Int32(exactly: bounds.width.rounded(.up)),
              let height = Int32(exactly: bounds.height.rounded(.up)), width > 0, height > 0 else {
            failure = "The extension button is not ready."
            return
        }
        let result = id.withCString {
            invoke(window, page.handle, $0, Unmanaged.passUnretained(anchor).toOpaque(), x, y, width, height)
        }
        failure = result == BOAZ_HOST_OK ? nil : "Could not open extension (\(result.rawValue))."
    }
}

struct ChromiumExtensionActionsBar: View {
    let model: ChromiumExtensionActionsModel
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !model.actions.isEmpty {
                HStack(spacing: 4) {
                    ForEach(model.actions) { action in
                        NativeExtensionActionButton(model: model, action: action).frame(width: 28, height: 28)
                    }
                    Spacer(minLength: 0)
                }
            }
            if let failure = model.failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
        }
        .onAppear { model.refresh() }
        .onChange(of: model.activeHandle) { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}

private struct NativeExtensionActionButton: NSViewRepresentable {
    let model: ChromiumExtensionActionsModel
    let action: ChromiumExtensionActionsModel.Action
    final class Coordinator: NSObject {
        var model: ChromiumExtensionActionsModel
        var id: String
        init(model: ChromiumExtensionActionsModel, id: String) { self.model = model; self.id = id }
        @objc func clicked(_ sender: NSButton) { model.invoke(id, anchor: sender) }
    }
    func makeCoordinator() -> Coordinator { Coordinator(model: model, id: action.id) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: action.name)!,
                              target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        button.isBordered = false
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.model = model
        context.coordinator.id = action.id
        button.toolTip = action.name
        button.setAccessibilityLabel(action.name)
        button.isEnabled = model.activeHandle != nil
    }
    static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) {
        button.target = nil
        button.action = nil
    }
}
#endif
