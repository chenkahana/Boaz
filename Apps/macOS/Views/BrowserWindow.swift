import AppKit
import BoazKit
import SwiftUI
import WebKit

/// Arc's window: the space's gradient fills the whole window, the sidebar sits on it with the traffic lights,
/// and web content is an inset rounded card.
struct BrowserWindow: View {
    @Environment(MacModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var browser: BrowserState
    @AppStorage("sidebarWidth") private var sidebarWidth = 250.0
    @AppStorage(Preferences.skipsPinnedRemovalWarningKey) private var skipsPinnedRemovalWarning = false

    init(incognito: Bool) {
        _browser = State(initialValue: BrowserState(incognito: incognito))
    }

    init(browser: BrowserState) {
        _browser = State(initialValue: browser)
    }

    var body: some View {
        @Bindable var browser = browser
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                if browser.sidebarVisible {
                    SidebarView()
                        .frame(width: sidebarWidth)
                        .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                    SidebarResizeHandle(width: $sidebarWidth)
                }
                ContentArea()
            }
            if !browser.sidebarVisible { PeekingSidebar(width: sidebarWidth) }
        }
        .background { WindowBackdrop() }
        .overlay {
            if let mode = browser.commandMode {
                CommandBar(mode: mode)
                    .id(browser.commandSession)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) { ToastView() }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: browser.commandMode)
        .background { AlternateShortcuts() }
        .background(WindowAccessor { browser.attach($0) })
        .ignoresSafeArea()
        .frame(minWidth: 720, minHeight: 460)
        .environment(browser)
        .focusedSceneValue(browser)
        // Names the window in the Window menu, Mission Control and VoiceOver; the title bar itself stays hidden.
        .navigationTitle(windowTitle)
        .preferredColorScheme(browser.isIncognito ? .dark : nil)
        .environment(\.isPrivateBrowsing, browser.isIncognito)
        .sheet(item: $browser.spaceEditor) { request in MacSpaceEditor(request: request).environment(model).environment(browser) }
        .sheet(isPresented: $browser.showImport) {
            ArcImportView(store: model.store,
                          applyKeyBindings: { try MacModel.shared.keyBindings.applyArcKeyBindings(fileURL: $0) })
        }
        .sheet(item: $browser.onboarding) { OnboardingView(start: $0).environment(model).environment(browser) }
        .sheet(item: $browser.rename) { request in RenameSheet(request: request).environment(browser) }
        .sheet(item: $browser.ai) { MacAISheet(request: $0).environment(model).environment(browser) }
        .sheet(item: $browser.popup) { PopupSheet(popup: $0) }
        .devToolsSheets(browser)
        .sheet(item: $browser.extensionSheet) { sheet in
            Group {
                switch sheet {
                case .manage: ExtensionsManagerView()
                case .confirm(let pending): ConfirmExtensionView(pending: pending)
                case .webStore(let text):
                    #if DIRECT_DISTRIBUTION
                    WebStoreInstallView(text: text)
                    #else
                    let _ = text
                    #endif
                }
            }
            .environment(browser)
        }
        .confirmationDialog("Delete \"\(browser.spaceToDelete?.title ?? "")\"?",
                            isPresented: Binding { browser.spaceToDelete != nil } set: { if !$0 { browser.spaceToDelete = nil } },
                            titleVisibility: .visible, presenting: browser.spaceToDelete) { space in
            Button("Delete Space", role: .destructive) { model.deleteSpace(space) }
        } message: { space in
            Text(model.deletionMessage(for: space))
        }
        .confirmationDialog("Remove \"\(browser.pinnedTabToRemove.flatMap { $0.title ?? $0.url?.host() } ?? "Tab")\" from Pinned?",
                            isPresented: Binding { browser.pinnedTabToRemove != nil } set: { if !$0 { browser.pinnedTabToRemove = nil } },
                            titleVisibility: .visible, presenting: browser.pinnedTabToRemove) { tab in
            Button("Remove", role: .destructive) { browser.removePinned(tab) }
        } message: { _ in
            Text("It moves to the Archive.")
        }
        .dialogSuppressionToggle(isSuppressed: $skipsPinnedRemovalWarning)
        .onAppear { model.registerOpenWindow(openWindow) }
        .onChange(of: browser.currentSpaceID) { if !browser.isIncognito { model.saveOpenWindows() } }
        .onChange(of: browser.activeTabID) { if !browser.isIncognito { model.saveOpenWindows() } }
        .task {
            if !browser.isIncognito { model.beginRestoring() }
            defer { if !browser.isIncognito { model.endRestoring() } }
            // Welcome can go up before the library has loaded; a URL to open has to wait for it.
            while model.sidebar.spaces.isEmpty && model.loadError == nil && !model.needsOnboarding {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if model.needsOnboarding && !browser.isIncognito {
                model.needsOnboarding = false
                browser.onboarding = .welcome
            }
            while model.sidebar.spaces.isEmpty && model.loadError == nil { try? await Task.sleep(for: .milliseconds(100)) }
            if !browser.isIncognito, let saved = model.claimSavedWindow() {
                if let id = saved.spaceID, model.space(id) != nil { browser.currentSpaceID = id }
                if let tab = browser.tab(saved.tabID) { browser.activate(tab) }
                for _ in 0..<25 where browser.window == nil { try? await Task.sleep(for: .milliseconds(20)) }
                if let frame = saved.frame { browser.window?.setFrame(from: frame) }
                if saved.minimized == true { browser.window?.miniaturize(nil) }
            }
            browser.consumePendingURL()
        }
    }

