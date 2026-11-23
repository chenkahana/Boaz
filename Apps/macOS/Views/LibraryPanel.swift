import AppKit
import BoazKit
import SwiftUI
import UniformTypeIdentifiers

/// The Library popover's left-hand panes. Arc also has Easels and Boosts; Boaz doesn't have either feature yet.
enum LibraryTab: String, CaseIterable, Identifiable {
    case media, downloads, spaces, archive
    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Media"
        case .downloads: "Downloads"
        case .spaces: "Spaces"
        case .archive: "Archived Tabs"
        }
    }

    var symbol: String {
        switch self {
        case .media: "photo.on.rectangle"
        case .downloads: "arrow.down.circle"
        case .spaces: "square.grid.2x2"
        case .archive: "archivebox"
        }
    }
}

/// Arc-style Library popover opened from the sidebar's bottom-left button (`sidebar.libraryButton`) or the
/// Downloads… menu item: a left icon column and a right pane, tinted with the current space's colour. Always
/// opens on Downloads.
struct LibraryPanel: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    @Environment(\.colorScheme) private var scheme
    @State private var tab: LibraryTab = .downloads
    @State private var downloads = DownloadsLibraryModel()

    static let columnWidth: CGFloat = 72
    private static let paneWidth: CGFloat = 290

    var body: some View {
        let style = SpaceStyle(browser.currentSpace, scheme: scheme)
        HStack(spacing: 0) {
            LibraryTabColumn(tab: $tab, style: style)
            Divider().overlay(style.secondary.opacity(0.2))
            Group {
                switch tab {
                case .media: LibraryMediaPane(downloads: downloads, style: style)
                case .downloads: LibraryDownloadsPane(downloads: downloads, style: style)
                case .spaces: LibrarySpacesPane(style: style)
                case .archive: LibraryArchivePane(style: style)
                }
            }
            .frame(width: Self.paneWidth)
        }
        .frame(width: Self.paneWidth + Self.columnWidth, height: 630)
        .background(style.background)
        .environment(\.colorScheme, SpaceStyle.colorScheme(of: browser.currentSpace) ?? scheme)
        .onExitCommand { browser.libraryPanelPresented = false }
        // ⌘↑ and ⌘↓ step through the tab column, whatever the pane's own list has focus.
        .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { press in
            guard press.modifiers.contains(.command), let index = LibraryTab.allCases.firstIndex(of: tab) else { return .ignored }
            let next = index + (press.key == .upArrow ? -1 : 1)
            guard LibraryTab.allCases.indices.contains(next) else { return .handled }
            tab = LibraryTab.allCases[next]
            return .handled
        }
        .task { downloads.start() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.libraryPanel")
    }
}

private struct LibraryTabColumn: View {
    @Binding var tab: LibraryTab
    let style: SpaceStyle

    var body: some View {
        VStack(spacing: 14) {
            ForEach(Array(LibraryTab.allCases.enumerated()), id: \.element) { index, item in
                Button { tab = item } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol).font(.system(size: 16, weight: .medium))
                        // 11 pt, the smallest a Mac label reads at: a long title wraps instead of shrinking.
                        Text(item.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                    }
                }
                .buttonStyle(LibraryTabButtonStyle(selected: tab == item, style: style))
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                .help("\(item.title) (⌘\(index + 1))")
                .accessibilityIdentifier("control.library.tab.\(item.rawValue)")
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 20)
        .frame(width: LibraryPanel.columnWidth)
    }
}

private struct LibraryTabButtonStyle: ButtonStyle {
    let selected: Bool
    let style: SpaceStyle

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? style.tint : style.secondary)
            .frame(width: 64, height: 54)
            .background(selected ? style.tint.opacity(0.18) : configuration.isPressed ? style.secondary.opacity(0.1) : .clear,
                        in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            // The whole tile takes the click, not just the icon's and the title's pixels.
            .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
    }
}

