#if BOAZ_CHROMIUM
import AppKit
import Observation
import SwiftUI

/// The window's extension toolbar as Chromium's toolbar model keeps it: which actions are pinned (and in what order),
/// their icons with the badge drawn in, and the sites that request access.
@MainActor @Observable
final class ChromiumExtensionActionsModel {
    static let installedExtensionsChanged = Notification.Name("BoazChromiumInstalledExtensionsChanged")
    /// Boaz's own pins from before Chromium's toolbar model kept them; moved into Chromium once.
    private static let legacyPinsKey = "chromiumPinnedExtensions"
    struct Action: Identifiable {
        let id: String
        let name: String
        let flags: UInt32
        var title = ""
        var icon: NSImage?
        var pinned: Bool { flags & BOAZ_EXTENSION_PINNED.rawValue != 0 }
        var forcePinned: Bool { flags & BOAZ_EXTENSION_FORCE_PINNED.rawValue != 0 }
    }
    struct AccessRequest { let tooltip: String; let ids: [String] }
    private(set) var actions: [Action] = []
    private(set) var accessRequest: AccessRequest?
    var failure: String?
    @ObservationIgnored private let api: BoazHostAPI
    @ObservationIgnored private let window: BoazHostWindow
    @ObservationIgnored private let activePage: () -> ChromiumEnginePageAdapter?
    @ObservationIgnored private var buttons: [String: WeakButton] = [:]
    @ObservationIgnored weak var menuButton: NSButton?

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
    var pinned: [Action] { actions.filter(\.pinned) }
    func refresh(for notification: Notification) {
        if let changedWindow = notification.userInfo?["window"] as? BoazHostWindow, changedWindow != window { return }
        refresh()
    }

    private final class Snapshot { var actions: [Action] = [] }
    private final class Metadata { var title = ""; var icon: NSImage? }
    private final class Request { var value: AccessRequest? }
    func refresh() {
        guard api.size >= MemoryLayout<BoazHostAPI>.size,
              api.version == BOAZ_HOST_ABI_VERSION,
              let enumerate = api.enumerate_extensions, api.invoke_extension != nil else {
            actions = []
            accessRequest = nil
            failure = "Extension actions are unavailable in this browser bridge."
            return
        }
        let snapshot = Snapshot()
        let result = enumerate(window, { context, id, name, flags in
            guard let context, let id, let name else { return }
            MainActor.assumeIsolated {
                Unmanaged<Snapshot>.fromOpaque(context).takeUnretainedValue().actions.append(
                    Action(id: String(cString: id), name: String(cString: name), flags: flags))
            }
        }, Unmanaged.passUnretained(snapshot).toOpaque())
        guard result == BOAZ_HOST_OK else {
            actions = []
            accessRequest = nil
            failure = "Could not load extensions (\(result.rawValue))."
            return
        }
        var request: AccessRequest?
        if let page = activeHandle {
            if let metadata = api.extension_metadata {
                for index in snapshot.actions.indices {
                    let value = Metadata()
                    let result = snapshot.actions[index].id.withCString {
                        metadata(window, page, $0, { context, title, _, png, count in
                            guard let context, let title else { return }
                            MainActor.assumeIsolated {
                                let value = Unmanaged<Metadata>.fromOpaque(context).takeUnretainedValue()
                                value.title = String(cString: title)
                                // Chromium draws the icon and its badge at 2x for a 26-point button.
                                if let png, count > 0, count <= 262_144,
                                   let image = NSImage(data: Data(bytes: png, count: count)) {
                                    image.size = NSSize(width: 26, height: 26)
                                    value.icon = image
                                }
                            }
                        }, Unmanaged.passUnretained(value).toOpaque())
                    }
                    if result == BOAZ_HOST_OK {
                        snapshot.actions[index].title = value.title
                        snapshot.actions[index].icon = value.icon
                    }
                }
            }
            if let access = api.extension_access_request {
                let value = Request()
                _ = access(window, page, { context, tooltip, ids, count in
                    guard let context, let tooltip, let ids, count > 0 else { return }
                    MainActor.assumeIsolated {
                        let list = (0..<count).compactMap { ids[$0].map { String(cString: $0) } }
                        Unmanaged<Request>.fromOpaque(context).takeUnretainedValue().value =
                            AccessRequest(tooltip: String(cString: tooltip), ids: list)
                    }
                }, Unmanaged.passUnretained(value).toOpaque())
                request = value.value
            }
        }
        actions = snapshot.actions
        accessRequest = request
        failure = nil
        migrateLegacyPins()
    }