    /// Private tabs keep their titles out of system UI, as the sidebar does.
    private var windowTitle: String {
        if browser.isIncognito { return "Incognito" }
        if let failure = browser.activeFailure { return failure.url?.host() ?? "Can't Open This Page" }
        return browser.activeTab.flatMap { $0.title ?? $0.url?.host() } ?? browser.currentSpace?.title ?? "Boaz"
    }
}

/// Extra bindings Arc also answers to for split view (⌘⇧= and ⌃⇧D) beside the menu's ⌃⇧=.
private struct AlternateShortcuts: View {
    @Environment(BrowserState.self) private var browser

    var body: some View {
        ZStack {
            Button("") { browser.toggleSplit() }.keyboardShortcut("=", modifiers: [.command, .shift])
            Button("") { browser.toggleSplit() }.keyboardShortcut("d", modifiers: [.control, .shift])
            // ⌘= as well as the menu's ⌘+, as Safari does.
            Button("") { browser.zoom(.in) }.keyboardShortcut("=", modifiers: .command).disabled(browser.activeTab == nil)
            Button("") { browser.commandMode = nil; browser.closePeek(); browser.findVisible = false }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(browser.commandMode == nil && browser.peek == nil && !browser.findVisible)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// Space gradient behind everything; incognito gets a dark violet wash.
struct WindowBackdrop: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.colorScheme) private var scheme
    /// What the translucent gradient blurs: other windows, or for the peeking sidebar the page beneath it.
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    var body: some View {
        Group {
            if browser.isIncognito {
                LinearGradient(colors: [Color(white: 0.09), Color(red: 0.16, green: 0.12, blue: 0.3)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                let style = SpaceStyle(browser.currentSpace, scheme: scheme)
                ZStack {
                    style.gradient
                    if style.grain > 0 { GrainOverlay(amount: style.grain) }
                    if style.lightStreak { LightStreak() }
                }
            }
        }
        .background(BlurredBackdrop(blending: blending))
        .animation(.easeInOut(duration: 0.45), value: browser.currentSpace)
    }
}

/// Soft light from the top-left corner, like Arc's vibrant themes; a theme option, off by default.
struct LightStreak: View {
    @Environment(\.colorScheme) private var scheme
    var radius: CGFloat = 520

    var body: some View {
        RadialGradient(colors: [.white.opacity(scheme == .dark ? 0.06 : 0.35), .clear],
                       center: .topLeading, startRadius: 0, endRadius: radius)
            .allowsHitTesting(false)
    }
}

/// Hover the left edge with the sidebar hidden to slide it out over the content.
private struct PeekingSidebar: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let width: Double

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: 8)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { browser.sidebarPeeking = true } }
                }
            if browser.sidebarPeeking {
                SidebarView()
                    .frame(width: width)
                    .background { WindowBackdrop(blending: .withinWindow) }
                    .clipShape(.rect(cornerRadius: MacRadius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: MacRadius.card, style: .continuous).strokeBorder(.white.opacity(0.25)))
                    .shadow(color: .black.opacity(0.3), radius: 24, x: 6)
                    .padding(6)
                    .onHover { inside in
                        if !inside { withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) { browser.sidebarPeeking = false } }
                    }
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            }
        }
    }
}

private struct SidebarResizeHandle: View {
    @Binding var width: Double
    @State private var start: Double?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .pointerStyle(.frameResize(position: .trailing))
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let origin = start ?? width
                    start = origin
                    width = min(420, max(200, origin + value.translation.width))
                }
                .onEnded { _ in start = nil })
    }
}

// MARK: Content

