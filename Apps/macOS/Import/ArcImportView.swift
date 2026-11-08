import AppKit
import FolioKit
import SwiftUI

/// File ▸ Import from Arc… sheet (also opened from onboarding). Shows what will come over (each space with its
/// icon and colors, tab counts), imports with one button, then shows the spaces that arrived.
/// Pass the app's shared store so the sidebar observation sees the import.
struct ArcImportView: View {
    static let bookmarkKey = "arcFolderBookmark"

    var store: FolioStore?
    /// Applies `StorableKeyBindings.json` from the granted Arc folder; returns the number of shortcuts applied.
    var applyKeyBindings: ((URL) throws -> Int)?

    init(store: FolioStore? = nil, applyKeyBindings: ((URL) throws -> Int)? = nil) {
        self.store = store
        self.applyKeyBindings = applyKeyBindings
    }

    private enum Phase: Equatable { case needsFolder, reading, preview, importing, done }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var folder: URL?
    @State private var phase = Phase.needsFolder
    @State private var snapshot: ArcSnapshot?
    @State private var importCookies = false
    @State private var status: String?
    @State private var results: [String] = []
    @State private var errors: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            switch phase {
            case .needsFolder:
                Label("Folio reads Arc's sidebar from its data folder. macOS asks you to choose it once; Folio only reads it.",
                      systemImage: "folder.badge.questionmark")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            case .reading:
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Reading your Arc sidebar…") }
            case .preview, .importing, .done:
                if let snapshot { SpaceGrid(snapshot: snapshot, arrived: phase == .done) }
                if phase != .done { cookieOption }
            }

            if let status, phase == .importing {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text(status) }
            }
            if !results.isEmpty || !errors.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(results, id: \.self) { Text($0).foregroundStyle(.secondary) }
                    ForEach(errors, id: \.self) { Label($0, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            }

            buttons
        }
        .padding(24)
        .frame(width: 560)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: phase)
        .onAppear(perform: restoreBookmark)
    }

    // MARK: Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(phase == .done ? "Your Arc is here" : "Import from Arc").font(.title2.bold())
                .contentTransition(.opacity)
            Text(subtitle)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subtitle: String {
        guard let snapshot else {
            return "Brings over your spaces exactly as they are: names, icons, colors, favorites, pinned tabs and folders, in the same order."
        }
        let tabs = snapshot.items.filter { $0.kind == .tab }.count
        let favorites = snapshot.tabCounts[.favorites] ?? 0
        var parts = ["\(snapshot.spaces.count) \(snapshot.spaces.count == 1 ? "space" : "spaces")",
                     "\(tabs) \(tabs == 1 ? "tab" : "tabs")"]
        if favorites > 0 { parts.append("\(favorites) \(favorites == 1 ? "favorite" : "favorites")") }
        if snapshot.folders > 0 { parts.append("\(snapshot.folders) \(snapshot.folders == 1 ? "folder" : "folders")") }
        if snapshot.profiles.count > 1 { parts.append("\(snapshot.profiles.count) profiles") }
        var text = parts.joined(separator: " · ")
        if phase != .done {
            text += ". Running it again later updates what came from Arc and leaves anything you made in Folio alone."
        }
        if snapshot.splitViews > 0 {
            text += " \(snapshot.splitViews) split \(snapshot.splitViews == 1 ? "view comes" : "views come") over as side-by-side tabs."
        }
        let left = snapshot.skippedTabs + snapshot.skippedItems
        if left > 0 { text += " \(left) Arc-only \(left == 1 ? "item" : "items") (notes, easels, arc:// pages) stay in Arc." }
        return text
    }

    private var cookieOption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Keep me signed in (copy Arc's cookies to this Mac)", isOn: $importCookies)
            Text(importCookies
                 ? "macOS will ask to let Folio use “Arc Safe Storage”. Click Allow, not Always Allow, so Folio reads it only this once. Quit Arc first. Cookies stay on this Mac and are never synced."
                 : "Cookies stay on this Mac and are never synced.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 20)
        }
        .disabled(phase == .importing)
    }

    private var buttons: some View {
        HStack {
            if folder != nil, phase == .preview {
                Button("Choose Another Folder…", action: chooseFolder).buttonStyle(.link)
            }
            Spacer()
            switch phase {
            case .done:
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            case .needsFolder:
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Choose Arc Folder…", action: chooseFolder).keyboardShortcut(.defaultAction)
            default:
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).disabled(phase == .importing)
                Button(importTitle) { Task { await runImport() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(phase != .preview || snapshot?.spaces.isEmpty != false)
            }
        }
    }

    private var importTitle: String {
        let count = snapshot?.spaces.count ?? 0
        return "Import \(count) \(count == 1 ? "Space" : "Spaces")"
    }

    // MARK: Folder access (sandbox)

    /// The user's real home; inside the sandbox `homeDirectoryForCurrentUser` is the app container.
    private static var arcDefaultFolder: URL {
        let home = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appending(path: "Library/Application Support/Arc", directoryHint: .isDirectory)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.message = "Choose Arc's data folder (Library ▸ Application Support ▸ Arc) so Folio can read your sidebar."
        panel.prompt = "Allow Access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = Self.arcDefaultFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard FileManager.default.fileExists(atPath: url.appending(path: "StorableSidebar.json").path) else {
            errors = ["That folder doesn't contain Arc's StorableSidebar.json. Choose ~/Library/Application Support/Arc."]
            return
        }
        errors = []
        folder = url
        saveBookmark(url)
        Task { await loadPreview() }
    }

    private func saveBookmark(_ url: URL) {
        if let data = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                            includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
        }
    }

    private func restoreBookmark() {
        guard folder == nil, let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else {
            UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
            return
        }
        folder = url
        if stale {
            let scoped = url.startAccessingSecurityScopedResource()
            saveBookmark(url)
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        Task { await loadPreview() }
    }

    // MARK: Import

    private func loadPreview() async {
        guard let folder else { return }
        phase = .reading
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        do {
            snapshot = try await Task.detached { try ArcSidebarImporter(arcFolder: folder).parse() }.value
            phase = .preview
        } catch {
            snapshot = nil
            errors = [error.localizedDescription]
            phase = .needsFolder
        }
    }

    private func runImport() async {
        guard let folder else { return }
        phase = .importing
        results = []; errors = []
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        do {
            let store = try self.store ?? FolioStore.onDisk()
            status = "Importing spaces…"
            let (summary, parsed, icons) = try await Task.detached {
                let importer = try ArcSidebarImporter(arcFolder: folder)
                let snapshot = try importer.parse()
                let summary = try importer.importInto(store, snapshot: snapshot)
                return (summary, snapshot, importer.cachedFavicons(for: snapshot))
            }.value
            snapshot = parsed
            for (url, png) in icons { Favicons.shared.seed(png, for: url) }
            if summary.updated + summary.removed > 0 {
                results.append("Updated \(summary.updated) and removed \(summary.removed) items from an earlier import.")
            }
            do {
                if let applyKeyBindings,
                   case let shortcuts = try applyKeyBindings(folder.appending(path: "StorableKeyBindings.json")), shortcuts > 0 {
                    results.append("\(shortcuts) keyboard shortcuts")
                }
            } catch {
                errors.append("Keyboard shortcuts: \(error.localizedDescription)")
            }

            if importCookies {
                status = "Waiting for Keychain approval…"
                // Reads the real "Arc Safe Storage" key: only ever reached from this button.
                let storage = try await Task.detached { try ChromiumSafeStorage.fromKeychain() }.value
                let profiles = try await store.loadSidebar().profiles
                for (profileID, directory) in summary.profileDirectories.sorted(by: { $0.key < $1.key })
                    where summary.localProfileDirectories.contains(directory) && !directory.contains("/") && !directory.contains("..") {
                    let name = profiles.first { $0.id == profileID }?.name ?? directory
                    let profileFolder = folder.appending(path: "User Data/\(directory)", directoryHint: .isDirectory)
                    status = "Importing cookies for \(name)…"
                    await importCookies(profileFolder, profile: profiles.first { $0.id == profileID }, name: name, storage: storage)
                }
            }
            phase = .done
        } catch {
            errors.append(error.localizedDescription)
            phase = .preview
        }
    }

    private func importCookies(_ profileFolder: URL, profile: Profile?, name: String, storage: ChromiumSafeStorage) async {
        guard let profile else {
            errors.append("\(name) cookies: import spaces first so the profile exists in Folio.")
            return
        }
        do {
            // Newer Chromium keeps the database under Network/.
            let network = profileFolder.appending(path: "Network/Cookies")
            let database = FileManager.default.fileExists(atPath: network.path) ? network : profileFolder.appending(path: "Cookies")
            let (cookies, result) = try ArcCookieImporter.readCookies(from: database, storage: storage)
            await ArcCookieImporter.install(cookies, dataStoreID: profile.dataStoreID)
            results.append("Signed in as before in \(name): \(result.imported) cookies" + (result.failed > 0 ? ", \(result.failed) unreadable" : ""))
        } catch {
            errors.append("\(name) cookies: \(error.localizedDescription)")
        }
    }
}

