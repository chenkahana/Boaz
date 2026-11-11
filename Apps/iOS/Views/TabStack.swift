import BoazKit
import SwiftUI

/// The phone's tabs (private tabs in Incognito): the one showing on top, as in the carousel it opens, and the one
/// used before it peeking out beneath. A tab just opened is on top at once. Tapping opens the tab carousel.
struct TabStack: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.paneIndex) private var pane
    let cardSize: CGSize

    var body: some View {
        let tabs = model.phoneTabs
        let showing = model.tabID(inPane: pane)
        let recent = tabs.sorted { ($0.id == showing ? 1 : 0, $0.lastUsed) > ($1.id == showing ? 1 : 0, $1.lastUsed) }
            .prefix(2)
        Button {
            model.focusPane(pane)
            model.openCoverFlow()
        } label: {
            ZStack {
                if recent.isEmpty {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: cardSize.width, height: cardSize.height)
                }
                ForEach(Array(recent.enumerated()).reversed(), id: \.element.id) { index, tab in
                    card(tab)
                        // The card behind peeks out up and to the left, turned a few degrees.
                        .rotationEffect(.degrees(index == 0 ? 0 : -9), anchor: .bottom)
                        .offset(x: index == 0 ? 0 : -cardSize.width * 0.14, y: index == 0 ? 0 : -cardSize.height * 0.05)
                }
            }
            .frame(width: cardSize.width * 1.3, height: cardSize.height * 1.12)
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .bouncy(duration: 0.35), value: recent.map(\.id))
        .accessibilityLabel("Tabs")
        .accessibilityValue("\(tabs.count) open")
        .accessibilityHint("Shows your tabs side by side")
    }

    private var radius: CGFloat { max(cardSize.width * 0.16, 5) }

    private func card(_ tab: SidebarItem) -> some View {
        Group {
            if let snapshot = model.snapshots[tab.id] {
                Color.clear.overlay(alignment: .top) { Image(uiImage: snapshot).resizable().scaledToFill() }
            } else {
                Monogram(url: tab.url, tint: Theme.brand, size: min(cardSize.width * 0.55, 44))
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: radius))
        .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }
}

