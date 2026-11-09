import BoazKit
import SwiftUI
import UniformTypeIdentifiers

/// Archive (closed and auto-archived tabs) and History, grouped by day.
struct LibrarySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0
    @State private var query = ""
    @State private var archive: [ArchiveItem] = []
    @State private var history: [HistoryVisit] = []
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                if tab == 0 {
                    ForEach(grouped(filteredArchive, by: \.archivedAt), id: \.day) { group in
                        Section(dayLabel(group.day)) {
                            ForEach(group.items) { item in
                                Row(title: item.title, url: item.url,
                                    detail: item.reason == "autoArchived" ? "Archived" : "Closed") { model.restore(item) }
                                    .swipeActions {
                                        Button("Delete", systemImage: "trash", role: .destructive) {
                                            try? model.store?.removeFromArchive(item.id)
                                            reload()
                                        }
                                    }
                            }
                        }
                    }
                } else {
                    ForEach(grouped(history, by: \.visitedAt), id: \.day) { group in
                        Section(dayLabel(group.day)) {
                            ForEach(group.items) { visit in
                                Row(title: visit.title, url: visit.url,
                                    detail: visit.visitedAt.formatted(date: .omitted, time: .shortened)) {
                                    model.openAfterSheet(visit.url, title: visit.title)
                                }
                                .contextMenu {
                                    Button("Open", systemImage: "arrow.up.right.square") {
                                        model.openAfterSheet(visit.url, title: visit.title)
                                    }
                                    Button("Copy Link", systemImage: "link") { UIPasteboard.general.url = visit.url }
                                }
                            }
                        }
                    }
                }
            }
            .overlay {
                if !query.isEmpty, (tab == 0 ? filteredArchive.isEmpty : history.isEmpty) {
                    ContentUnavailableView.search(text: query)
                } else if (tab == 0 ? archive.isEmpty : history.isEmpty) {
                    ContentUnavailableView(tab == 0 ? "Archive is empty" : "No history",
                                           systemImage: tab == 0 ? "archivebox" : "clock",
                                           description: Text(tab == 0 ? "Closed and inactive tabs land here." : "Pages you visit appear here."))
                }
            }
            .searchable(text: $query)
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Library", selection: $tab) {
                        Text("Archive").tag(0)
                        Text("History").tag(1)
                    }
                    .pickerStyle(.segmented).fixedSize()
                }
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Button(tab == 0 ? "Clear Archive" : "Clear History", role: .destructive) { confirmClear = true }
                        // History is filtered by the search, so only an unfiltered empty list proves there's nothing to clear.
                        .disabled(tab == 0 ? archive.isEmpty : (query.isEmpty && history.isEmpty))
                        .confirmationDialog(tab == 0 ? "Clear the whole Archive?" : "Clear all history?",
                                            isPresented: $confirmClear, titleVisibility: .visible) {
                            Button(tab == 0 ? "Clear Archive" : "Clear History", role: .destructive) {
                                if tab == 0 { try? model.store?.clearArchive() } else { try? model.store?.clearHistory() }
                                reload()
                            }
                        } message: {
                            Text("This can't be undone.")
                        }
                }
            }
        }
        .onAppear(perform: reload)
        .onChange(of: query) { reload() }
    }

    private var filteredArchive: [ArchiveItem] {
        guard !query.isEmpty else { return archive }
        return archive.filter { ($0.title ?? "").localizedCaseInsensitiveContains(query)
            || $0.url.absoluteString.localizedCaseInsensitiveContains(query) }
    }

    private func reload() {
        archive = (try? model.store?.archivedItems()) ?? []
        history = (try? model.store?.history(matching: query)) ?? []
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month().day())
    }

    private func grouped<T: Identifiable>(_ items: [T], by date: KeyPath<T, Date>) -> [(day: Date, items: [T])] {
        let calendar = Calendar.current
        var groups: [(day: Date, items: [T])] = []
        for item in items {
            let day = calendar.startOfDay(for: item[keyPath: date])
            if groups.last?.day == day { groups[groups.count - 1].items.append(item) } else { groups.append((day, [item])) }
        }
        return groups
    }
}

private struct Row: View {
    let title: String?
    let url: URL
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Monogram(url: url, tint: Theme.brand, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title ?? url.host() ?? url.absoluteString).lineLimit(1)
                    Text(url.host() ?? "").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(detail).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .foregroundStyle(.primary)
    }
}

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Preferences.archiveAfterKey) private var archiveAfter = ArchiveInterval.day.rawValue
    @AppStorage(Preferences.searchEngineKey) private var searchEngine = SearchEngine.duckDuckGo.rawValue
    @AppStorage("blockTrackers") private var blockTrackers = true
    @AppStorage("hideCookieBanners") private var hideCookieBanners = true
    @AppStorage(Preferences.tintWithSiteColorsKey) private var tintWithSiteColors = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Archive Inactive Tabs After", selection: $archiveAfter) {
                        ForEach(ArchiveInterval.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } footer: {
                    Text("Tabs you haven't opened in this long move to the Archive. Pinned tabs and favorites stay put.")
                }
                Section("Search") {
                    Picker("Search engine", selection: $searchEngine) {
                        ForEach(SearchEngine.allCases) { Text($0.name).tag($0.rawValue) }
                    }
                }
                Section {
                    Toggle("Block ads and trackers", isOn: $blockTrackers)
                    Toggle("Hide cookie banners", isOn: $hideCookieBanners)
                } header: {
                    Text("Content")
                } footer: {
                    Text("Boaz blocks known ad and tracking requests, and dismisses cookie consent pop-ups by declining non-essential cookies where the site allows it. Turn either off if a site breaks.")
                }
                Section {
                    Toggle("Tint chrome with site colors", isOn: $tintWithSiteColors)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("The toolbar and the strip around the page take on the color of the site you're on.")
                }
                SyncSettingsSection()
                AppIconPicker()
                AboutSection()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } } }
        }
    }
}

/// iCloud sync status and Sync Now; a sync folder is offered only while iCloud can't sync on this iPhone.
private struct SyncSettingsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var picking = false
    @State private var pickError: String?

    var body: some View {
        if let sync = model.sync {
            Section {
                SyncStatusLabel(status: sync.status)
                if ICloudSignIn.needsSignIn(sync.status) {
                    Button("Sign In to iCloud") { if let url = ICloudSignIn.settingsURL { openURL(url) } }
                } else {
                    Button("Sync Now") { Task { await sync.syncNow(userInitiated: true) } }
                        .disabled(sync.status == .syncing)
                }
                if sync.offersFolder {
                    LabeledContent("Sync Folder", value: sync.folderURL?.lastPathComponent ?? "None")
                    Button(sync.folderURL == nil ? "Sync Through a Folder…" : "Change Folder…") { picking = true }
                    if let pickError { Text(pickError).font(.footnote).foregroundStyle(.secondary) }
                }
            } header: {
                Text("iCloud Sync")
            } footer: {
                Text(sync.offersFolder
                     ? "Until iCloud is available, you can sync through a folder your Mac can reach too, like iCloud Drive › Boaz."
                     : "Spaces, pins, tabs and the Archive sync through your iCloud account. History and private tabs stay on this iPhone.")
            }
            .syncFolderImporter(isPresented: $picking, sync: sync, message: $pickError)
        }
    }
}