    /// Moves each extension Boaz pinned itself into Chromium's pins, once it is installed here.
    private func migrateLegacyPins() {
        let defaults = UserDefaults.standard
        guard let stored = defaults.string(forKey: Self.legacyPinsKey) else { return }
        var remaining = Set(stored.split(separator: " ").map(String.init))
        var changed = false
        for action in actions where remaining.contains(action.id) {
            if !action.pinned { setPinned(action.id, true) }
            remaining.remove(action.id)
            changed = true
        }
        if remaining.isEmpty { defaults.removeObject(forKey: Self.legacyPinsKey) }
        else if changed { defaults.set(remaining.sorted().joined(separator: " "), forKey: Self.legacyPinsKey) }
    }

    func setPinned(_ id: String, _ pinned: Bool) {
        guard let set = api.set_extension_pinned else { return }
        let result = id.withCString { set(window, $0, pinned ? 1 : 0) }
        if result != BOAZ_HOST_OK { failure = "Could not change the pin (\(result.rawValue))." }
    }

    func register(_ button: NSButton, for id: String) { buttons[id] = WeakButton(button: button) }

    /// Where Chromium points the popup or dialog of `id`: its pinned button, else the extensions button.
    func anchor(for id: String?) -> NSView? {
        for candidate in [id.flatMap { buttons[$0]?.button }, menuButton] {
            if let view = candidate, view.window != nil, !view.isHiddenOrHasHiddenAncestor, view.bounds.width > 0 {
                return view
            }
        }
        return nil
    }

    private func anchorRect(_ anchor: NSView) -> (Int32, Int32, Int32, Int32)? {
        let bounds = anchor.bounds
        guard let x = Int32(exactly: bounds.minX.rounded(.down)),
              let y = Int32(exactly: bounds.minY.rounded(.down)),
              let width = Int32(exactly: bounds.width.rounded(.up)),
              let height = Int32(exactly: bounds.height.rounded(.up)), width > 0, height > 0 else { return nil }
        return (x, y, width, height)
    }

    fileprivate func invoke(_ id: String, anchor: NSView) {
        guard let page = activeHandle, actions.contains(where: { $0.id == id }), anchor.window != nil,
              let invoke = api.invoke_extension else {
            failure = "The extension action has no active page or window."
            return
        }
        guard let (x, y, width, height) = anchorRect(anchor) else {
            failure = "The extension button is not ready."
            return
        }
        let result = id.withCString {
            invoke(window, page, $0, Unmanaged.passUnretained(anchor).toOpaque(), x, y, width, height)
        }
        failure = result == BOAZ_HOST_OK ? nil : "Could not open extension (\(result.rawValue))."
    }

    /// Chromium's own action menu: pin, site access, options, remove, inspect popup.
    fileprivate func showMenu(_ id: String, anchor: NSView) {
        guard let page = activeHandle, let show = api.show_extension_menu,
              let (x, y, width, height) = anchorRect(anchor) else { return }
        let result = id.withCString {
            show(window, page, $0, Unmanaged.passUnretained(anchor).toOpaque(), x, y, width, height)
        }
        if result != BOAZ_HOST_OK { failure = "Could not show the extension menu (\(result.rawValue))." }
    }

    fileprivate func grantAccess() {
        guard let page = activeHandle, let grant = api.grant_extension_access_request else { return }
        let result = grant(window, page)
        if result != BOAZ_HOST_OK { failure = "Could not allow the extension (\(result.rawValue))." }
    }
}

private struct WeakButton { weak var button: NSButton? }

/// The extensions in the address row, as Chrome's toolbar has them: the request-access button, the pinned actions,
/// then the extensions button whose popover lists every extension, pins it and opens its popup.
struct ChromiumExtensionActionsBar: View {
    let model: ChromiumExtensionActionsModel
    @Environment(BrowserState.self) private var browser
    @State private var listing = false
    @State private var opening: String?

    var body: some View {
        HStack(spacing: 0) {
            if let request = model.accessRequest {
                ExtensionAccessButton(model: model, request: request)
            }
            ForEach(model.pinned) { action in
                NativeExtensionActionButton(model: model, action: action).frame(width: 26, height: 26)
            }
            ExtensionsMenuButton(model: model, failed: model.failure != nil) { listing.toggle() }
                .frame(width: 26, height: 26)
                .help(model.failure ?? "Extensions")
                .popover(isPresented: $listing, arrowEdge: .bottom) {
                    ExtensionsPopover(model: model,
                                      open: { opening = $0; listing = false },
                                      togglePin: { action in model.setPinned(action.id, !action.pinned) },
                                      manage: browser.manageChromiumExtensions.map { manage in { listing = false; manage() } })
                    // The popup opens once the popover is gone, so it keeps the focus.
                    .onDisappear {
                        guard let id = opening else { return }
                        opening = nil
                        if let anchor = model.anchor(for: id) { model.invoke(id, anchor: anchor) }
                    }
                }
        }
        .onAppear { model.refresh() }
        .onChange(of: model.activeHandle) { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: ChromiumExtensionActionsModel.installedExtensionsChanged)) { notification in
            model.refresh(for: notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }
}

/// Chrome's request-access button: extensions that want this site, granted with one click.
private struct ExtensionAccessButton: View {
    let model: ChromiumExtensionActionsModel
    let request: ChromiumExtensionActionsModel.AccessRequest