/// The phone's tabs as a deck in the page area, beside the rail: the current tab large and in front at the right,
/// the ones used before it peeking out to its left, most recent first. Swipe sideways to move through them, tap one to open it, swipe one up to
/// archive it. The rail switches to Tabs on Your Mac, New Tab and Settings. Folded layout only, over the page. It
/// grows out of the page as it opens and back into it as it closes, then clears `showsCoverFlow` itself.
struct TabCarousel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    /// The focused tab's index; fractional while swiping.
    @State private var position: Double = 0
    @State private var focusedID: String?
    @State private var drag: DragMode?
    @State private var liftedID: String?
    @State private var lift: CGFloat = 0
    /// The card that grows back into the page as the carousel closes.
    @State private var openingID: String?
    /// Open (or opening): drives the deck growing out of the page and everything else fading in.
    @State private var presented = false
    @State private var sheet: Sheet?
    /// A Mac tab picked in the sheet, opened once the sheet has gone.
    @State private var macTab: SidebarItem?
    /// The deck's order, fixed as it opens so picking a tab doesn't reshuffle it on the way out. The next time
    /// it opens, that tab is in front.
    @State private var order: [String] = []

    private enum Sheet: String, Identifiable { case macTabs, settings; var id: String { rawValue } }
    private enum DragMode: Equatable { case paging(from: Double), lifting, ignored }

    var body: some View {
        let tabs = phoneTabs
        let style = SpaceStyle(nil, scheme: scheme)
        GeometryReader { proxy in
            let metrics = DeckMetrics(size: proxy.size)
            ZStack(alignment: .top) {
                if tabs.isEmpty {
                    ContentUnavailableView("No Tabs", systemImage: "square.on.square",
                                           description: Text("Tabs you open on this iPhone appear here."))
                        .opacity(presentation)
                } else {
                    DeckCards(tabs: tabs, position: position, metrics: metrics, presentation: presentation,
                              heroID: heroZooms ? (openingID ?? focusedID) : nil,
                              liftedID: liftedID, lift: lift,
                              open: open, archive: archive)
                    caption(tabs, metrics: metrics)
                }
                header(count: tabs.count)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(.rect)
            .gesture(swipe(tabs, metrics: metrics))
            .simultaneousGesture(SpatialTapGesture().onEnded { value in
                // The header's buttons take their own taps.
                guard value.location.y > DeckMetrics.header else { return }
                if let id = card(at: value.location, tabs: tabs, metrics: metrics) { open(id) } else { dismiss() }
            })
        }
        .toolRail { axis in
            CarouselRail(axis: axis, hasMac: hasMac,
                         onMacTabs: { sheet = .macTabs },
                         onNewTab: newTab,
                         onSettings: { sheet = .settings })
                .opacity(presentation)
        }
        .foregroundStyle(style.foreground, style.secondary)
        .background {
            // The gradient is translucent; the page mustn't show through it.
            style.gradient.background(Color(.systemBackground)).ignoresSafeArea().opacity(presentation)
        }
        .allowsHitTesting(presented)
        .sensoryFeedback(.selection, trigger: Int(position.rounded()))
        .onAppear {
            order = tabs.map(\.id)
            let index = tabs.firstIndex { $0.id == model.activeTabID } ?? tabs.count - 1
            position = Double(max(index, 0))
            focusedID = tabs.indices.contains(index) ? tabs[index].id : nil
            withAnimation(motion) { presented = true }
        }
        // Reopened while closing: come back instead of finishing the close.
        .onChange(of: model.coverFlowRequests) {
            openingID = nil
            withAnimation(motion) { presented = true }
        }
        .onChange(of: tabs.map(\.id)) { old, new in refocus(from: old, to: new) }
        .sheet(item: $sheet, onDismiss: openMacTab) { sheet in
            switch sheet {
            case .macTabs: MacTabsSheet { macTab = $0 }
            case .settings: SettingsSheet()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, dismiss)
        .accessibilityAction(named: "Next Tab") { step(by: 1, count: tabs.count) }
        .accessibilityAction(named: "Previous Tab") { step(by: -1, count: tabs.count) }
    }

    /// The card grows back into the page.
    private var heroZooms: Bool { !reduceMotion }

    private var presentation: Double { presented ? 1 : 0 }

    /// By last use, the current tab last (in front). Tabs opened while the deck is up go in front of the rest.
    private var phoneTabs: [SidebarItem] {
        let tabs = model.phoneTabs
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return tabs.sorted { (rank[$0.id] ?? .max, $0.lastUsed) < (rank[$1.id] ?? .max, $1.lastUsed) }
    }

    private var hasMac: Bool { model.sidebar.devices.contains { $0.platform == .macOS } }

    private var motion: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .interpolatingSpring(duration: 0.42, bounce: 0.12)
    }

    private func header(count: Int) -> some View {
        HStack {
            Spacer()
            Button("Done", action: dismiss).fontWeight(.semibold)
        }
        .overlay {
            Text(count == 1 ? "1 Tab" : "\(count) Tabs")
                .font(.headline)
                .contentTransition(.numericText(value: Double(count)))
                .accessibilityAddTraits(.isHeader)
        }
        .buttonStyle(.glass)
        .padding(.horizontal, 12)
        .frame(height: DeckMetrics.header)
        .opacity(presentation)
    }

    /// The focused tab's title and host, under its card.
    private func caption(_ tabs: [SidebarItem], metrics: DeckMetrics) -> some View {
        let index = min(max(Int(position.rounded()), 0), tabs.count - 1)
        let tab = tabs[index]
        return VStack(spacing: 2) {
            Text(tab.title ?? tab.url?.host() ?? "New Tab")
                .font(.subheadline.weight(.semibold))
            Text(tab.url?.host() ?? "")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .frame(width: max(metrics.card.width + 24, 0))
        .position(x: metrics.front.x, y: metrics.size.height - DeckMetrics.footer / 2)
        .id(tab.id)
        .transition(.opacity)
        .animation(.easeOut(duration: 0.18), value: tab.id)
        .opacity(presentation)
        .accessibilityHidden(true)
    }

    // MARK: Gestures

    /// Sideways moves through the deck, following the finger; up lifts the card under the finger to archive it.
    private func swipe(_ tabs: [SidebarItem], metrics: DeckMetrics) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let x = value.translation.width, y = value.translation.height
                if drag == nil {
                    if abs(x) > abs(y) {
                        drag = .paging(from: position)
                    } else if y < 0, let id = card(at: value.startLocation, tabs: tabs, metrics: metrics) {
                        liftedID = id
                        drag = .lifting
                    } else {
                        drag = .ignored
                    }
                }
                switch drag {
                case .paging(let start):
                    position = rubberBand(start - x / metrics.unit, upper: Double(tabs.count - 1))
                case .lifting:
                    lift = y < 0 ? y : 30 * (1 - exp(-y / 30))
                default:
                    break
                }
            }
            .onEnded { value in
                switch drag {
                case .paging: settle(velocity: value.velocity.width, unit: metrics.unit, tabs: tabs)
                case .lifting: endLift(predicted: value.predictedEndTranslation.height, height: metrics.size.height)
                default: break
                }
                drag = nil
            }
    }

    /// Lands on the card the flick carries to, carrying the finger's speed into the spring.
    private func settle(velocity: CGFloat, unit: CGFloat, tabs: [SidebarItem]) {
        guard !tabs.isEmpty else { return }
        let speed = -Double(velocity / unit)
        let target = min(max((position + speed * 0.22).rounded(), 0), Double(tabs.count - 1))
        let distance = target - position
        let initial = abs(distance) > 0.01 ? max(min(speed / distance, 30), -30) : 0
        focusedID = tabs[Int(target)].id
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .interpolatingSpring(duration: 0.45, bounce: 0.1,
                                                                                     initialVelocity: initial)) {
            position = target
        }
    }

    private func endLift(predicted: CGFloat, height: CGFloat) {
        guard let id = liftedID else { return }
        if lift < -110 || (lift < 0 && predicted < -360) {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .snappy(duration: 0.28)) { lift = -height } completion: {
                archive(id)
                lift = 0
                liftedID = nil
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { lift = 0 }
        }
    }

    private func rubberBand(_ value: Double, upper: Double) -> Double {
        if value < 0 { return -0.35 * (1 - exp(value / 0.35)) }
        if value > upper { return upper + 0.35 * (1 - exp(-(value - upper) / 0.35)) }
        return value
    }

    /// The front-most card under `point`.
    private func card(at point: CGPoint, tabs: [SidebarItem], metrics: DeckMetrics) -> String? {
        for index in metrics.visible(around: position, count: tabs.count).reversed() {
            let place = metrics.placement(offset: Double(index) - position)
            guard place.opacity > 0.2 else { continue }
            let size = CGSize(width: metrics.card.width * place.scale, height: metrics.card.height * place.scale)
            let frame = CGRect(x: place.center.x - size.width / 2, y: place.center.y - size.height / 2,
                               width: size.width, height: size.height)
            if frame.contains(point) { return tabs[index].id }
        }
        return nil
    }

    // MARK: Actions

    private func step(by offset: Int, count: Int) {
        guard count > 0 else { return }
        let target = min(max(Int(position.rounded()) + offset, 0), count - 1)
        focusedID = phoneTabs[target].id
        withAnimation(motion) { position = Double(target) }
    }

    /// Keeps the focused card in front as tabs come and go; when it goes, the one before it comes forward. A tab
    /// that comes back (Undo) comes to the front.
    private func refocus(from old: [String], to new: [String]) {
        guard !new.isEmpty else { return }
        let added = Set(new).subtracting(old)
        if added.count == 1, let id = added.first, let index = new.firstIndex(of: id) {
            focusedID = id
            withAnimation(motion) { position = Double(index) }
        } else if let focusedID, let index = new.firstIndex(of: focusedID) {
            var unanimated = Transaction()
            unanimated.disablesAnimations = true
            withTransaction(unanimated) { position = Double(index) }
        } else {
            let was = focusedID.flatMap { old.firstIndex(of: $0) } ?? Int(position.rounded())
            let index = min(max(was - 1, 0), new.count - 1)
            focusedID = new[index]
            withAnimation(motion) { position = Double(index) }
        }
    }

    private func open(_ id: String) {
        guard presented, let tab = phoneTabs.first(where: { $0.id == id }) else { return }
        openingID = id
        // No animation: the page changes underneath the deck, which then grows back into it.
        if tab.id != model.activeTabID { model.activate(tab) }
        close()
    }

    private func archive(_ id: String) {
        guard let tab = phoneTabs.first(where: { $0.id == id }) else { return }
        withAnimation(.snappy) { model.close(tab) }
    }

    private func dismiss() {
        guard presented else { return }
        openingID = model.activeTabID
        close()
    }

    /// Animates out, then leaves the screen, unless it was reopened in the meantime.
    private func close() {
        withAnimation(motion) { presented = false } completion: {
            // The card now lies over the page, showing just what the page shows: take it away at once.
            if !presented { withTransaction(\.disablesAnimations, true) { model.showsCoverFlow = false } }
        }
    }

    private func newTab() {
        model.showsCoverFlow = false
        withAnimation(BottomPanelStyle.motion) { model.beginSearch(.newTab) }
    }

    /// The Mac's tab opens as a copy on top of the stack (`AppModel.activate`).
    private func openMacTab() {
        guard let tab = macTab else { return }
        macTab = nil
        model.showsCoverFlow = false
        model.activate(tab)
    }
}

