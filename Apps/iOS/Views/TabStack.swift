import BoazKit
import SwiftUI

/// This iPhone's two most recently used Today tabs as a fanned pair of cards, with the tab count. Tapping opens
/// the cover flow. Folded layout only: on the page's rail and on the home screen.
struct TabStack: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    /// The space whose Today this shows: each home page shows its own, even while swiping between them.
    let space: Space?
    let cardSize: CGSize
    /// Where the open page zooms back to: the front card, which is always the tab used last.
    var zoom: Namespace.ID?

    var body: some View {
        let tabs = todayTabs
        let recent = tabs.sorted { ($0.lastActiveAt ?? $0.createdAt) > ($1.lastActiveAt ?? $1.createdAt) }.prefix(2)
        Button { model.openCoverFlow() } label: {
            ZStack {
                if recent.isEmpty {
                    RoundedRectangle(cornerRadius: radius)
                        .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: cardSize.width, height: cardSize.height)
                }
                ForEach(Array(recent.enumerated()).reversed(), id: \.element.id) { index, tab in
                    card(tab)
                        .matchedTransitionSourceIfPresent(id: tab.id, in: index == 0 ? zoom : nil)
                        // The card behind peeks out up and to the left, turned a few degrees.
                        .rotationEffect(.degrees(index == 0 ? 0 : -9), anchor: .bottom)
                        .offset(x: index == 0 ? 0 : -cardSize.width * 0.14, y: index == 0 ? 0 : -cardSize.height * 0.05)
                }
            }
            .frame(width: cardSize.width * 1.3, height: cardSize.height * 1.12)
            .overlay(alignment: .topTrailing) { RailBadge(count: tabs.count) }
            .contentShape(.rect)
        }
        .buttonStyle(PressableStyle())
        .animation(.bouncy(duration: 0.35), value: recent.map(\.id))
        .accessibilityLabel("Tabs")
        .accessibilityValue("\(tabs.count) open")
        .accessibilityHint("Shows your tabs side by side")
    }

    private var todayTabs: [SidebarItem] { space.map(model.todayTabs(in:)) ?? [] }

    private var radius: CGFloat { max(cardSize.width * 0.16, 5) }

    private func card(_ tab: SidebarItem) -> some View {
        Group {
            if let snapshot = model.snapshots[tab.id] {
                Color.clear.overlay(alignment: .top) { Image(uiImage: snapshot).resizable().scaledToFill() }
            } else {
                Monogram(url: tab.url, tint: SpaceStyle(space, scheme: scheme).tint,
                         size: min(cardSize.width * 0.55, 44))
            }
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: radius))
        .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(.primary.opacity(0.15), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }
}

