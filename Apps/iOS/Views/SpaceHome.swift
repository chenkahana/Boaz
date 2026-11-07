import FolioKit
import SwiftUI

/// Home: spaces page horizontally, each on its own themed gradient, with favorites, pins and today's tabs.
struct SpaceHome: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
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
        .safeAreaInset(edge: .bottom) { HomeBar().environment(\.colorScheme, model.isIncognito ? .dark : scheme) }
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
            .animation(.easeInOut(duration: 0.35), value: model.currentSpaceID)
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
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(model.incognitoTabs) { tab in
                        TabCard(tab: tab, tint: Theme.violet)
                            .matchedTransitionSourceIfPresent(id: tab.id, in: zoom)
                    }
                }
                Button("Leave Incognito") { model.setIncognito(false) }
                    .buttonStyle(.bordered).tint(.white)
            }
            .padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 120)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

private struct SpacePage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme
    let space: Space
    let zoom: Namespace.ID?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let style = SpaceStyle(space, scheme: scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 10) {
                    Text(space.icon ?? "✦").font(.title)
                    Text(space.title).font(.system(.largeTitle, design: .rounded, weight: .bold))
                }
                .padding(.top, 8)

                let favorites = model.favorites(for: space)
                if !favorites.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                        ForEach(favorites) { FavoriteTile(tab: $0, tint: style.tint) }
                    }
                }

                let pinned = model.pinnedItems(in: space)
                if !pinned.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(pinned) { PinnedRow(item: $0, tint: style.tint, depth: 0) }
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: .rect(cornerRadius: Theme.cornerRadius))
                }

                let today = model.todayTabs(in: space)
                Text(today.isEmpty ? "No open tabs" : "Today")
                    .font(.footnote.weight(.semibold)).textCase(.uppercase)
                    .foregroundStyle(style.foreground.opacity(0.6))
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(today) { tab in
                        TabCard(tab: tab, tint: style.tint)
                            .matchedTransitionSourceIfPresent(id: tab.id, in: zoom)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: today.map(\.id))
            }
            .padding(.horizontal, 20)
            .padding(.top, 60)
            .padding(.bottom, 120)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(style.foreground)
    }
}

private struct HomeBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 10) {
            if model.spaces.count > 1, !model.isIncognito {
                HStack(spacing: 6) {
                    ForEach(model.spaces) { space in
                        Capsule()
                            .fill(.primary.opacity(space.id == model.currentSpaceID ? 0.8 : 0.25))
                            .frame(width: space.id == model.currentSpaceID ? 18 : 6, height: 6)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: model.currentSpaceID)
            }
            HStack(spacing: 10) {
                Menu {
                    Button("Library", systemImage: "archivebox") { model.sheet = .library }
                    Button(model.isIncognito ? "Leave Incognito" : "Incognito",
                           systemImage: "eyeglasses") { model.setIncognito(!model.isIncognito) }
                    Button("Settings", systemImage: "gearshape") { model.sheet = .settings }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.body.weight(.medium))
                        .frame(width: 50, height: 50)
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.plain)
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

struct TabCard: View {
    @Environment(AppModel.self) private var model
    let tab: SidebarItem
    let tint: Color
    @State private var dragY: CGFloat = 0

    var body: some View {
        Button { model.activate(tab) } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Monogram(url: tab.url, tint: tint, size: 28)
                    Spacer()
                    Button { model.close(tab) } label: {
                        Image(systemName: "xmark").font(.caption.weight(.bold)).padding(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(tab.title ?? tab.url?.host() ?? "New Tab")
                    .font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(tab.url?.host() ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(14)
            .frame(height: 150)
            .background(.regularMaterial, in: .rect(cornerRadius: 22))
        }
        .buttonStyle(PressableStyle())
        .offset(y: min(dragY, 0))
        .opacity(1 + Double(min(dragY, 0)) / 300)
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onChanged { if abs($0.translation.height) > abs($0.translation.width) { dragY = $0.translation.height } }
                .onEnded { value in
                    if value.translation.height < -90 {
                        withAnimation(.spring(response: 0.3)) { dragY = -400 }
                        model.close(tab)
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) { dragY = 0 }
                    }
                }
        )
        .contextMenu {
            Button("Pin", systemImage: "pin") { model.togglePin(tab) }
            Button("Close", systemImage: "xmark", role: .destructive) { model.close(tab) }
        }
    }
}

private struct FavoriteTile: View {
    @Environment(AppModel.self) private var model
    let tab: SidebarItem
    let tint: Color

    var body: some View {
        Button { model.activate(tab) } label: {
            Monogram(url: tab.url, tint: tint, size: 30)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(.ultraThinMaterial, in: .rect(cornerRadius: 18))
        }
        .buttonStyle(PressableStyle())
    }
}

private struct PinnedRow: View {
    @Environment(AppModel.self) private var model
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
            if item.isExpanded {
                ForEach(model.sidebar.children(of: item.id)) { PinnedRow(item: $0, tint: tint, depth: depth + 1) }
            }
        case .tab:
            Button { model.activate(item) } label: {
                row {
                    Monogram(url: item.url, tint: tint, size: 24)
                    Text(item.title ?? item.url?.host() ?? "Tab").lineLimit(1)
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button("Unpin", systemImage: "pin.slash") { model.togglePin(item) }
            }
        case .container:
            EmptyView()
        }
    }

    private func row(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 10) { content() }
            .font(.callout)
            .padding(.vertical, 9).padding(.horizontal, 10)
            .padding(.leading, CGFloat(depth) * 18)
            .contentShape(.rect)
    }
}

extension View {
    @ViewBuilder
    func matchedTransitionSourceIfPresent(id: String, in namespace: Namespace.ID?) -> some View {
        if let namespace { matchedTransitionSource(id: id, in: namespace) } else { self }
    }
}
