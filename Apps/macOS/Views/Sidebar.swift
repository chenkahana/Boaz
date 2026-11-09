import AppKit
import BoazKit
import SwiftUI
import WebKit

/// Drag payload for sidebar items; anything else dropped (a link) becomes a new tab.
enum SidebarDrag {
    static let prefix = "boaz-item:"
    static func payload(_ item: SidebarItem) -> String { prefix + item.id }
    static func itemID(_ payload: String) -> String? {
        payload.hasPrefix(prefix) ? String(payload.dropFirst(prefix.count)) : nil
    }
}

struct SidebarView: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Preferences.tintWithSiteColorsKey) private var tintWithSiteColors = true
    @State private var swipe: CGFloat = 0

    var body: some View {
        let style = SpaceStyle(browser.currentSpace, scheme: browser.isIncognito ? .dark : scheme)
        let site = browser.activeSiteColor(enabled: tintWithSiteColors)
        VStack(alignment: .leading, spacing: 8) {
            SidebarTopBar()
            AddressPill()
            if !browser.isIncognito { FavoritesGrid(tint: style.tint) }
            ZStack(alignment: .top) {
                if browser.isIncognito {
                    IncognitoColumn()
                } else if let space = browser.currentSpace {
                    SpaceColumn(space: space, tint: style.tint)
                        .id(space.id)
                        .transition(reduceMotion ? .opacity : .push(from: browser.spaceEdge))
                }
            }
            .offset(x: swipe)
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
            SidebarBottomBar()
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        // An Arc theme pinned to light or dark keeps the sidebar in that appearance, as Arc does.
        .environment(\.colorScheme, browser.isIncognito ? scheme : SpaceStyle.colorScheme(of: browser.currentSpace) ?? scheme)
        .animation(SiteColor.fade(reduceMotion: reduceMotion)) {
            $0.foregroundStyle(browser.isIncognito ? .white : site?.foreground ?? style.foreground)
        }
        .background {
            HorizontalSwipeReader { dx in
                swipe = max(-90, min(90, dx * 0.4))
            } onEnded: { dx in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { swipe = 0 }
                if dx < -70 { browser.shiftSpace(by: 1) } else if dx > 70 { browser.shiftSpace(by: -1) }
            }
        }
    }
}

// MARK: Top

private struct SidebarTopBar: View {
    @Environment(BrowserState.self) private var browser

    var body: some View {
        let page = browser.activePage
        let keys = browser.model.keyBindings
        HStack(spacing: 2) {
            Spacer().frame(width: 70) // traffic lights
            HoverIconButton(symbol: "sidebar.left", help: "Toggle Sidebar", hint: keys.hint("Toggle Sidebar", .toggleSidebar)) {
                browser.toggleSidebar()
            }
            Spacer()
            HistoryButton(symbol: "arrow.left", help: "Back", hint: keys.hint("Back", .goBack),
                          items: (page?.backForwardList.backList ?? []).reversed(), action: browser.goBack)
            HistoryButton(symbol: "arrow.right", help: "Forward", hint: keys.hint("Forward", .goForward),
                          items: page?.backForwardList.forwardList ?? [], action: browser.goForward)
            HoverIconButton(symbol: page?.isLoading == true ? "xmark" : "arrow.clockwise",
                            help: page?.isLoading == true ? "Stop" : "Reload", hint: keys.hint("Reload", .reload)) {
                if page?.isLoading == true { page?.stopLoading() } else { browser.reload() }
            }
        }
        .frame(height: 40)
        .background(Color.clear.contentShape(Rectangle()).gesture(WindowDragGesture()))
    }
}