/// The search field + Filter menu shared by the Downloads and Media panes.
private struct LibrarySearchBar: View {
    @Binding var query: String
    var placeholder = "Search Downloads…"
    let style: SpaceStyle
    var filter: Binding<DownloadsFilter>?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(style.secondary)
            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(style.foreground)
                .accessibilityIdentifier("control.library.search")
            if let filter {
                Menu {
                    ForEach(DownloadsFilter.allCases) { option in
                        Button {
                            filter.wrappedValue = option
                        } label: {
                            if filter.wrappedValue == option { Label(option.title, systemImage: "checkmark") }
                            else { Text(option.title) }
                        }
                    }
                } label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(style.secondary)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityIdentifier("control.library.filter")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(style.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .padding(.horizontal, 12).padding(.top, 12)
    }
}

// MARK: Downloads pane

private struct LibraryDownloadsPane: View {
    @Environment(BrowserState.self) private var browser
    let downloads: DownloadsLibraryModel
    let style: SpaceStyle
    @State private var query = ""
    @State private var filter: DownloadsFilter = .all
    @State private var selection: Set<URL> = []
    #if BOAZ_CHROMIUM
    @State private var chromiumDownloads: ChromiumDownloads?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            LibrarySearchBar(query: $query, style: style, filter: $filter)
            #if BOAZ_CHROMIUM
            if let chromiumDownloads, !chromiumDownloads.items.isEmpty {
                ActiveChromiumDownloadsSection(model: chromiumDownloads, style: style)
            }
            #endif
            if downloads.loaded, sections.isEmpty {
                Spacer()
                ContentUnavailableView(query.isEmpty ? "No Downloads" : "No Results", systemImage: "arrow.down.circle",
                                       description: Text(query.isEmpty ? "Files you download appear here." : "Try another search."))
                    .foregroundStyle(style.secondary)
                Spacer()
            } else {
                List(selection: $selection) {
                    ForEach(sections, id: \.title) { section in
                        Section {
                            ForEach(section.items) { item in
                                LibraryDownloadRow(item: item, style: style)
                                    .tag(item.id)
                                    .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                        } header: {
                            Text(section.title.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(style.secondary)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("Downloads")
                .contextMenu(forSelectionType: URL.self) { urls in
                    LibraryDownloadContextMenu(urls: urls, downloads: downloads)
                } primaryAction: { urls in
                    for url in urls { NSWorkspace.shared.open(url) }
                }
            }
        }
        .task {
            #if BOAZ_CHROMIUM
            if let identity = browser.chromiumProfileIdentity { chromiumDownloads = ChromiumRuntime.activeDownloads(for: identity) }
            #endif
        }
    }

    private var filteredItems: [LibraryDownloadItem] {
        downloads.items.filter { item in
            (query.isEmpty || item.name.localizedCaseInsensitiveContains(query)) && filter.matches(item.contentType)
        }
    }

    private var sections: [(title: String, items: [LibraryDownloadItem])] {
        var result: [(title: String, items: [LibraryDownloadItem])] = []
        for item in filteredItems {
            let title = relativeLibrarySection(for: item.dateAdded)
            if result.indices.last.map({ result[$0].title == title }) == true {
                result[result.count - 1].items.append(item)
            } else {
                result.append((title, [item]))
            }
        }
        return result
    }
}

private struct LibraryDownloadContextMenu: View {
    let urls: Set<URL>
    let downloads: DownloadsLibraryModel

    var body: some View {
        Button("Open") { for url in urls { NSWorkspace.shared.open(url) } }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(Array(urls)) }
        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
        }
        Divider()
        Button("Move to Trash", role: .destructive) {
            for url in urls { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
            downloads.reload()
        }
    }
}

private struct LibraryDownloadRow: View {
    let item: LibraryDownloadItem
    let style: SpaceStyle

    var body: some View {
        HStack(spacing: 10) {
            // Beside the file's name, the thumbnail is decoration.
            DownloadThumbnail(url: item.url, size: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(style.foreground)
                Text(item.subtitle).font(.system(size: 11)).lineLimit(1).foregroundStyle(style.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("control.library.download.\(item.name)")
    }
}

#if BOAZ_CHROMIUM
private struct ActiveChromiumDownloadsSection: View {
    let model: ChromiumDownloads
    let style: SpaceStyle

    private var active: [ChromiumDownload] {
        model.items.values.filter { $0.state == BOAZ_DOWNLOAD_PROGRESS || $0.state == BOAZ_DOWNLOAD_INTERRUPTED }
            .sorted { $0.id > $1.id }
    }

    var body: some View {
        if !active.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(active) { item in ActiveChromiumDownloadRow(item: item, model: model, style: style) }
            }
            .padding(.horizontal, 12).padding(.top, 10)
        }
    }
}

private struct ActiveChromiumDownloadRow: View {
    let item: ChromiumDownload
    let model: ChromiumDownloads
    let style: SpaceStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.filename).font(.system(size: 13)).lineLimit(1).foregroundStyle(style.foreground)
            if item.state == BOAZ_DOWNLOAD_PROGRESS {
                if item.total > 0 {
                    ProgressView(value: Double(max(0, item.received)), total: Double(max(item.total, item.received)))
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            HStack(spacing: 8) {
                Text(statusText).font(.system(size: 11)).foregroundStyle(style.secondary)
                Spacer(minLength: 0)
                if !item.dangerous, item.state == BOAZ_DOWNLOAD_PROGRESS, !item.paused {
                    Button("Pause") { model.action(item.id, BOAZ_DOWNLOAD_PAUSE) }
                }
                if !item.dangerous, item.canResume, item.paused || item.state == BOAZ_DOWNLOAD_INTERRUPTED {
                    Button("Resume") { model.action(item.id, BOAZ_DOWNLOAD_RESUME) }
                }
                if item.state == BOAZ_DOWNLOAD_PROGRESS || item.state == BOAZ_DOWNLOAD_INTERRUPTED {
                    Button("Cancel") { model.action(item.id, BOAZ_DOWNLOAD_CANCEL) }
                }
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11))
        }
        .padding(8)
        .background(style.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
    }

    private var statusText: String {
        switch item.state {
        case BOAZ_DOWNLOAD_INTERRUPTED: "Interrupted"
        default:
            (item.paused ? "Paused · " : "Downloading · ")
                + ByteCountFormatter.string(fromByteCount: max(0, item.received), countStyle: .file)
        }
    }
}
#endif

// MARK: Media pane

private struct LibraryMediaPane: View {
    let downloads: DownloadsLibraryModel
    let style: SpaceStyle
    @State private var query = ""

    private var items: [LibraryDownloadItem] {
        downloads.items.filter { item in
            (item.contentType?.conforms(to: .image) == true || item.contentType?.conforms(to: .movie) == true)
                && (query.isEmpty || item.name.localizedCaseInsensitiveContains(query))
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 80, maximum: 96), spacing: 8)]

    var body: some View {
        VStack(spacing: 0) {
            LibrarySearchBar(query: $query, placeholder: "Search Media…", style: style)
            if downloads.loaded, items.isEmpty {
                Spacer()
                ContentUnavailableView("No Media", systemImage: "photo.on.rectangle",
                                       description: Text("Images and videos you download appear here."))
                    .foregroundStyle(style.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(items) { item in
                            DownloadThumbnail(url: item.url, size: 86)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
                                .contextMenu {
                                    Button("Open") { NSWorkspace.shared.open(item.url) }
                                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                }
                                .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(Self.spokenName(item))
                                .accessibilityAddTraits(.isImage)
                                .accessibilityAction { NSWorkspace.shared.open(item.url) }
                                .accessibilityIdentifier("control.library.download.\(item.name)")
                        }
                    }
                    .padding(12)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Media")
                }
            }
        }
    }

