import AppKit
import BoazKit
import SwiftUI
import UniformTypeIdentifiers

/// Archive window (⌥⌘A): closed and auto-archived tabs by day; double-click or Restore reopens one.
struct ArchiveWindow: View {
    @Environment(MacModel.self) private var model
    @State private var items: [ArchiveItem] = []
    @State private var query = ""
    @State private var selection: ArchiveItem.ID?
    @State private var confirmClear = false

    var body: some View {
        let filtered = query.isEmpty ? items : items.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(query) || $0.url.absoluteString.localizedCaseInsensitiveContains(query)
        }
        let days = Dictionary(grouping: filtered) { Calendar.current.startOfDay(for: $0.archivedAt) }
            .sorted { $0.key > $1.key }
        List(selection: $selection) {
            ForEach(days, id: \.key) { day, entries in
                Section(dayTitle(day)) {
                    ForEach(entries) { item in
                        HStack(spacing: 10) {
                            SiteMonogram(url: item.url, tint: Theme.brand, size: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title ?? item.url.host() ?? item.url.absoluteString).lineLimit(1)
                                Text(item.url.host() ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(item.archivedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption).foregroundStyle(.tertiary)
                            Button("Restore") { restore(item) }.buttonStyle(.borderless)
                        }
                        .padding(.vertical, 2)
                        .tag(item.id)
                        .contextMenu {
                            Button("Restore") { restore(item) }
                            Button("Delete", role: .destructive) { try? model.store?.removeFromArchive(item.id); reload() }
                        }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: ArchiveItem.ID.self) { _ in } primaryAction: { ids in
            for id in ids { if let item = items.first(where: { $0.id == id }) { restore(item) } }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Archive is empty", systemImage: "archivebox",
                                       description: Text("Closed and auto-archived tabs appear here."))
            }
        }
        .searchable(text: $query, prompt: "Search archive")
        .toolbar {
            Button("Clear Archive", systemImage: "trash") { confirmClear = true }
                .disabled(items.isEmpty)
                .confirmationDialog("Clear the Archive?", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("Clear Archive", role: .destructive) { try? model.store?.clearArchive(); reload() }
                } message: {
                    Text("This can't be undone.")
                }
        }
        .navigationTitle("Archive")
        .task(id: model.sidebar) { reload() }
    }

    private func reload() { items = (try? model.store?.archivedItems()) ?? [] }

    private func restore(_ item: ArchiveItem) {
        guard let tab = model.restore(item) else { return }
        if let browser = model.lastActiveBrowser {
            browser.activate(tab)
            browser.window?.makeKeyAndOrderFront(nil)
        }
        reload()
    }
}

/// History window (⌘Y): visits by day, searchable; double-click or Open reopens one as a tab. The store keeps
/// no per-visit delete, so clearing is all-or-nothing.
struct HistoryWindow: View {
    @Environment(MacModel.self) private var model
    @State private var visits: [HistoryVisit] = []
    @State private var query = ""
    @State private var selection: HistoryVisit.ID?
    @State private var confirmClear = false