/// Back or forward: click to step once, hold for the page's history (as Safari does). Disabled with no history.
private struct HistoryButton: View {
    @Environment(BrowserState.self) private var browser
    let symbol: String
    let help: String
    let hint: String
    let items: [WebPage.BackForwardList.Item]
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(items) { item in
                Button(item.title.flatMap { $0.isEmpty ? nil : $0 } ?? item.url.host() ?? item.url.absoluteString) {
                    _ = browser.activePage?.load(item)
                }
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(.primary.opacity(hovering && !items.isEmpty ? 0.12 : 0),
                            in: .rect(cornerRadius: MacRadius.icon, style: .continuous))
                .contentShape(Rectangle())
        } primaryAction: {
            action()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(items.isEmpty)
        .opacity(items.isEmpty ? 0.4 : 1)
        .help(hint)
        .accessibilityLabel(help)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Arc's URL field in the sidebar: shows the host, opens the command bar on the current tab (⌘L).
private struct AddressPill: View {
    @Environment(BrowserState.self) private var browser
    @State private var hovering = false

    var body: some View {
        let url = browser.activePage?.url ?? browser.activeTab?.url
        Button { browser.commandMode = browser.activeTab == nil ? .newTab : .currentTab } label: {
            HStack(spacing: 6) {
                if url?.scheme == "https" { Image(systemName: "lock.fill").font(.caption2).opacity(0.6) }
                Text(url?.host()?.replacingOccurrences(of: "www.", with: "") ?? "Search or enter address")
                    .font(.callout)
                    .opacity(url == nil ? 0.6 : 1)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if hovering, url != nil {
                    Image(systemName: "link").font(.caption).opacity(0.6)
                        .onTapGesture { browser.copyActiveURL() }
                        .help(browser.model.keyBindings.hint("Copy URL", .copyURL))
                }
            }
            .padding(.horizontal, 10).frame(height: 32)
            .background(.white.opacity(hovering ? 0.32 : 0.2), in: .rect(cornerRadius: MacRadius.row, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

// MARK: Favorites

private struct FavoritesGrid: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    let tint: Color
    @State private var targeted = false

    var body: some View {
        let favorites = model.favorites(profileID: browser.currentSpace?.profileID)
        let container = browser.currentSpace.flatMap { model.sidebar.favoritesContainer(profileID: $0.profileID) }
        Group {
            if favorites.isEmpty {
                RoundedRectangle(cornerRadius: MacRadius.tile, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .opacity(targeted ? 0.6 : 0)
                    .frame(height: targeted ? 44 : 6)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: min(4, max(favorites.count, 3))),
                          spacing: 6) {
                    ForEach(favorites) { FavoriteTile(tab: $0, tint: tint) }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: favorites.map(\.id))
        .dropDestination(for: String.self) { payloads, _ in
            guard let container else { return false }
            return dropItems(payloads, into: container.id, before: nil, model: model, browser: browser)
        } isTargeted: { targeted = $0 }
    }
}

private struct FavoriteTile: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let tab: SidebarItem
    let tint: Color
    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        let active = browser.activeTabID == tab.id
        Button { browser.activate(tab) } label: {
            SiteMonogram(url: tab.url, tint: tint, size: 24)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(.white.opacity(active ? 0.75 : hovering ? 0.4 : 0.3),
                            in: .rect(cornerRadius: MacRadius.tile, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: MacRadius.tile, style: .continuous)
                        .strokeBorder(targeted ? tint : .white.opacity(active ? 0.9 : 0), lineWidth: targeted ? 2 : 1)
                }
                .shadow(color: active ? tint.opacity(0.45) : .clear, radius: 8)
                .scaleEffect(hovering && !reduceMotion ? 1.04 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title ?? tab.url?.host() ?? "Favorite")
        .accessibilityAddTraits(active ? .isSelected : [])
            .onHover { hovering = $0 }
            .help(tab.title ?? tab.url?.absoluteString ?? "")
            .draggable(SidebarDrag.payload(tab)) { SiteMonogram(url: tab.url, tint: tint, size: 28) }
            .dropDestination(for: String.self) { payloads, _ in
                dropItems(payloads, into: tab.parentID ?? "", before: tab.id, model: model, browser: browser)
            } isTargeted: { targeted = $0 }
            .contextMenu { TabMenu(tab: tab) }
    }
}

// MARK: Space column

private struct SpaceColumn: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    let space: Space
    let tint: Color
    @State private var pinnedTargeted = false
    @State private var todayTargeted = false

    var body: some View {
        let pinned = model.pinnedItems(in: space)
        let today = model.todayTabs(in: space)
        let pinnedBox = model.sidebar.container(.pinned, in: space.id)
        let todayBox = model.sidebar.container(.unpinned, in: space.id)
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                SpaceHeader(space: space)
                    .dropDestination(for: String.self) { payloads, _ in
                        guard let pinnedBox else { return false }
                        return dropItems(payloads, into: pinnedBox.id, before: pinned.first?.id, model: model, browser: browser)
                    } isTargeted: { pinnedTargeted = $0 }
                    .overlay(alignment: .bottom) { if pinnedTargeted { InsertionLine(tint: tint) } }
                ForEach(pinned) { ItemRow(item: $0, depth: 0, tint: tint) }

                TodayDivider(space: space, hasTabs: !today.isEmpty)
                    .dropDestination(for: String.self) { payloads, _ in
                        guard let todayBox else { return false }
                        return dropItems(payloads, into: todayBox.id, before: today.first?.id, model: model, browser: browser)
                    } isTargeted: { todayTargeted = $0 }
                    .overlay(alignment: .bottom) { if todayTargeted { InsertionLine(tint: tint) } }
                NewTabRow()
                ForEach(today) { ItemRow(item: $0, depth: 0, tint: tint) }
                Color.clear
                    .frame(height: 80)
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { payloads, _ in
                        guard let todayBox else { return false }
                        return dropItems(payloads, into: todayBox.id, before: nil, model: model, browser: browser)
                    }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: pinned.map(\.id) + today.map(\.id))
        }
        .scrollIndicators(.never)
    }
}

private struct SpaceHeader: View {
    @Environment(BrowserState.self) private var browser
    let space: Space
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            SpaceIcon(space: space, size: 15)
            Text(space.title).font(.system(.headline, design: .rounded)).lineLimit(1)
            Spacer()
            Menu {
                SpaceMenu(space: space)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).frame(width: 22, height: 22)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 8).frame(height: 32)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu { SpaceMenu(space: space) }
    }
}

struct SpaceMenu: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    let space: Space