/// The deck's geometry for a given size: the card size, where the front card sits, and where every other card
/// sits relative to it.
private struct DeckMetrics {
    static let header: CGFloat = 56
    static let footer: CGFloat = 64
    let size: CGSize

    /// The page's own proportions, so a page snapshot fills it.
    var card: CGSize {
        let aspect = size.width / max(size.height, 1)
        var height = max(size.height - Self.header - Self.footer, 80) * 0.96
        var width = height * aspect
        if width > size.width * 0.66 {
            width = size.width * 0.66
            height = width / aspect
        }
        return CGSize(width: width, height: height)
    }

    var front: CGPoint {
        CGPoint(x: size.width - 16 - card.width / 2, y: Self.header + (size.height - Self.header - Self.footer) / 2)
    }

    /// How far one step through the deck moves the front card: fully off to the right.
    var unit: CGFloat { card.width + 56 }

    /// The room left of the front card that earlier cards peek into.
    private var peekSpan: CGFloat { max(front.x - card.width / 2 - 12, 24) }

    /// Cards worth drawing: up to four earlier ones, and the next one while it slides in.
    func visible(around position: Double, count: Int) -> Range<Int> {
        guard count > 0 else { return 0..<0 }
        // `position` can still point past the end for a frame after tabs vanish, before refocusing catches up.
        let lower = min(max(Int((position - 4).rounded(.down)), 0), count - 1)
        let upper = min(Int((position + 1).rounded(.up)), count - 1)
        return lower..<(max(lower, upper) + 1)
    }