    var body: some View {
        let days = Dictionary(grouping: visits) { Calendar.current.startOfDay(for: $0.visitedAt) }
            .sorted { $0.key > $1.key }
        List(selection: $selection) {
            ForEach(days, id: \.key) { day, entries in
                Section(dayTitle(day)) {
                    ForEach(entries) { visit in
                        HStack(spacing: 10) {
                            SiteMonogram(url: visit.url, tint: Theme.brand, size: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(visit.title ?? visit.url.host() ?? visit.url.absoluteString).lineLimit(1)
                                Text(visit.url.host() ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(visit.visitedAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                        .tag(visit.id)
                        .contextMenu {
                            Button("Open") { model.openInMainWindow(visit.url, title: visit.title) }
                            Button("Copy URL") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(visit.url.absoluteString, forType: .string)
                            }
                        }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: HistoryVisit.ID.self) { _ in } primaryAction: { ids in
            for id in ids { if let visit = visits.first(where: { $0.id == id }) { model.openInMainWindow(visit.url, title: visit.title) } }
        }
        .overlay {
            if visits.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No History" : "No Results", systemImage: "clock",
                                       description: Text(query.isEmpty ? "Pages you visit appear here." : "Try another search."))
            }
        }
        .searchable(text: $query, prompt: "Search history")
        .toolbar {
            Button("Clear History", systemImage: "trash") { confirmClear = true }
                .disabled(visits.isEmpty && query.isEmpty)
                .confirmationDialog("Clear all history?", isPresented: $confirmClear, titleVisibility: .visible) {
                    Button("Clear History", role: .destructive) { try? model.store?.clearHistory(); visits = [] }
                } message: {
                    Text("This can't be undone.")
                }
        }
        .navigationTitle("History")
        .task(id: query) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            await reload()
        }
        .task(id: model.sidebar) { await reload() }
    }

    /// Searches in the database, off the main thread: matching scans the whole history.
    private func reload() async {
        let searched = query
        guard !Task.isCancelled, let store = model.store,
              let found = try? await store.history(matching: searched, limit: 1000), !Task.isCancelled,
              searched == query else { return }
        visits = found
    }
}

/// A calendar day's section title. Relative formatting counts from now, so this morning read as "Yesterday"
/// late at night.
private func dayTitle(_ day: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return "Today" }
    if calendar.isDateInYesterday(day) { return "Yesterday" }
    // The archive keeps entries for good, so older days name their year.
    let date = Date.FormatStyle.dateTime.weekday(.wide).month().day()
    return day.formatted(calendar.isDate(day, equalTo: .now, toGranularity: .year) ? date : date.year())
}

/// Boaz ▸ Settings: same preferences as iOS, plus keyboard shortcut overrides.
struct MacSettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            PrivacySettings().tabItem { Label("Privacy", systemImage: "hand.raised") }
            SyncSettings().tabItem { Label("Sync", systemImage: "icloud") }
            ShortcutsSettings().tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @Environment(MacModel.self) private var model
    @AppStorage(Preferences.archiveAfterKey) private var archiveAfter = ArchiveInterval.day.rawValue
    @AppStorage(Preferences.searchEngineKey) private var searchEngine = SearchEngine.duckDuckGo.rawValue
    @AppStorage(Preferences.tintWithSiteColorsKey) private var tintWithSiteColors = true

    var body: some View {
        Form {
            Section {
                DefaultBrowserRow()
                Picker("Archive Inactive Tabs After", selection: $archiveAfter) {
                    ForEach(ArchiveInterval.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("Search engine", selection: $searchEngine) {
                    ForEach(SearchEngine.allCases) { Text($0.name).tag($0.rawValue) }
                }
                Toggle("Tint chrome with site colors", isOn: $tintWithSiteColors)
            }
            AISettingsSection()
            AboutSection()
        }
        .formStyle(.grouped)
        .onChange(of: archiveAfter) { model.archiveStaleTabs() }
    }
}

private struct DefaultBrowserRow: View {
    @State private var current = DefaultBrowser.current()
    @State private var failed = false

    var body: some View {
        LabeledContent("Default browser") {
            if current.isBoaz {
                Text("Boaz").foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(current.name).foregroundStyle(.secondary)
                    Button("Make Default") {
                        Task {
                            failed = (try? await DefaultBrowser.makeBoazDefault()) == nil
                            current = DefaultBrowser.current()
                        }
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            current = DefaultBrowser.current()
        }
        if failed { Text("Your default browser didn't change.").font(.caption).foregroundStyle(.secondary) }
    }
}

private struct PrivacySettings: View {
    @AppStorage(Preferences.blockTrackersKey) private var blockTrackers = true

    var body: some View {
        Form {
            Section {
                Toggle("Block ads and trackers", isOn: $blockTrackers)
                Text("Applies to pages opened after you change it.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SyncSettings: View {
    @Environment(MacModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var syncMessage: String?

    var body: some View {
        Form {
            if let sync = model.sync {
                Section("iCloud Sync") {
                    LabeledContent {
                        if ICloudSignIn.needsSignIn(sync.status) {
                            Button("Sign In to iCloud…") { if let url = ICloudSignIn.settingsURL { openURL(url) } }
                        } else {
                            Button("Sync Now") { Task { await sync.syncNow(userInitiated: true) } }
                                .disabled(sync.status == .syncing || !sync.canSyncNow)
                        }
                    } label: {
                        SyncStatusLabel(status: sync.status)
                    }
                    if sync.offersFolder {
                        LabeledContent("Sync folder", value: sync.folderURL?.path(percentEncoded: false) ?? "None")
                        Button(sync.folderURL == nil ? "Sync Through a Folder…" : "Change Folder…") {
                            Task { syncMessage = await sync.chooseFolder() }
                        }
                        if let syncMessage { Text(syncMessage).font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(sync.offersFolder
                         ? "Until iCloud is available, you can sync through a folder your iPhone can reach too, like iCloud Drive › Boaz."
                         : "Spaces, pins, tabs and the Archive sync through your iCloud account. History and private tabs stay on this Mac.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text("Sync starts once your library has loaded.").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutsSettings: View {
    @Environment(MacModel.self) private var model
    @State private var message: String?
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section("Keyboard shortcuts") {
                LabeledContent("Overrides", value: model.keyBindings.overrides.isEmpty
                               ? "Arc defaults" : "\(model.keyBindings.overrides.count) custom")
                HStack {
                    Button("Import Arc Shortcuts…", action: importArcShortcuts)
                    Button("Reset to Defaults") { confirmReset = true }
                        .disabled(model.keyBindings.overrides.isEmpty)
                        .confirmationDialog("Reset keyboard shortcuts?", isPresented: $confirmReset, titleVisibility: .visible) {
                            Button("Reset to Defaults", role: .destructive) { model.keyBindings.resetToDefaults() }
                        } message: {
                            Text("Your custom and imported shortcuts go back to Arc's defaults.")
                        }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }

    private func importArcShortcuts() {
        let panel = NSOpenPanel()
        panel.message = "Choose Arc's StorableKeyBindings.json (in ~/Library/Application Support/Arc)"
        panel.allowedContentTypes = [.json]
        panel.directoryURL = ReadOnlyFolder.realHome.appending(path: "Library/Application Support/Arc", directoryHint: .isDirectory)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let count = try model.keyBindings.applyArcKeyBindings(fileURL: url)
            message = count == 0 ? "No custom Arc shortcuts found." : "Applied \(count) shortcut\(count == 1 ? "" : "s")."
        } catch {
            message = "Couldn't read shortcuts: \(error.localizedDescription)"
        }
    }
}

/// Per-space theme editor. Writes Arc `windowTheme` JSON, live.
struct ThemeEditor: View {
    @Environment(MacModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    let spaceID: String

    private let presets: [(String, Color)] = [
        ("Sky", Color(red: 0.80, green: 0.88, blue: 0.98)), ("Peach", Color(red: 0.98, green: 0.86, blue: 0.78)),
        ("Mint", Color(red: 0.84, green: 0.95, blue: 0.86)), ("Lilac", Color(red: 0.92, green: 0.85, blue: 0.98)),
        ("Butter", Color(red: 0.98, green: 0.95, blue: 0.78)), ("Rose", Color(red: 0.98, green: 0.82, blue: 0.86)),
        ("Slate", Color(red: 0.78, green: 0.82, blue: 0.88)),
    ]

    var body: some View {
        let space = model.space(spaceID)
        let style = SpaceStyle(space, scheme: scheme)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                if let space { SpaceIcon(space: space, size: 22) }
                Text(space?.title ?? "Space").font(.system(.title2, design: .rounded, weight: .bold))
            }
            RoundedRectangle(cornerRadius: MacRadius.card, style: .continuous)
                .fill(style.gradient)
                .overlay(alignment: .bottomLeading) {
                    Circle().fill(style.tint).frame(width: 18, height: 18).shadow(color: style.tint, radius: 8).padding(12)
                }
                .frame(height: 90)
                .animation(.easeInOut(duration: 0.2), value: space)
            HStack(spacing: 8) {
                ForEach(presets, id: \.0) { name, color in
                    Button { applyPreset(color) } label: {
                        Circle().fill(color).frame(width: 26, height: 26)
                            .overlay(Circle().strokeBorder(.black.opacity(0.1)))
                    }
                    .buttonStyle(PresetStyle())
                    .help(name)
                    .accessibilityLabel(name)
                }
            }
            ForEach(ThemeJSON.Role.allCases) { role in
                ColorPicker(role.label, selection: binding(role, space: space), supportsOpacity: false)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 360)
    }

    private func binding(_ role: ThemeJSON.Role, space: Space?) -> Binding<Color> {
        Binding {
            let theme = space?.theme
            let rgba: WindowTheme.RGBA? = switch role {
            case .backgroundLight: theme?.color("background", dark: false)
            case .backgroundDark: theme?.color("background", dark: true)
            case .accent: theme?.primaryColorPalette?["midTone"]
            }
            return rgba?.color ?? .gray
        } set: { color in
            model.setThemeColor(NSColor(color), role: role, of: spaceID)
        }
    }

    private func applyPreset(_ color: Color) {
        let base = NSColor(color).usingColorSpace(.sRGB) ?? .white
        let r = base.redComponent, g = base.greenComponent, b = base.blueComponent
        withAnimation(.easeInOut(duration: 0.35)) {
            model.setThemeColor(base, role: .backgroundLight, of: spaceID)
            model.setThemeColor(NSColor(srgbRed: r * 0.25, green: g * 0.25, blue: b * 0.3, alpha: 1), role: .backgroundDark, of: spaceID)
            model.setThemeColor(NSColor(srgbRed: r * 0.7, green: g * 0.7, blue: b * 0.9, alpha: 1), role: .accent, of: spaceID)
        }
    }
}

private struct PresetStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}