/// Today's tabs side by side, full screen over the page or the home screen: the centre card flat, its neighbours
/// turned away. Tap a card to open it, swipe it up to archive it.
struct CoverFlow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    var zoom: Namespace.ID?
    @State private var centred: String?
    @State private var sheet: Sheet?
    /// A Mac tab picked in the sheet, opened once the sheet has gone.
    @State private var macTab: SidebarItem?

    private enum Sheet: String, Identifiable { case macTabs, settings; var id: String { rawValue } }

    var body: some View {
        let tabs = model.currentSpace.map(model.todayTabs(in:)) ?? []
        let style = SpaceStyle(model.currentSpace, scheme: scheme)
        VStack(spacing: 0) {
            header(count: tabs.count)
            if tabs.isEmpty {
                ContentUnavailableView("No Tabs", systemImage: "square.on.square",
                                       description: Text("Tabs you open on this iPhone appear here."))
            } else {
                carousel(tabs, tint: style.tint)
            }
            bottomBar
        }
        .foregroundStyle(style.foreground)
        .background {
            // The space gradient is translucent; the page or home screen mustn't show through it.
            style.gradient.background(Color(.systemBackground)).ignoresSafeArea()
        }
        .onAppear { centred = model.activeTabID ?? tabs.last?.id }
        .sheet(item: $sheet, onDismiss: openMacTab) { sheet in
            switch sheet {
            case .macTabs: MacTabsSheet { macTab = $0 }
            case .settings: SettingsSheet()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { model.showsCoverFlow = false }
    }

    private func header(count: Int) -> some View {
        HStack {
            if model.activeTabID != nil {
                // The page's rail opens this view in place of going home, so home is one step on from here.
                Button("Home", systemImage: "square.grid.2x2") {
                    model.showsCoverFlow = false
                    model.goHome()
                }
            }
            Spacer()
            Button("Done") { model.showsCoverFlow = false }
                .fontWeight(.semibold)
        }
        .overlay {
            Text(count == 1 ? "1 Tab" : "\(count) Tabs")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
        }
        .buttonStyle(.glass)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func carousel(_ tabs: [SidebarItem], tint: Color) -> some View {
        GeometryReader { proxy in
            let cardWidth = min(proxy.size.width * 0.56, (proxy.size.height - 60) * 0.62)
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(tabs) { tab in
                        CoverCard(tab: tab, tint: tint, width: cardWidth, isCentred: tab.id == centred,
                                  open: { open(tab) },
                                  archive: { withAnimation(.snappy) { model.close(tab) } })
                            .matchedTransitionSourceIfPresent(id: tab.id, in: zoom)
                            .visualEffect { [reduceMotion] content, proxy in
                                // Card widths from the centre: negative to the left. The neighbours stay in view,
                                // so this is measured rather than taken from `scrollTransition`'s visibility phase.
                                let centre = proxy.bounds(of: .scrollView).map { $0.midX - proxy.size.width / 2 } ?? 0
                                let distance = max(-1, min(1, -centre / proxy.size.width))
                                return content
                                    .rotation3DEffect(.degrees(reduceMotion ? 0 : distance * 50),
                                                      axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                                    .scaleEffect(reduceMotion ? 1 : 1 - abs(distance) * 0.18)
                            }
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, (proxy.size.width - cardWidth) / 2, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centred, anchor: .center)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .frame(maxHeight: .infinity)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 28) {
            barButton("laptopcomputer", label: "Tabs on Your Mac") { sheet = .macTabs }
            barButton("plus", label: "New Tab") {
                model.showsCoverFlow = false
                model.beginSearch(.newTab)
            }
            barButton("gearshape", label: "Settings") { sheet = .settings }
        }
        .padding(.vertical, 12)
    }

    private func barButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { RailIcon(symbol: symbol, size: 52) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
    }

    private func open(_ tab: SidebarItem) {
        model.activate(tab)
        model.showsCoverFlow = false
    }

    private func openMacTab() {
        guard let tab = macTab, let url = tab.url else { return }
        macTab = nil
        model.showsCoverFlow = false
        model.openNewTab(url, title: tab.title)
    }
}

/// One tab in the cover flow: the page as last seen, then its icon and title.
private struct CoverCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tab: SidebarItem
    let tint: Color
    let width: CGFloat
    let isCentred: Bool
    let open: () -> Void
    let archive: () -> Void
    /// How far the card has been swiped up (negative).
    @State private var lift: CGFloat = 0

    var body: some View {
        Button(action: open) {
            VStack(spacing: 14) {
                preview
                    .frame(width: width, height: width / 0.62)
                    .background(.regularMaterial)
                    .clipShape(.rect(cornerRadius: Theme.Radius.sheet))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.sheet).strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                HStack(spacing: 8) {
                    Monogram(url: tab.url, tint: tint, size: 22)
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                .frame(maxWidth: width)
                .opacity(isCentred ? 1 : 0.5)
            }
        }
        .buttonStyle(PressableStyle())
        .offset(y: lift)
        .opacity(1 + lift / 500)
        .simultaneousGesture(swipeUp)
        .accessibilityLabel(title)
        .accessibilityHint("Opens the tab")
        .accessibilityAction(named: "Archive", archive)
    }

    private var title: String { tab.title ?? tab.url?.host() ?? "New Tab" }

    @ViewBuilder private var preview: some View {
        if let snapshot = model.snapshots[tab.id] {
            Color.clear.overlay(alignment: .top) { Image(uiImage: snapshot).resizable().scaledToFill() }
        } else {
            Monogram(url: tab.url, tint: tint, size: 64)
        }
    }

    /// Up past a short distance (or flicked up) archives the tab; anything else springs back.
    private var swipeUp: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                lift = min(value.translation.height, 0)
            }
            .onEnded { value in
                if lift < -120 || (lift < 0 && value.predictedEndTranslation.height < -400) {
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .snappy) { lift = -width * 2 } completion: {
                        archive()
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { lift = 0 }
                }
            }
    }
}

/// Today tabs open on the user's Macs, by Mac. Read-only: picking one opens its page in a new tab here.
private struct MacTabsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let pick: (SidebarItem) -> Void

    var body: some View {
        let macs = model.sidebar.devices
            .filter { $0.platform == .macOS }
            .map { (device: $0, tabs: model.sidebar.todayTabs(openedOn: $0.id).filter { $0.url != nil }) }
            .filter { !$0.tabs.isEmpty }
        NavigationStack {
            List {
                ForEach(macs, id: \.device.id) { mac in
                    Section {
                        ForEach(mac.tabs) { tab in
                            Button { pick(tab); dismiss() } label: { row(tab) }
                                .buttonStyle(.plain)
                        }
                    } header: {
                        Text(mac.device.name)
                    } footer: {
                        Text("Last used \(mac.device.lastSeenAt, format: .relative(presentation: .named))")
                    }
                }
            }
            .overlay {
                if macs.isEmpty {
                    ContentUnavailableView("No Tabs on Your Mac", systemImage: "laptopcomputer",
                                           description: Text("Today tabs open in Boaz on your Mac appear here."))
                }
            }
            .navigationTitle("Tabs on Your Mac")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } } }
        }
    }

    private func row(_ tab: SidebarItem) -> some View {
        HStack(spacing: 12) {
            Monogram(url: tab.url, tint: Theme.brand, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.title ?? tab.url?.host() ?? "").lineLimit(1)
                Text(tab.url?.host() ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect)
    }
}