    var body: some View {
        Button("Edit Space…") { browser.spaceEditor = .init(spaceID: space.id) }
        Button("Rename Space…") { browser.rename = .init(target: .space(space), text: space.title) }
        Button("Custom Colors…") { browser.themeEditor = .init(id: space.id) }
        Button("New Folder") { withAnimation { model.newFolder(in: space) } }
        if model.sidebar.spaces.count > 1, let index = model.sidebar.spaces.firstIndex(where: { $0.id == space.id }) {
            Divider()
            Button("Move Up") { withAnimation { try? model.store?.moveSpace(space.id, to: index - 1) } }.disabled(index == 0)
            Button("Move Down") { withAnimation { try? model.store?.moveSpace(space.id, to: index + 1) } }
                .disabled(index == model.sidebar.spaces.count - 1)
        }
        Divider()
        Button("Archive Today's Tabs") { withAnimation { model.clearToday(in: space) } }
        Button("New Space…") { browser.newSpace() }
    }
}

private struct TodayDivider: View {
    @Environment(MacModel.self) private var model
    let space: Space
    let hasTabs: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(.primary.opacity(0.15)).frame(height: 1)
            if hasTabs && hovering {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { model.clearToday(in: space) }
                } label: {
                    Label("Clear", systemImage: "arrow.down").font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .opacity(0.7)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.15)) { hovering = inside } }
    }
}

private struct NewTabRow: View {
    @Environment(BrowserState.self) private var browser
    @State private var hovering = false

    var body: some View {
        Button { browser.commandMode = .newTab } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 18)
                Text("New Tab").font(.body)
                Spacer()
            }
            .opacity(0.75)
            .padding(.horizontal, 8).frame(height: 32)
            .background(.white.opacity(hovering ? 0.25 : 0), in: .rect(cornerRadius: MacRadius.row, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(browser.model.keyBindings.hint("New Tab", .newTab))
        .onHover { hovering = $0 }
    }
}

private struct InsertionLine: View {
    let tint: Color
    var body: some View {
        Capsule().fill(tint).frame(height: 2).shadow(color: tint, radius: 3).padding(.horizontal, 6)
    }
}

// MARK: Rows

