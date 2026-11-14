#if BOAZ_CHROMIUM
import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class ChromiumExtensionActionsModel {
    struct Action: Identifiable { let id: String; let name: String; var title = ""; var badge = ""; var icon: NSImage? }
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
    var activeHandle: BoazHostPage? {
        guard let page = activePage(), page.state.lifecycle == .active else { return nil }
        return page.handle
    }
    func refresh(for notification: Notification) {
        if let changedWindow = notification.userInfo?["window"] as? BoazHostWindow, changedWindow != window { return }
        refresh()
    }

    private final class Snapshot { var actions: [Action] = [] }
    private final class Metadata { var title = ""; var badge = ""; var icon: NSImage? }
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
        if let page = activePage(), page.state.lifecycle == .active, let metadata = api.extension_metadata {
            for index in snapshot.actions.indices {
                let value = Metadata()
                let result = snapshot.actions[index].id.withCString {
                    metadata(window, page.handle, $0, { context, title, badge, png, count in
                        guard let context, let title, let badge else { return }
                        MainActor.assumeIsolated {
                            let value = Unmanaged<Metadata>.fromOpaque(context).takeUnretainedValue()
                            value.title = String(cString: title)
                            value.badge = String(cString: badge)
                            if let png, count > 0, count <= 262_144 {
                                value.icon = NSImage(data: Data(bytes: png, count: count))
                            }
                        }
                    }, Unmanaged.passUnretained(value).toOpaque())
                }
                if result == BOAZ_HOST_OK {
                    snapshot.actions[index].title = value.title
                    snapshot.actions[index].badge = value.badge
                    snapshot.actions[index].icon = value.icon
                }
            }
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

/// Arc's extensions in the address row: the pinned extensions' buttons, then a puzzle button whose popover lists every
/// extension, pins it and opens its popup.
struct ChromiumExtensionActionsBar: View {
    let model: ChromiumExtensionActionsModel
    @Environment(BrowserState.self) private var browser
    /// Pinned extension IDs, space-separated; shared by every window.
    @AppStorage("chromiumPinnedExtensions") private var pinnedIDs = ""
    @State private var listing = false
    @State private var opening: String?
    @State private var menuButton = ButtonReference()

    var body: some View {
        let pinned = Set(pinnedIDs.split(separator: " ").map(String.init))
        HStack(spacing: 0) {
            ForEach(model.actions.filter { pinned.contains($0.id) }) { action in
                NativeExtensionActionButton(model: model, action: action).frame(width: 26, height: 26)
                    .overlay(alignment: .topTrailing) {
                        if !action.badge.isEmpty {
                            Text(action.badge).font(.system(size: 9, weight: .semibold))
                                .lineLimit(1).padding(.horizontal, 3)
                                .background(.regularMaterial, in: Capsule())
                                .frame(maxWidth: 36).allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
            }
            ExtensionsMenuButton(reference: menuButton, failed: model.failure != nil) { listing.toggle() }
                .frame(width: 26, height: 26)
                .help(model.failure ?? "Extensions")
                .popover(isPresented: $listing, arrowEdge: .bottom) {
                    ExtensionsPopover(model: model, pinned: pinned,
                                      open: { opening = $0; listing = false },
                                      togglePin: { id in
                                          pinnedIDs = (pinned.contains(id) ? pinned.subtracting([id]) : pinned.union([id]))
                                              .sorted().joined(separator: " ")
                                      },
                                      manage: browser.manageChromiumExtensions.map { manage in { listing = false; manage() } })
                    // The popup opens once the popover is gone, so it keeps the focus.
                    .onDisappear {
                        guard let id = opening else { return }
                        opening = nil
                        if let button = menuButton.button { model.invoke(id, anchor: button) }
                    }
                }
        }
        .onAppear { model.refresh() }
        .onChange(of: model.activeHandle) { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ChromiumExtensionManagement.installedExtensionsChanged)) { notification in
            model.refresh(for: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}

private final class ButtonReference { weak var button: NSButton? }

/// An AppKit button, because an extension popup points at a native view.
private struct ExtensionsMenuButton: NSViewRepresentable {
    let reference: ButtonReference
    let failed: Bool
    let toggle: () -> Void
    final class Coordinator: NSObject {
        var toggle: () -> Void
        init(toggle: @escaping () -> Void) { self.toggle = toggle }
        @objc func clicked(_ sender: NSButton) { toggle() }
    }
    func makeCoordinator() -> Coordinator { Coordinator(toggle: toggle) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: "Extensions")!,
                              target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        button.isBordered = false
        reference.button = button
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.toggle = toggle
        reference.button = button
        button.contentTintColor = failed ? .systemOrange : .secondaryLabelColor
    }
    static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) {
        button.target = nil
        button.action = nil
    }
}

private struct ExtensionsPopover: View {
    let model: ChromiumExtensionActionsModel
    let pinned: Set<String>
    let open: (String) -> Void
    let togglePin: (String) -> Void
    let manage: (() -> Void)?

    var body: some View {
        let active = model.activeHandle != nil
        VStack(alignment: .leading, spacing: 0) {
            Text("Extensions").font(.headline).padding(.horizontal, 8).padding(.bottom, 6)
            if model.actions.isEmpty {
                Text("No extensions yet.").foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4)
            }
            ForEach(model.actions) { action in
                ExtensionRow(action: action, pinned: pinned.contains(action.id), active: active,
                             open: { open(action.id) }, togglePin: { togglePin(action.id) })
            }
            if !active, !model.actions.isEmpty {
                Text("Extensions aren't available on this page.").font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.top, 4)
            }
            if let failure = model.failure {
                Text(failure).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.top, 4)
            }
            if let manage {
                Divider().padding(.vertical, 6)
                PopoverRow(action: manage) { Text("Manage Extensions…") }
            }
        }
        .padding(8)
        .frame(width: 280)
    }
}

private struct ExtensionRow: View {
    let action: ChromiumExtensionActionsModel.Action
    let pinned: Bool
    let active: Bool
    let open: () -> Void
    let togglePin: () -> Void

    var body: some View {
        PopoverRow(action: open) {
            HStack(spacing: 8) {
                Group {
                    if let icon = action.icon { Image(nsImage: icon).resizable() } else { Image(systemName: "puzzlepiece.extension") }
                }
                .frame(width: 16, height: 16)
                Text(action.name).lineLimit(1)
                Spacer(minLength: 0)
                if !action.badge.isEmpty { Text(action.badge).font(.caption).foregroundStyle(.secondary) }
                Button(action: togglePin) {
                    Image(systemName: pinned ? "pin.fill" : "pin").foregroundStyle(pinned ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .help(pinned ? "Unpin from Address Bar" : "Pin to Address Bar")
                .accessibilityLabel(pinned ? "Unpin \(action.name)" : "Pin \(action.name)")
            }
        }
        .disabled(!active)
        .help(action.title.isEmpty ? action.name : action.title)
    }
}

private struct PopoverRow<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label.padding(.horizontal, 8).frame(height: 28).frame(maxWidth: .infinity, alignment: .leading)
                .background(hovering && enabled ? SidebarStyle.hover : .clear, in: .rect(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
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
        button.image = action.icon ?? NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: action.name)
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = model.activeHandle != nil ? (action.title.isEmpty ? action.name : action.title)
            : "Extensions aren't available on this page."
        button.setAccessibilityLabel(action.badge.isEmpty ? action.name : "\(action.name), \(action.badge)")
        button.isEnabled = model.activeHandle != nil
    }
    static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) {
        button.target = nil
        button.action = nil
    }
}
#endif