/// The spaces Arc will bring over, each drawn in its own theme; checked off once they've arrived.
private struct SpaceGrid: View {
    let snapshot: ArcSnapshot
    let arrived: Bool

    var body: some View {
        let tabs = Dictionary(grouping: snapshot.items.filter { $0.kind == .tab && $0.spaceID != nil }, by: \.spaceID)
        let multiProfile = Set(snapshot.spaces.map(\.profileID)).count > 1
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(Array(snapshot.spaces.enumerated()), id: \.element.id) { index, space in
                    SpaceCard(space: space, tabs: tabs[space.id]?.count ?? 0,
                              profile: multiProfile ? snapshot.profiles.first { $0.id == space.profileID }?.name : nil,
                              arrived: arrived, delay: Double(index) * 0.06)
                }
            }
        }
        .frame(maxHeight: 300)
        .fixedSize(horizontal: false, vertical: snapshot.spaces.count <= 6)
    }
}

private struct SpaceCard: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let space: Space
    let tabs: Int
    let profile: String?
    let arrived: Bool
    let delay: Double

    var body: some View {
        let style = SpaceStyle(space, scheme: scheme)
        HStack(spacing: 10) {
            SpaceIcon(space: space, size: 22).frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(space.title).font(.headline).lineLimit(1)
                Text([profile, "\(tabs) \(tabs == 1 ? "tab" : "tabs")"].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).opacity(0.7).lineLimit(1)
            }
            Spacer(minLength: 0)
            if arrived {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(style.tint)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .foregroundStyle(style.foreground)
        .padding(12)
        .background {
            ZStack {
                style.gradient
                if style.grain > 0 { GrainOverlay(amount: style.grain) }
            }
            .clipShape(.rect(cornerRadius: 12, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.black.opacity(0.08)))
        .environment(\.colorScheme, SpaceStyle.colorScheme(of: space) ?? scheme)
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.7).delay(delay), value: arrived)
        .accessibilityElement(children: .combine)
    }
}