/// A pinned or Today row; folders expand in place. Drop on a tab inserts above it, on a folder moves inside.
struct ItemRow: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    let item: SidebarItem
    let depth: Int
    let tint: Color
    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            row
            if item.kind == .folder && item.isExpanded {
                ForEach(model.sidebar.children(of: item.id)) { ItemRow(item: $0, depth: depth + 1, tint: tint) }
            }
        }
    }

    private var row: some View {
        let active = item.kind == .tab && (browser.activeTabID == item.id || browser.split?.contains(item.id) == true)
        let dark = scheme == .dark || browser.isIncognito
        let highContrast = contrast == .increased
        let activeFill = highContrast ? (dark ? 0.35 : 0.9) : (dark ? 0.18 : 0.78)
        return HStack(spacing: 8) {
            Button(action: open) {
                HStack(spacing: 8) {
                    leadingIcon
                    Text(title).font(.body.weight(active ? .medium : .regular)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 8 + CGFloat(depth) * 14)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(item.kind == .folder ? (item.isExpanded ? "Expanded" : "Collapsed") : "")
            .accessibilityAddTraits(active ? .isSelected : [])
            if item.kind == .tab, browser.hasWandered(item) {
                HoverIconButton(symbol: "arrow.uturn.backward", help: "Back to Pinned Page", size: 20) {
                    browser.returnToPinnedPage(item)
                }
                .opacity(hovering || active ? 0.9 : 0.45)
                .transition(.scale.combined(with: .opacity))
            }
            if hovering, item.kind == .tab {
                let pinned = model.isPinned(item)
                HoverIconButton(symbol: pinned ? "minus" : "xmark", help: pinned ? "Unload" : "Archive",
                                hint: pinned ? "Unload" : model.keyBindings.hint("Archive", .closeTab), size: 20) {
                    browser.close(item)
                }
            }
        }
        .padding(.trailing, 4)
        .frame(height: 32)
        .background {
            RoundedRectangle(cornerRadius: MacRadius.row, style: .continuous)
                .fill(.white.opacity(active ? activeFill : hovering ? (dark ? 0.08 : 0.3) : 0))
                .shadow(color: .black.opacity(active && !dark ? 0.08 : 0), radius: 2, y: 1)
                .overlay {
                    if active && highContrast {
                        RoundedRectangle(cornerRadius: MacRadius.row, style: .continuous)
                            .strokeBorder(.primary.opacity(0.4), lineWidth: 1)
                    }
                }
        }
        .overlay(alignment: item.kind == .folder ? .center : .top) {
            if targeted {
                if item.kind == .folder {
                    RoundedRectangle(cornerRadius: MacRadius.row, style: .continuous).strokeBorder(tint, lineWidth: 2)
                } else {
                    InsertionLine(tint: tint).offset(y: -1)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.1)) { hovering = inside } }
        .draggable(SidebarDrag.payload(item)) {
            Label(title, systemImage: item.kind == .folder ? "folder" : "globe")
                .padding(6).background(.regularMaterial, in: .rect(cornerRadius: MacRadius.icon))
        }
        .dropDestination(for: String.self) { payloads, _ in
            if item.kind == .folder {
                if !item.isExpanded { model.toggleExpanded(item) }
                return dropItems(payloads, into: item.id, before: nil, model: model, browser: browser)
            }
            return dropItems(payloads, into: item.parentID ?? "", before: item.id, model: model, browser: browser)
        } isTargeted: { targeted = $0 }
        .contextMenu {
            if item.kind == .folder {
                Button("Rename Folder…") { browser.rename = .init(target: .item(item), text: item.title ?? "") }
                Button(item.isExpanded ? "Collapse" : "Expand") { model.toggleExpanded(item) }
            } else {
                TabMenu(tab: item)
            }
        }
    }

    private func open() {
        if item.kind == .folder {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { model.toggleExpanded(item) }
        } else if NSEvent.modifierFlags.contains(.shift) {
            browser.openInSplit(item)
        } else {
            browser.activate(item)
        }
    }

    @ViewBuilder private var leadingIcon: some View {
        if item.kind == .folder {
            // Filled while open, as on iOS.
            Image(systemName: item.isExpanded ? "folder.fill" : "folder")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 18)
                .overlay(alignment: .leading) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(item.isExpanded ? 90 : 0))
                        .offset(x: -12)
                        .opacity(hovering ? 0.6 : 0)
                }
        } else {
            SiteMonogram(url: item.url, tint: tint, size: 18)
        }
    }

    private var title: String {
        if item.kind == .folder { return item.title ?? "Folder" }
        let live = browser.isPrivate(item) ? nil : item.title
        return live ?? item.url?.host() ?? "New Tab"
    }
}

struct TabMenu: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    let tab: SidebarItem

    var body: some View {
        if browser.hasWandered(tab) {
            Button("Back to Pinned Page") { browser.returnToPinnedPage(tab) }
            Divider()
        }
        Button("Open in Split View") { browser.openInSplit(tab) }
        if let url = tab.url {
            Button("Duplicate") { browser.openTab(url, title: tab.title) }
            if !browser.isPrivate(tab) { Button("Open in New Window") { model.openInNewWindow(tab) } }
        }
        if !browser.isPrivate(tab) {
            Button(model.isPinned(tab) && !model.isFavorite(tab) ? "Unpin Tab" : "Pin Tab") {
                withAnimation { browser.togglePin(tab) }
            }
            if !model.isFavorite(tab) { Button("Add to Favorites") { withAnimation { model.addToFavorites(tab) } } }
            Button("Rename…") { browser.rename = .init(target: .item(tab), text: tab.title ?? "") }
            let otherSpaces = model.sidebar.spaces.filter { $0.id != tab.spaceID }
            if !model.isFavorite(tab), !otherSpaces.isEmpty {
                Menu("Move to Space") {
                    ForEach(otherSpaces) { space in
                        Button(space.title) { withAnimation { model.move(tab, to: space) } }
                    }
                }
            }
        }
        Button("Copy URL") {
            guard let url = tab.url else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
        }
        Divider()
        Button(model.isPinned(tab) ? "Unload Tab" : "Archive Tab") { browser.close(tab) }
    }
}