    /// `offset` is the card's index minus the focused position: negative for earlier cards.
    func placement(offset: Double) -> (center: CGPoint, scale: CGFloat, opacity: Double, dim: Double) {
        if offset > 0 {
            return (CGPoint(x: front.x + offset * unit, y: front.y), 1, 1, 0)
        }
        let depth = -offset
        let x = front.x - peekSpan * (1 - pow(0.5, depth))
        return (CGPoint(x: x, y: front.y), 1 - 0.06 * min(depth, 5), min(max(4 - depth, 0), 1), min(depth, 4) * 0.07)
    }
}

/// The visible cards, laid out for a position that animates frame by frame, so springs between cards and
/// cards entering or leaving the deck move smoothly.
private struct DeckCards: View, Animatable {
    let tabs: [SidebarItem]
    var position: Double
    let metrics: DeckMetrics
    var presentation: Double
    /// The card that grows into the page as the carousel opens and closes.
    let heroID: String?
    let liftedID: String?
    let lift: CGFloat
    let open: (String) -> Void
    let archive: (String) -> Void

    // Nonisolated, so the `Animatable` conformance isn't isolated to the main actor (this module's default).
    nonisolated var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(position, presentation) }
        set { (position, presentation) = (newValue.first, newValue.second) }
    }

    var body: some View {
        let range = metrics.visible(around: position, count: tabs.count)
        ZStack {
            ForEach(tabs[range]) { tab in
                card(tab, index: tabs.firstIndex { $0.id == tab.id } ?? 0)
            }
        }
        .frame(width: metrics.size.width, height: metrics.size.height)
        // Later cards wait off to the right; they slide in from the rail's edge, not over the rail.
        .clipped()
    }

    private func card(_ tab: SidebarItem, index: Int) -> some View {
        let place = metrics.placement(offset: Double(index) - position)
        let p = CGFloat(presentation)
        let isHero = tab.id == heroID
        let isLifted = tab.id == liftedID
        let full = CGPoint(x: metrics.size.width / 2, y: metrics.size.height / 2)
        let fullScale = metrics.size.width / max(metrics.card.width, 1)
        let center = isHero
            ? CGPoint(x: full.x + (place.center.x - full.x) * p, y: full.y + (place.center.y - full.y) * p)
            : CGPoint(x: place.center.x - (1 - p) * 60, y: place.center.y)
        let scale = isHero ? fullScale + (place.scale - fullScale) * p
            : place.scale * (heroID == nil ? 0.94 + 0.06 * p : 1)
        let opacity = isHero ? 1 : place.opacity * Double(p)
        return DeckCard(tab: tab, radius: isHero ? 22 * p : 22, dim: place.dim * Double(p),
                        shadow: Double(p))
            .frame(width: metrics.card.width, height: metrics.card.height)
            .scaleEffect(scale)
            .opacity(isLifted ? opacity * Double(max(0.3, 1 + lift / 600)) : opacity)
            .position(x: center.x, y: center.y + (isLifted ? lift : 0))
            .zIndex(Double(index))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tab.title ?? tab.url?.host() ?? "New Tab")
            .accessibilityValue(tab.url?.host() ?? "")
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the tab")
            .accessibilityAction { open(tab.id) }
            .accessibilityAction(named: "Archive") { archive(tab.id) }
            .accessibilityHidden(opacity < 0.2 || place.center.x - metrics.card.width / 2 > metrics.size.width)
    }
}

