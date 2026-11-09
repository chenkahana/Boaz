import BoazKit
import SwiftUI

/// Home: spaces page horizontally, each on its own themed gradient, with favorites, pins and today's tabs.
struct SpaceHome: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.homeControlsElsewhere) private var homeControlsElsewhere
    var zoom: Namespace.ID?

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isIncognito {
                IncognitoPage(zoom: zoom).transition(.opacity)
            } else {
                TabView(selection: $model.currentSpaceID) {
                    ForEach(model.spaces) { space in
                        SpacePage(space: space, zoom: zoom).tag(Optional(space.id))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .transition(.opacity)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .toolRail { axis in
            if !homeControlsElsewhere {
                HomeBar(axis: axis).environment(\.colorScheme, model.isIncognito ? .dark : scheme)
            }
        }
        // One full-bleed backdrop so the colour reaches under the sensor column and the bar; content stays in the safe area.
        .background {
            Group {
                if model.isIncognito {
                    LinearGradient(colors: [Color(white: 0.08), Theme.indigo(3)], startPoint: .top, endPoint: .bottom)
                        .environment(\.colorScheme, .dark)
                } else {
                    SpaceStyle(model.currentSpace, scheme: scheme).gradient
                }
            }
            .ignoresSafeArea()
            .animation(.smooth(duration: 0.45), value: model.currentSpaceID)
        }
        .animation(.easeInOut(duration: 0.35), value: model.isIncognito)
        .sensoryFeedback(.selection, trigger: model.currentSpaceID)
    }
}

/// Private mode: tabs live only in memory with a non-persistent website data store.
private struct IncognitoPage: View {
    @Environment(AppModel.self) private var model
    let zoom: Namespace.ID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Image(systemName: "eyeglasses").font(.title)
                    Text("Incognito").font(.system(.largeTitle, design: .rounded, weight: .bold))
                }
                Text("Private tabs don't save history, cookies or site data, and close when you leave Incognito.")
                    .font(.callout).foregroundStyle(.white.opacity(0.7))
                TodayGrid(tabs: model.incognitoTabs, tint: Theme.violet, zoom: zoom)
                Button("Leave Incognito") { model.setIncognito(false) }
                    .buttonStyle(.bordered).tint(.white)
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 120)
        }
        .collapsesToolRail()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