private struct IncognitoColumn: View {
    @Environment(BrowserState.self) private var browser

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Image(systemName: "eyeglasses")
                    Text("Incognito").font(.system(.headline, design: .rounded))
                }
                .padding(.horizontal, 8).frame(height: 32)
                NewTabRow()
                ForEach(browser.incognitoTabs) { ItemRow(item: $0, depth: 0, tint: Theme.violet) }
            }
        }
        .scrollIndicators(.never)
    }
}

// MARK: Bottom bar

private struct SidebarBottomBar: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            HoverIconButton(symbol: "archivebox", help: "Archive", hint: model.keyBindings.hint("Archive", .showArchive)) {
                openWindow(id: "archive")
            }
            Spacer(minLength: 4)
            if !browser.isIncognito {
                HStack(spacing: 2) {
                    ForEach(model.sidebar.spaces) { space in SpaceDot(space: space) }
                }
            }
            Spacer(minLength: 4)
            Menu {
                Button("New Space") { browser.newSpace() }
                if let space = browser.currentSpace { Button("New Folder") { model.newFolder(in: space) } }
                Divider()
                Button("New Incognito Window") { openWindow(id: "incognito") }
                Button("Import from Arc…") { browser.showImport = true }
            } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .frame(height: 30)
    }
}

private struct SpaceDot: View {
    @Environment(BrowserState.self) private var browser
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let space: Space
    @State private var hovering = false

    var body: some View {
        let selected = browser.spaceID == space.id
        Button { browser.switchSpace(to: space.id) } label: {
            Group {
                if space.icon != nil {
                    SpaceIcon(space: space, size: 13).opacity(selected ? 1 : 0.55)
                } else {
                    Circle().frame(width: 6, height: 6).opacity(selected ? 0.9 : 0.35)
                }
            }
            .frame(width: 24, height: 24)
            .background(.white.opacity(selected ? 0.45 : hovering ? 0.2 : 0), in: .circle)
            .scaleEffect(hovering && !reduceMotion ? 1.12 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.55), value: hovering)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selected)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(space.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .onHover { hovering = $0 }
        .help(space.title)
        .contextMenu { SpaceMenu(space: space) }
    }
}

// MARK: Drop handling

/// Moves dragged sidebar items, or opens dropped links as tabs at the drop point.
@discardableResult
func dropItems(_ payloads: [String], into parentID: String, before beforeID: String?,
               model: MacModel, browser: BrowserState) -> Bool {
    guard !parentID.isEmpty, !browser.isIncognito else { return false }
    var handled = false
    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
        for payload in payloads {
            if let id = SidebarDrag.itemID(payload) {
                model.move(id, into: parentID, before: beforeID)
                handled = true
            } else if let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
                      url.scheme?.hasPrefix("http") == true,
                      let tab = model.newTab(url, in: browser.spaceID) {
                model.move(tab.id, into: parentID, before: beforeID)
                handled = true
            }
        }
    }
    return handled
}

// MARK: Two-finger swipe

/// Reports horizontal two-finger trackpad swipes over this view (in finger direction: negative = left).
/// Vertical scrolling passes through untouched.
struct HorizontalSwipeReader: NSViewRepresentable {
    var onChanged: (CGFloat) -> Void
    var onEnded: (CGFloat) -> Void

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ view: SwipeView, context: Context) {
        view.onChanged = onChanged
        view.onEnded = onEnded
    }

    final class SwipeView: NSView {
        var onChanged: ((CGFloat) -> Void)?
        var onEnded: ((CGFloat) -> Void)?
        private var monitor: Any?
        private var tracking = false
        private var accumulated: CGFloat = 0

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window === window else { return event }
            if !event.momentumPhase.isEmpty { return tracking ? nil : event }
            let inside = bounds.contains(convert(event.locationInWindow, from: nil))
            let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            switch event.phase {
            case .began:
                tracking = false
                accumulated = 0
                return event
            case .changed:
                if !tracking {
                    guard inside, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5,
                          abs(event.scrollingDeltaX) > 1 else { return event }
                    tracking = true
                }
                accumulated += dx
                onChanged?(accumulated)
                return nil
            case .ended, .cancelled:
                guard tracking else { return event }
                tracking = false
                onEnded?(accumulated)
                accumulated = 0
                return nil
            default:
                return tracking ? nil : event
            }
        }
    }
}