/// One card: the page as last seen, or its icon until there's a snapshot.
private struct DeckCard: View {
    @Environment(AppModel.self) private var model
    let tab: SidebarItem
    let radius: CGFloat
    let dim: Double
    let shadow: Double

    var body: some View {
        ZStack {
            Rectangle().fill(.background)
            if let snapshot = model.snapshots[tab.id] {
                Color.clear.overlay(alignment: .top) { Image(uiImage: snapshot).resizable().scaledToFill() }
            } else {
                Monogram(url: tab.url, tint: Theme.brand, size: 64)
            }
            Color.black.opacity(dim)
        }
        .clipShape(.rect(cornerRadius: radius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.primary.opacity(0.12 * shadow), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.28 * shadow), radius: 16, x: -6, y: 8)
    }
}

/// The rail while the carousel is up.
private struct CarouselRail: View {
    let axis: Axis
    let hasMac: Bool
    let onMacTabs: () -> Void
    let onNewTab: () -> Void
    let onSettings: () -> Void

    var body: some View {
        if axis == .vertical {
            RailColumn {
                RailButton(symbol: "desktopcomputer", label: "Tabs on Your Mac", action: onMacTabs)
                    .disabled(!hasMac)
                    .opacity(hasMac ? 1 : 0.4)
                RailButton(symbol: "plus", label: "New Tab", action: onNewTab)
            } bottom: {
                RailButton(symbol: "gearshape", label: "Settings", action: onSettings)
            }
        } else {
            HStack(spacing: 10) {
                BarDock {
                    RailButton(symbol: "desktopcomputer", label: "Tabs on Your Mac", action: onMacTabs)
                        .disabled(!hasMac)
                        .opacity(hasMac ? 1 : 0.4)
                    RailButton(symbol: "plus", label: "New Tab", action: onNewTab)
                }
                Spacer(minLength: 0)
                BarDock { RailButton(symbol: "gearshape", label: "Settings", action: onSettings) }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 4)
        }
    }
}