private struct SpacePage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isSidebar) private var isSidebar
    @Environment(\.sidebar) private var sidebar
    let space: Space
    let zoom: Namespace.ID?

    var body: some View {
        let style = SpaceStyle(space, scheme: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: isSidebar ? 14 : 20) {
                HStack(spacing: isSidebar ? 8 : 10) {
                    // Tapping the name switches, adds, edits or reorders spaces.
                    SpaceTitleMenu(space: space) {
                        HStack(spacing: isSidebar ? 8 : 10) {
                            Text(space.icon ?? "✦").font(isSidebar ? .title3 : .title)
                            Text(space.title).font(.system(isSidebar ? .title2 : .largeTitle, design: .rounded, weight: .bold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font((isSidebar ? Font.footnote : .callout).weight(.bold))
                                .opacity(0.45)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    if isSidebar, let sidebar {
                        Spacer(minLength: 4)
                        Button("Hide Sidebar", systemImage: "sidebar.left", action: sidebar.toggle)
                            .labelStyle(.iconOnly)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                }
                .padding(.top, 8)

                if isSidebar { searchField(style) }

                let favorites = model.favorites(for: space)
                if !favorites.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: isSidebar ? 8 : 12), count: 4),
                              spacing: isSidebar ? 8 : 12) {
                        ForEach(favorites) { FavoriteTile(tab: $0, tint: style.tint) }
                    }
                }

                let pinned = model.pinnedItems(in: space)
                if !pinned.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(pinned) { PinnedRow(item: $0, tint: style.tint, depth: 0) }
                    }
                    .padding(isSidebar ? 4 : 8)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: Theme.Radius.tile))
                }

                let today = model.todayTabs(in: space)
                if isSidebar {
                    // The sidebar lists Today like Arc: a new-tab row, then one row per tab.
                    VStack(spacing: 0) {
                        Capsule().fill(style.foreground.opacity(0.12)).frame(height: 1)
                            .padding(.horizontal, 10).padding(.bottom, 6)
                        TodayRow.newTab(tint: style.tint)
                        ForEach(today) { TodayRow(tab: $0, tint: style.tint) }
                    }
                    .animation(.snappy, value: today.map(\.id))
                } else if today.isEmpty {
                    searchField(style)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Today")
                            .font(.footnote.weight(.semibold)).textCase(.uppercase)
                            .foregroundStyle(style.foreground.opacity(0.6))
                            .accessibilityAddTraits(.isHeader)
                        // The open page zooms back into the stack, unless the cover flow is the one showing.
                        TabStack(cardSize: CGSize(width: 116, height: 160), zoom: model.showsCoverFlow ? nil : zoom)
                            .frame(maxWidth: .infinity)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, isSidebar ? 14 : 20)
            .padding(.top, isSidebar ? 12 : 24)
            .padding(.bottom, isSidebar ? 40 : 120)
            .animation(.snappy, value: model.todayTabs(in: space).isEmpty)
        }
        .scrollIndicators(.hidden)
        .collapsesToolRail()
        .foregroundStyle(style.foreground)
    }

    private func searchField(_ style: SpaceStyle) -> some View {
        Button { model.beginSearch(.newTab) } label: {
            Label("Search or enter address", systemImage: "magnifyingglass")
                .font(.callout)
                .lineLimit(1)
                .foregroundStyle(style.foreground.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, isSidebar ? 14 : 18).padding(.vertical, isSidebar ? 11 : 15)
                .glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// A Today tab as a sidebar row: tap to open, × (or the context menu) to close.
private struct TodayRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sidebar) private var sidebar
    let tab: SidebarItem
    let tint: Color

    var body: some View {
        let active = model.activeTabID == tab.id
        Button { model.activate(tab); sidebar?.didPick() } label: {
            HStack(spacing: 10) {
                Monogram(url: tab.url, tint: tint, size: 22)
                Text(tab.title ?? tab.url?.host() ?? "New Tab").lineLimit(1)
                    .fontWeight(active ? .semibold : .regular)
                Spacer(minLength: 0)
            }
            .font(.callout)
            .padding(.vertical, 7).padding(.leading, 10).padding(.trailing, 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // The row stays 36pt for a dense list; the close target is 44pt wide and spans the row's full height.
        .overlay(alignment: .trailing) {
            Button("Close", systemImage: "xmark") { withAnimation(.snappy) { model.close(tab) } }
                .labelStyle(.iconOnly)
                .font(.caption.weight(.semibold))
                .opacity(active ? 0.8 : 0.35)
                .frame(width: 44)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .buttonStyle(.plain)
        }
        .selectedRowBackground(active)
        .animation(.snappy, value: active)
        .contextMenu {
            Button("Pin", systemImage: "pin") { model.togglePin(tab) }
            Button("Archive Tab", systemImage: "archivebox", role: .destructive) { model.close(tab) }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }

    static func newTab(tint: Color) -> some View { NewTabRow() }
}

private struct NewTabRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button { model.beginSearch(.newTab) } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.callout.weight(.semibold)).frame(width: 22)
                Text("New Tab")
                Spacer(minLength: 0)
            }
            .font(.callout)
            .opacity(0.7)
            .padding(.vertical, 7).padding(.horizontal, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

/// Home toolbar: search, space dots and the menu. Runs down the right-hand rail, or across the bottom.
struct HomeBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sidebar) private var sidebar
    let axis: Axis

    var body: some View {
        if axis == .vertical {
            RailColumn {
                Button { model.beginSearch(.newTab) } label: {
                    RailGlyph(symbol: searchSymbol)
                        .foregroundStyle(.white)
                        .background(Theme.brand.gradient, in: .circle)
                        .padding(2)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Search")
                spaceDots.padding(.vertical, 8)
            } bottom: {
                if let sidebar { SidebarRailButton(sidebar: sidebar) }
                HomeMenu(inDock: true)
            } nub: {
                RailGlyph(symbol: searchSymbol, size: 30)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .background(Theme.brand.gradient, in: .circle)
            }
        } else {
            VStack(spacing: 8) {
                // Its own glass capsule, so the dots don't float over the cards scrolling beneath.
                spaceDots
                    .padding(.horizontal, 6)
                    .glassEffect(.regular, in: .capsule)
                HStack(spacing: 10) {
                    if let sidebar {
                        Button(action: sidebar.toggle) { RailIcon(symbol: "sidebar.left", size: 50) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(sidebar.isCollapsed ? "Show Sidebar" : "Hide Sidebar")
                    }
                    HomeMenu()
                    Button { model.beginSearch(.newTab) } label: {
                        HStack {
                            Image(systemName: model.isIncognito ? "eyeglasses" : "magnifyingglass")
                            Text(model.isIncognito ? "Private search" : "Search or enter address")
                            Spacer()
                            Image(systemName: "plus")
                        }
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
        }
    }

    private var searchSymbol: String { model.isIncognito ? "eyeglasses" : "magnifyingglass" }

    @ViewBuilder private var spaceDots: some View {
        if model.spaces.count > 1, !model.isIncognito {
            let stack = axis.stack(spacing: 0)
            stack {
                ForEach(model.spaces) { space in
                    let current = space.id == model.currentSpaceID
                    Button { withAnimation(.smooth) { model.currentSpaceID = space.id } } label: {
                        Capsule()
                            .fill(.primary.opacity(current ? 0.8 : 0.25))
                            .frame(width: axis == .horizontal && current ? 18 : 6,
                                   height: axis == .vertical && current ? 18 : 6)
                            // Padding widens each dot's hit area without moving the dots apart.
                            .padding(axis == .horizontal ? .horizontal : .vertical, 3)
                            .padding(axis == .horizontal ? .vertical : .horizontal, 7)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.bouncy(duration: 0.35, extraBounce: 0.1), value: model.currentSpaceID)
            // VoiceOver reads the strip as one control and swipes up or down to change space.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Space")
            .accessibilityValue(model.spaces.first { $0.id == model.currentSpaceID }?.title ?? "")
            .accessibilityAdjustableAction { direction in
                guard let index = model.spaces.firstIndex(where: { $0.id == model.currentSpaceID }) else { return }
                let next = direction == .increment ? index + 1 : direction == .decrement ? index - 1 : index
                guard model.spaces.indices.contains(next) else { return }
                withAnimation(.smooth) { model.currentSpaceID = model.spaces[next].id }
            }
        }
    }
}

/// Library, Incognito and Settings.
struct HomeMenu: View {
    @Environment(AppModel.self) private var model
    var inDock = false

    var body: some View {
        Menu {
            HomeMenuItems()
        } label: {
            if inDock { RailGlyph(symbol: "line.3.horizontal") } else { RailIcon(symbol: "line.3.horizontal", size: 50) }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Menu")
    }
}

struct HomeMenuItems: View {
    @Environment(AppModel.self) private var model
    @Environment(\.spaceEditing) private var spaceEditing

    var body: some View {
        if !model.isIncognito, let space = model.currentSpace {
            Section {
                Button("New Space…", systemImage: "plus.rectangle.on.rectangle") {
                    spaceEditing.request = .create(profileID: space.profileID)
                }
                Button("Edit Space…", systemImage: "paintpalette") { spaceEditing.request = .edit(space) }
            }
        }
        Button("Library", systemImage: "archivebox") { model.sheet = .library }
        Button(model.isIncognito ? "Leave Incognito" : "Incognito",
               systemImage: "eyeglasses") { model.setIncognito(!model.isIncognito) }
        Button("Settings", systemImage: "gearshape") { model.sheet = .settings }
    }
}

/// Private tabs as cards, as many columns as fit (three on the cover screen). Holding a card opens its menu.
private struct TodayGrid: View {
    let tabs: [SidebarItem]
    let tint: Color
    let zoom: Namespace.ID?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var minCardWidth: CGFloat = 100

    var body: some View {
        // At accessibility text sizes the cards need the full width to show the title.
        let columns = typeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: minCardWidth), spacing: 10)]
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(tabs) { tab in
                TabCard(tab: tab, tint: tint)
                    .matchedTransitionSourceIfPresent(id: tab.id, in: zoom)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: tabs.map(\.id))
    }
}

struct TabCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    @AppStorage("delight.celebratedFirstPin") private var celebratedFirstPin = false
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 124
    let tab: SidebarItem
    let tint: Color
    var body: some View {
        Button { model.activate(tab) } label: {
            Group {
                if let snapshot = model.snapshots[tab.id] { preview(snapshot) } else { monogramLayout }
            }
            // Grows with Dynamic Type instead of clipping the title.
            .frame(minHeight: height, idealHeight: height)
            .background(.regularMaterial, in: .rect(cornerRadius: Theme.Radius.card))
            .overlay {
                // A hairline edge keeps dark cards from melting into a dark backdrop.
                if scheme == .dark {
                    RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityAction(named: "Close") { model.close(tab) }
        .accessibilityAction(named: "Pin") { pin() }
        .contextMenu {
            Button("Pin", systemImage: "pin") { pin() }
            Button("Archive Tab", systemImage: "archivebox", role: .destructive) { model.close(tab) }
        }
        // Outside the card's label, so it's its own 44pt target and VoiceOver element.
        .overlay(alignment: .topTrailing) { closeButton }
    }

    private var title: String { tab.title ?? tab.url?.host() ?? "New Tab" }
    /// "theverge.com", not "www.theverge.com": the narrower card has no room for the prefix.
    private var displayHost: String {
        let host = tab.url?.host() ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var closeButton: some View {
        Button { model.close(tab) } label: {
            Image(systemName: "xmark").font(.caption2.weight(.bold))
                .frame(width: 18, height: 18)
                .background {
                    if model.snapshots[tab.id] != nil { Circle().fill(.ultraThinMaterial) }
                }
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close \(title)")
        .foregroundStyle(.secondary)
    }

    private var monogramLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Monogram(url: tab.url, tint: tint, size: 26)
                Spacer()
            }
            Spacer(minLength: 0)
            Text(title).font(.footnote.weight(.semibold)).lineLimit(2)
            Text(displayHost).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12)
    }

    /// Concentric with the card around the 7pt inset.
    private var innerRadius: CGFloat { Theme.Radius.card - 7 }

    /// Last rendered page, top-aligned, with the monogram and title as a footer.
    private func preview(_ snapshot: UIImage) -> some View {
        VStack(spacing: 0) {
            Color.clear
                .overlay(alignment: .top) { Image(uiImage: snapshot).resizable().scaledToFill() }
                .clipShape(.rect(cornerRadius: innerRadius))
                .overlay { RoundedRectangle(cornerRadius: innerRadius).strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
            HStack(spacing: 7) {
                Monogram(url: tab.url, tint: tint, size: 20)
                Text(title).font(.caption.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.top, 7).padding(.horizontal, 2)
        }
        .padding(7)
    }

    /// Pins the tab; the very first pin ever gets confetti once the menu has closed.
    private func pin() {
        model.togglePin(tab)
        guard !celebratedFirstPin, tab.spaceID != nil else { return }
        celebratedFirstPin = true
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            Celebration.shared.confetti()
        }
    }
}

private struct FavoriteTile: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sidebar) private var sidebar
    let tab: SidebarItem
    let tint: Color
    @Environment(\.isSidebar) private var isSidebar
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            model.activate(tab)
            sidebar?.didPick()
        } label: {
            Monogram(url: tab.url, tint: tint, size: isSidebar ? 24 : 28)
                .frame(maxWidth: .infinity, minHeight: isSidebar ? 46 : 58)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: Theme.Radius.tile))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(tab.title ?? tab.url?.host() ?? "Favorite")
        .sparkle(trigger: taps)
        .contextMenu {
            Button("Open", systemImage: "arrow.up.right.square") { model.activate(tab); sidebar?.didPick() }
            if let url = tab.url { ShareLink("Share", item: url) }
        }
    }
}

private struct PinnedRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sidebar) private var sidebar
    let item: SidebarItem
    let tint: Color
    let depth: Int

    var body: some View {
        switch item.kind {
        case .folder:
            Button { withAnimation(.snappy) { model.toggleExpanded(item) } } label: {
                row {
                    Image(systemName: item.isExpanded ? "folder.fill" : "folder").frame(width: 24)
                    Text(item.title ?? "Folder")
                    Spacer()
                    Image(systemName: "chevron.right").rotationEffect(.degrees(item.isExpanded ? 90 : 0)).font(.caption)
                }
            }
            .buttonStyle(.plain)
            .accessibilityValue(item.isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows or hides the folder's tabs")
            if item.isExpanded {
                ForEach(model.sidebar.children(of: item.id)) { PinnedRow(item: $0, tint: tint, depth: depth + 1) }
            }
        case .tab:
            let active = model.activeTabID == item.id
            let wandered = model.hasWandered(item)
            Button { model.activate(item); sidebar?.didPick() } label: {
                row {
                    Monogram(url: item.url, tint: tint, size: 24)
                    Text(item.title ?? item.url?.host() ?? "New Tab").lineLimit(1)
                        .fontWeight(active ? .semibold : .regular)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .overlay(alignment: .trailing) {
                if wandered {
                    Button("Back to pinned page", systemImage: "arrow.uturn.backward") {
                        model.activate(item)
                        model.returnToPinnedPage(item)
                        sidebar?.didPick()
                    }
                    .labelStyle(.iconOnly)
                    .font(.caption.weight(.semibold))
                    .frame(width: 44)
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .selectedRowBackground(active)
            .animation(.snappy, value: active)
            .animation(.snappy, value: wandered)
            .contextMenu {
                if wandered {
                    Button("Back to Pinned Page", systemImage: "arrow.uturn.backward") { model.returnToPinnedPage(item) }
                }
                Button("Unpin", systemImage: "pin.slash") { model.togglePin(item) }
            }
        case .container:
            EmptyView()
        }
    }

    private func row(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 10) { content() }
            .font(.callout)
            .padding(.vertical, 7).padding(.horizontal, 10)
            .padding(.leading, CGFloat(depth) * 18)
            .contentShape(.rect)
    }
}

/// The active-row fill, stronger and outlined under Increase Contrast so the selection stays visible.
private struct SelectedRowBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    let active: Bool

    func body(content: Content) -> some View {
        let increased = contrast == .increased
        let fill = scheme == .dark ? (increased ? 0.35 : 0.14) : (increased ? 0.9 : 0.55)
        content
            .background(.white.opacity(active ? fill : 0), in: .rect(cornerRadius: Theme.Radius.row))
            .overlay {
                if active, increased {
                    RoundedRectangle(cornerRadius: Theme.Radius.row).strokeBorder(.primary.opacity(0.4), lineWidth: 1)
                }
            }
    }
}

extension View {
    fileprivate func selectedRowBackground(_ active: Bool) -> some View { modifier(SelectedRowBackground(active: active)) }

    @ViewBuilder
    func matchedTransitionSourceIfPresent(id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace { matchedTransitionSource(id: id, in: namespace) } else { self }
    }
}