private struct ContentArea: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One layout for single and split so a pane keeps its identity (and its WebView) when a split opens or
    /// closes: a WebPage can only be hosted by one WebView at a time. For the same reason panes have no
    /// removal transition.
    private var panes: [SidebarItem] {
        if let split = browser.split, let leading = browser.tab(split.leading), let trailing = browser.tab(split.trailing) {
            return [leading, trailing]
        }
        return browser.activeTab.map { [$0] } ?? []
    }

    var body: some View {
        let panes = self.panes
        let isSplit = panes.count == 2
        let tint = SpaceStyle(browser.currentSpace, scheme: scheme).tint
        ZStack {
            if panes.isEmpty {
                EmptyContent().webCard()
            } else {
                GeometryReader { proxy in
                    let available = max(proxy.size.width - 8, 1)
                    HStack(spacing: 0) {
                        ForEach(Array(panes.enumerated()), id: \.element.id) { index, tab in
                            if index == 1 { SplitDivider(width: available) }
                            TabPane(tab: tab, inSplit: isSplit)
                                .webCard(focused: isSplit && browser.activeTabID == tab.id, tint: tint)
                                .frame(width: isSplit && index == 0 ? available * (browser.split?.fraction ?? 0.5) : nil)
                        }
                    }
                }
            }
            #if DIRECT_DISTRIBUTION
            WebStoreBanner().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            #endif
            if let peek = browser.peek {
                PeekOverlay(peek: peek)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .padding(.vertical, 8)
        .padding(.trailing, 8)
        .padding(.leading, browser.sidebarVisible ? 0 : 8)
    }
}

extension View {
    /// The rounded, slightly lifted card web content sits in, concentric with the window's corners.
    func webCard(focused: Bool = false, tint: Color = .accentColor) -> some View {
        let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(MacRadius.card)), isUniform: true)
        return self
            .clipShape(shape)
            .overlay {
                shape.stroke(focused ? tint.opacity(0.9) : .black.opacity(0.08), lineWidth: focused ? 2 : 0.5)
            }
            // Cast by the card's shape, not by the page, so it isn't drawn again each time the page redraws.
            .background {
                shape.fill(Color(nsColor: .textBackgroundColor)).shadow(color: .black.opacity(0.16), radius: 5, y: 1)
            }
    }
}

private struct EmptyContent: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let style = SpaceStyle(browser.currentSpace, scheme: scheme)
        VStack(spacing: 18) {
            Group {
                if browser.isIncognito {
                    Image(systemName: "eyeglasses").font(.system(size: 54, weight: .light))
                    Text("Incognito").font(.system(.title, design: .rounded, weight: .bold))
                    Text("Tabs here don't save history, cookies or site data.").foregroundStyle(.secondary)
                } else if let space = browser.currentSpace {
                    SpaceIcon(space: space, size: 54)
                    Text(space.title).font(.system(.title, design: .rounded, weight: .bold))
                }
            }
            .id(browser.isIncognito ? "incognito" : browser.currentSpace?.id)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))

            Button { browser.commandMode = .newTab } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    Text("Search or enter address").foregroundStyle(.secondary)
                    Spacer(minLength: 24)
                    if let shortcut = model.keyBindings.shortcut(.newTab) {
                        Text(shortcut.displayString).font(.caption.monospaced()).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .frame(width: 340)
                .glassEffect(.regular.interactive(), in: .capsule)
                .scaleEffect(hovering && !reduceMotion ? 1.02 : 1)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
            .accessibilityLabel("New Tab")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            // A wash of the space's colour so an empty window still feels like that space.
            if !browser.isIncognito {
                RadialGradient(colors: [style.tint.opacity(scheme == .dark ? 0.22 : 0.16), .clear],
                               center: .center, startRadius: 0, endRadius: 520)
            }
        }
        .animation(.smooth(duration: 0.4), value: browser.currentSpace?.id)
    }
}

private struct SplitDivider: View {
    @Environment(BrowserState.self) private var browser
    let width: CGFloat
    @State private var start: CGFloat?
    @State private var hovering = false

    var body: some View {
        Capsule()
            .fill(.white.opacity(hovering ? 0.7 : 0))
            .frame(width: 3, height: 44)
            .frame(width: 8)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { value in
                    let origin = start ?? browser.split?.fraction ?? 0.5
                    start = origin
                    browser.split?.fraction = min(0.8, max(0.2, origin + value.translation.width / width))
                }
                .onEnded { _ in start = nil })
    }
}

/// Floating preview for links that would leave a pinned tab.
private struct PeekOverlay: View {
    @Environment(BrowserState.self) private var browser
    let peek: BrowserState.Peek

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .clipShape(.rect(cornerRadius: MacRadius.card, style: .continuous))
                .onTapGesture { browser.closePeek() }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: peek.page.url?.scheme == "https" && peek.page.serverTrust != nil ? "lock.fill" : "globe")
                        .font(.caption).foregroundStyle(.secondary)
                    Text(peek.page.title.isEmpty ? (peek.page.url?.host() ?? "Loading…") : peek.page.title)
                        .font(.callout.weight(.medium)).lineLimit(1)
                    Spacer()
                    HoverIconButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Open as Tab") { browser.promotePeek() }
                    HoverIconButton(symbol: "xmark", help: "Close", hint: "Close (Esc)") { browser.closePeek() }
                }
                .padding(.horizontal, 12).frame(height: 38)
                WebView(peek.page)
                    .overlay(alignment: .top) { LoadingGlow(page: peek.page) }
            }
            .background(.regularMaterial)
            .clipShape(.rect(cornerRadius: MacRadius.panel, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: MacRadius.panel, style: .continuous).strokeBorder(.white.opacity(0.3)))
            .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
            .padding(.horizontal, 56).padding(.vertical, 32)
        }
    }
}