    var body: some View {
        let icons = request.ids.prefix(3).compactMap { id in model.actions.first { $0.id == id }?.icon }
        Button { model.grantAccess() } label: {
            HStack(spacing: 2) {
                ForEach(icons.indices, id: \.self) { Image(nsImage: icons[$0]).resizable().frame(width: 14, height: 14) }
                Text("Allow").font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 6).frame(height: 22)
            .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .help(request.tooltip)
        .accessibilityLabel(request.tooltip)
        .accessibilityIdentifier("control.extensionRequestAccess")
        .padding(.trailing, 2)
    }
}

/// An AppKit button, because an extension popup points at a native view.
private struct ExtensionsMenuButton: NSViewRepresentable {
    let model: ChromiumExtensionActionsModel
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
        button.setAccessibilityIdentifier("control.extensions")
        model.menuButton = button
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.toggle = toggle
        model.menuButton = button
        button.contentTintColor = failed ? .systemOrange : .secondaryLabelColor
    }
    static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) {
        button.target = nil
        button.action = nil
    }
}

private struct ExtensionsPopover: View {
    let model: ChromiumExtensionActionsModel
    let open: (String) -> Void
    let togglePin: (ChromiumExtensionActionsModel.Action) -> Void
    let manage: (() -> Void)?

    var body: some View {
        let active = model.activeHandle != nil
        VStack(alignment: .leading, spacing: 0) {
            Text("Extensions").font(.headline).padding(.horizontal, 8).padding(.bottom, 6)
            if model.actions.isEmpty {
                Text("No extensions yet.").foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 4)
            }
            ForEach(model.actions) { action in
                ExtensionRow(action: action, active: active, open: { open(action.id) }, togglePin: { togglePin(action) })
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
                    .accessibilityIdentifier("control.extensions.manage")
            }
        }
        .padding(8)
        .frame(width: 280)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.extensions")
    }
}

private struct ExtensionRow: View {
    let action: ChromiumExtensionActionsModel.Action
    let active: Bool
    let open: () -> Void
    let togglePin: () -> Void

    var body: some View {
        // The pin is the row's sibling, not inside its button, so it stays its own control (as in Chrome's menu).
        HStack(spacing: 0) {
            PopoverRow(action: open) {
                HStack(spacing: 8) {
                    Group {
                        if let icon = action.icon { Image(nsImage: icon).resizable() } else { Image(systemName: "puzzlepiece.extension") }
                    }
                    .frame(width: 16, height: 16)
                    Text(action.name).lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .help(action.title.isEmpty ? action.name : action.title)
            .accessibilityIdentifier("control.extensionRow.\(action.id)")
            Button(action: togglePin) {
                Image(systemName: action.pinned ? "pin.fill" : "pin").foregroundStyle(action.pinned ? .primary : .secondary)
                    .frame(width: 28, height: 28).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(action.forcePinned)
            .help(action.pinned ? "Unpin from Address Bar" : "Pin to Address Bar")
            .accessibilityLabel(action.pinned ? "Unpin \(action.name)" : "Pin \(action.name)")
            .accessibilityIdentifier("control.extensionPin.\(action.id)")
        }
        .disabled(!active)
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

/// A toolbar action button: click runs the action, right-click (or control-click) shows Chromium's menu for it.
private final class ExtensionActionButton: NSButton {
    var showMenu: ((NSButton) -> Void)?
    override func rightMouseDown(with event: NSEvent) { showMenu?(self) }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let showMenu { showMenu(self) } else { super.mouseDown(with: event) }
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
        let button = ExtensionActionButton(frame: .zero)
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked(_:))
        button.isBordered = false
        button.imagePosition = .imageOnly
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.model = model
        coordinator.id = action.id
        model.register(button, for: action.id)
        (button as? ExtensionActionButton)?.showMenu = { [weak coordinator] sender in
            guard let coordinator else { return }
            coordinator.model.showMenu(coordinator.id, anchor: sender)
        }
        button.image = action.icon ?? NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: action.name)
        button.imageScaling = .scaleProportionallyDown
        let active = model.activeHandle != nil
        button.toolTip = active ? (action.title.isEmpty ? action.name : action.title)
            : "Extensions aren't available on this page."
        button.setAccessibilityLabel(action.title.isEmpty ? action.name : action.title)
        button.setAccessibilityIdentifier("control.extensionAction.\(action.id)")
        button.isEnabled = active
    }
    static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) {
        button.target = nil
        button.action = nil
        (button as? ExtensionActionButton)?.showMenu = nil
    }
}
#endif