/// The Mac's sidebar, one space at a time: favorites, pinned tabs and folders, then the Today tabs open on the user's
/// Macs. Swipe or use the space bar to change spaces. Read-only: picking a page opens it in a new tab here. Opens on
/// the space it last showed.
private struct MacTabsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let pick: (SidebarItem) -> Void
    @State private var spaceID: String?
    @AppStorage("macTabsSpaceID") private var lastSpaceID = ""

    var body: some View {
        let spaces = model.spaces
        let style = SpaceStyle(spaces.first { $0.id == spaceID }, scheme: scheme)
        NavigationStack {
            TabView(selection: $spaceID) {
                ForEach(spaces) { space in
                    MacSpaceColumn(space: space) { pick($0); dismiss() }.tag(Optional(space.id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .safeAreaInset(edge: .bottom) { if spaces.count > 1 { spaceBar(spaces) } }
            .foregroundStyle(style.foreground, style.secondary)
            .background { style.gradient.background(Color(.systemBackground)).ignoresSafeArea() }
            .animation(MacRowStyle.motion, value: spaceID)
            .navigationTitle("Tabs on Your Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } } }
        }
        .onAppear { if spaceID == nil { spaceID = spaces.first { $0.id == lastSpaceID }?.id ?? spaces.first?.id } }
        .onChange(of: spaceID) { if let spaceID { lastSpaceID = spaceID } }
    }

    /// The Mac's space buttons: each space's icon, or a dot.
    private func spaceBar(_ spaces: [Space]) -> some View {
        HStack(spacing: 10) {
            ForEach(spaces) { space in
                let selected = space.id == spaceID
                Button {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : MacRowStyle.motion) { spaceID = space.id }
                } label: {
                    Group {
                        if space.icon != nil { SpaceIcon(space: space, size: 17) } else { Circle().frame(width: 7, height: 7) }
                    }
                    .foregroundStyle(selected ? .primary : .secondary)
                    .frame(width: 36, height: 36)
                    .background(selected ? MacRowStyle.selection : .clear, in: .circle)
                    .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(space.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}

/// One space as the Mac's sidebar shows it, in the space's tint.
private struct MacSpaceColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    let space: Space
    let open: (SidebarItem) -> Void

    var body: some View {
        let tint = SpaceStyle(space, scheme: scheme).tint
        let favorites = model.sidebar.favorites(profileID: space.profileID).filter { $0.kind == .tab }
        let pinned = model.sidebar.container(.pinned, in: space.id).map { model.sidebar.children(of: $0.id) } ?? []
        let today = macTodayTabs
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    SpaceIcon(space: space, size: 17).frame(width: 22)
                    Text(space.title).font(.headline).lineLimit(1)
                }
                .padding(.horizontal, 8)
                .frame(height: 44)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
                if !favorites.isEmpty { favoritesGrid(favorites, tint: tint).padding(.bottom, 8) }
                ForEach(pinned) { MacItemRow(item: $0, depth: 0, tint: tint, open: open) }
                Rectangle().fill(.primary.opacity(0.15)).frame(height: 1)
                    .padding(.horizontal, 8).padding(.vertical, 12)
                    .accessibilityHidden(true)
                if today.isEmpty {
                    Text("No tabs open on your Mac in this space.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                }
                ForEach(today) { MacItemRow(item: $0, depth: 0, tint: tint, open: open) }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.never)
    }

    /// The space's Today tabs opened on a Mac, or from before devices were recorded, with the Mac's folders under
    /// Today flattened.
    private var macTodayTabs: [SidebarItem] {
        let macs = Set(model.sidebar.devices.filter { $0.platform == .macOS }.map(\.id))
        func tabs(under parent: String) -> [SidebarItem] {
            model.sidebar.children(of: parent)
                .flatMap { $0.kind == .folder ? tabs(under: $0.id) : $0.kind == .tab ? [$0] : [] }
        }
        return model.sidebar.container(.unpinned, in: space.id).map { tabs(under: $0.id) }?
            .filter { $0.url != nil && $0.deviceID.map(macs.contains) ?? true } ?? []
    }

    /// Up to four a row, the rows as even as they can be, as on the Mac.
    private func favoritesGrid(_ favorites: [SidebarItem], tint: Color) -> some View {
        let rows = (favorites.count + 3) / 4
        let columns = max(3, (favorites.count + rows - 1) / rows)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
            ForEach(favorites) { tab in
                Button { open(tab) } label: {
                    Monogram(url: tab.url, tint: tint, size: 26)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        // The icon's own color; a black, white or gray icon keeps the neutral fill.
                        .background(Favicons.shared.resolved(for: tab.url)?.color.map { $0.opacity(0.24) } ?? MacRowStyle.hover,
                                    in: .rect(cornerRadius: 12, style: .continuous))
                        .contentShape(.rect)
                }
                .buttonStyle(PressableStyle())
                .disabled(tab.url == nil)
                .accessibilityLabel(tab.title ?? tab.url?.host() ?? "Favorite")
            }
        }
    }
}

/// A pinned or Today row: favicon and title, as on the Mac. Folders open and close here without changing the Mac's.
private struct MacItemRow: View {
    @Environment(AppModel.self) private var model
    let item: SidebarItem
    let depth: Int
    let tint: Color
    let open: (SidebarItem) -> Void
    @State private var expanded: Bool?

    var body: some View {
        let isFolder = item.kind == .folder
        let isExpanded = expanded ?? item.isExpanded
        VStack(alignment: .leading, spacing: 2) {
            Button {
                if isFolder { withAnimation(MacRowStyle.motion) { expanded = !isExpanded } } else { open(item) }
            } label: {
                HStack(spacing: 10) {
                    if isFolder {
                        Image(systemName: isExpanded ? "folder.fill" : "folder")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 22)
                    } else {
                        Monogram(url: item.url, tint: tint, size: 20).frame(width: 22)
                    }
                    Text(isFolder ? item.title ?? "Folder" : item.title ?? item.url?.host() ?? "New Tab").lineLimit(1)
                    Spacer(minLength: 0)
                    if isFolder {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                }
                .padding(.leading, 8 + CGFloat(depth) * 16)
                .padding(.trailing, 8)
                .frame(height: 44)
            }
            .buttonStyle(MacRowStyle())
            .disabled(!isFolder && item.url == nil)
            .accessibilityValue(isFolder ? (isExpanded ? "Expanded" : "Collapsed") : item.url?.host() ?? "")
            if isFolder && isExpanded {
                ForEach(model.sidebar.children(of: item.id)) { MacItemRow(item: $0, depth: depth + 1, tint: tint, open: open) }
            }
        }
    }
}

/// The Mac sidebar's fills and motion (docs/design.md): the label color at 12% under a pressed row, half that at rest
/// under a favorite.
private struct MacRowStyle: ButtonStyle {
    static let selection = Color.primary.opacity(0.12)
    static let hover = Color.primary.opacity(0.06)
    static let motion = Animation.smooth(duration: 0.2)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .background(configuration.isPressed ? Self.selection : .clear, in: .rect(cornerRadius: 10, style: .continuous))
    }
}

private extension SidebarItem {
    var lastUsed: Date { lastActiveAt ?? createdAt }
}