// MARK: Shared bits

struct HoverIconButton: View {
    let symbol: String
    /// Spoken label and tooltip; `hint` (with a shortcut) replaces the tooltip when given.
    let help: String
    var hint: String?
    var size: CGFloat = 26
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: size, height: size)
                .background(.primary.opacity(hovering ? 0.12 : 0), in: .rect(cornerRadius: MacRadius.icon, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hint ?? help)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Shows the site's real favicon once known, falling back to a tinted letter tile (no third-party
/// favicon service; same as iOS).
struct SiteMonogram: View {
    let url: URL?
    let tint: Color
    var size: CGFloat = 16

    var body: some View {
        FaviconTile(url: url, tint: tint, size: size, letterScale: 0.6)
    }
}

/// Thin gradient progress line with a glow while a page loads.
struct LoadingGlow: View {
    let page: WebPage

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(Theme.glow)
                .frame(width: proxy.size.width * page.estimatedProgress, height: 2.5)
                .shadow(color: Theme.violet.opacity(0.8), radius: 6)
                .opacity(page.isLoading ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: page.estimatedProgress)
                .animation(.easeOut(duration: 0.4), value: page.isLoading)
        }
        .frame(height: 3)
        .allowsHitTesting(false)
    }
}

private struct ToastView: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser

    var body: some View {
        if let toast = model.toast, browser.window?.isKeyWindow ?? true {
            HStack(spacing: 12) {
                Text(toast.message).font(.callout.weight(.medium))
                if toast.canUndo {
                    Button("Undo") { if !AIUndo.perform(for: toast.id) { browser.reopenClosedTab() }; model.toast = nil }
                        .buttonStyle(.plain).font(.callout.weight(.bold)).foregroundStyle(.tint)
                        .help(model.keyBindings.hint("Reopen Closed Tab", .reopenClosedTab))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .glassEffect(.regular, in: .capsule)
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .padding(.bottom, 22)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast.id)
        }
    }
}

private struct RenameSheet: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    @State var request: BrowserState.RenameRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename").font(.headline)
            TextField("Name", text: $request.text).textFieldStyle(.roundedBorder).frame(width: 280).onSubmit(save)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Rename", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private func save() {
        let text = request.text.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty {
            switch request.target {
            case .item(let item): browser.model.rename(item, to: text)
            case .space(var space):
                if let latest = browser.model.space(space.id) { space = latest }
                space.title = text
                browser.model.update(space)
            }
        }
        dismiss()
    }
}

/// Hands the hosting NSWindow to the window's state once it exists.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
    }
}

/// A blur under the backdrop's translucent gradient, so what shows through is a wash of color, never legible
/// text from another window.
private struct BlurredBackdrop: NSViewRepresentable {
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = StillEffectView()
        view.material = .underWindowBackground
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.blendingMode = blending }

    /// A drag on empty backdrop doesn't move the window, as it didn't before the blur was there.
    private final class StillEffectView: NSVisualEffectView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

/// Customize Space (the shared space editor), saving through the store; a new space opens as soon as it's created.
private struct MacSpaceEditor: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    let request: BrowserState.SpaceEditorRequest

    var body: some View {
        if let id = request.spaceID {
            if let space = model.space(id) {
                SpaceEditor(mode: .edit(space, canDelete: model.sidebar.spaces.count > 1),
                            deleteMessage: model.deletionMessage(for: space)) { title, icon, themeJSON in
                    try? model.store?.updateSpace(space.id, title: title, icon: icon, themeJSON: themeJSON)
                } onDelete: {
                    model.deleteSpace(space)
                }
            } else {
                // The space was deleted while its editor was open, here or on another Mac: there's nothing to edit.
                Color.clear.frame(width: 1, height: 1).onAppear { browser.spaceEditor = nil }
            }
        } else if let profileID = browser.currentSpace?.profileID ?? model.sidebar.profiles.first(where: \.isDefault)?.id
                    ?? model.sidebar.profiles.first?.id {
            SpaceEditor(mode: .create) { title, icon, themeJSON in
                guard let space = try? model.store?.createSpace(title: title, icon: icon, palette: .defaultPalette,
                                                                themeJSON: themeJSON, profileID: profileID) else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    browser.switchSpace(to: space.id)
                }
            }
        }
    }
}