    /// "screenshot, PNG image" rather than the file name VoiceOver would spell out.
    private static func spokenName(_ item: LibraryDownloadItem) -> String {
        let name = (item.name as NSString).deletingPathExtension
        return item.contentType?.localizedDescription.map { "\(name), \($0)" } ?? name
    }
}

// MARK: Spaces pane

private struct LibrarySpacesPane: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    let style: SpaceStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Spaces").font(.system(size: 13, weight: .semibold)).foregroundStyle(style.foreground)
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
            if model.sidebar.spaces.isEmpty {
                Spacer()
                ContentUnavailableView("No Spaces", systemImage: "square.grid.2x2").foregroundStyle(style.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.sidebar.spaces) { space in
                            LibrarySpaceRow(space: space, selected: browser.spaceID == space.id, style: style) {
                                browser.switchSpace(to: space.id)
                                browser.libraryPanelPresented = false
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct LibrarySpaceRow: View {
    let space: Space
    let selected: Bool
    let style: SpaceStyle
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if space.icon != nil { SpaceIcon(space: space, size: 18) } else { Circle().frame(width: 8, height: 8) }
                Text(space.title).font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(style.foreground)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(selected ? style.tint.opacity(0.18) : hovering ? style.secondary.opacity(0.1) : .clear,
                        in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityIdentifier("control.library.space.\(space.id)")
    }
}

// MARK: Archived Tabs pane

private struct LibraryArchivePane: View {
    @Environment(BrowserState.self) private var browser
    let style: SpaceStyle
    @State private var query = ""
    @State private var isEmpty = true

    var body: some View {
        VStack(spacing: 0) {
            LibrarySearchBar(query: $query, placeholder: "Search Archive…", style: style)
            ArchiveListView(query: $query, isEmpty: $isEmpty) { _ in browser.libraryPanelPresented = false }
                .scrollContentBackground(.hidden)
        }
    }
}
