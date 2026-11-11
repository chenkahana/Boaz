import AppKit
import BoazKit
import SwiftUI
import UniformTypeIdentifiers

/// Archive window (⌥⌘A): closed and auto-archived tabs by day; double-click or Restore reopens one.
struct ArchiveWindow: View {
    @Environment(MacModel.self) private var model
    @State private var items: [ArchiveItem] = []
    /// The search's results, from the whole archive: `items` holds only the newest entries.
    @State private var matches: (query: String, items: [ArchiveItem])?
    @State private var query = ""
    @State private var selection: ArchiveItem.ID?
    @State private var confirmClear = false

    var body: some View {
        // Until the search for the current text lands, the newest entries that match it.
        let filtered = query.isEmpty ? items
            : matches.flatMap { $0.query == query ? $0.items : nil } ?? items.filter { $0.matches(query) }
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
                            Button("Delete", role: .destructive) {
                                try? model.store?.removeFromArchive(item.id)
                                matches?.items.removeAll { $0.id == item.id }
                                reload()
                            }
                        }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: ArchiveItem.ID.self) { _ in } primaryAction: { ids in
            for id in ids { if let item = filtered.first(where: { $0.id == id }) { restore(item) } }
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
                    Button("Clear Archive", role: .destructive) {
                        try? model.store?.clearArchive()
                        matches = nil
                        reload()
                    }
                } message: {
                    Text("This can't be undone.")
                }
        }
        .navigationTitle("Archive")
        .task(id: model.sidebar) {
            reload()
            await search()
        }
        .task(id: query) {
            if !query.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            await search()
        }
    }

    private func reload() { items = (try? model.store?.archivedItems()) ?? [] }

    /// Searches the whole archive in the database, off the main thread.
    private func search() async {
        let searched = query
        guard !searched.isEmpty else { matches = nil; return }
        guard !Task.isCancelled, let store = model.store,
              let found = try? await store.archivedItems(matching: searched), !Task.isCancelled, searched == query
        else { return }
        matches = (searched, found)
    }

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
        .task(id: search) {
            guard let search, let store = model.store else { return }
            if !search.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
            guard !Task.isCancelled else { return }
            // Follows the database rather than the page: a visit is written after the navigation that records it.
            do {
                for try await found in store.historyUpdates(matching: search, limit: 1000) { visits = found }
            } catch {}
        }
    }

    /// The text to search history for, in the database off the main thread; nil until the library is open.
    private var search: String? { model.sidebar.spaces.isEmpty ? nil : query }
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
        // System label colors on the system background. Footnotes and values take the second level, which reads at
        // 4.5:1 or better (the system's secondary label is about 4:1 in Light).
        .foregroundStyle(.primary, Self.footnote)
        .frame(width: 520)
    }

    static let footnote = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.62) : NSColor(white: 0, alpha: 0.64)
    })
}

private struct GeneralSettings: View {
    @Environment(MacModel.self) private var model
    @AppStorage(Preferences.archiveAfterKey) private var archiveAfter = ArchiveInterval.day.rawValue
    @AppStorage(Preferences.searchEngineKey) private var searchEngine = SearchEngine.duckDuckGo.rawValue
    @AppStorage(Preferences.sidebarTextSizeKey) private var sidebarTextSize = SidebarStyle.defaultTextSize
    @AppStorage(PictureInPicture.whenLeavingKey) private var pictureInPictureWhenLeaving = true

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
                Picker("Sidebar text size", selection: $sidebarTextSize) {
                    Text("Small").tag(13.0)
                    Text("Medium").tag(14.0)
                    Text("Large").tag(16.0)
                }
                if PictureInPicture.isSupported {
                    Toggle(isOn: $pictureInPictureWhenLeaving) {
                        Text("Picture in Picture when you leave a video")
                        Text("A playing video floats when you switch tabs or spaces, or its window is hidden, and comes back when you return.")
                    }
                }
            }
            AISettingsSection()
            AboutSection()
        }
        .formStyle(.grouped)
        // The Settings window takes this tab's height and can't be resized; without it About sat below the fold.
        .frame(minHeight: 600)
        .onChange(of: archiveAfter) { model.archiveStaleTabs() }
    }
}

private struct DefaultBrowserRow: View {
    @State private var current = DefaultBrowser.current()
    @State private var failed = false

    var body: some View {
        LabeledContent("Default browser") {
            if current.isBoaz {
                Text("Boaz")
            } else {
                HStack {
                    Text(current.name)
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
                Text("Sync starts once your library has loaded.")
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
