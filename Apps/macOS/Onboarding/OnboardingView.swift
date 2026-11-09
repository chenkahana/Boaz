import AppKit
import BoazKit
import SwiftUI
import UniformTypeIdentifiers

/// First-run setup in a sheet over the main window: sign in to iCloud, bring your browser, default browser, done.
/// Signing in comes first so everything imported afterwards syncs to the iPhone.
/// File ▸ Import from Another Browser… opens just the browser page.
struct OnboardingView: View {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome, browsers, defaultBrowser, done
        var id: Self { self }
    }

    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let steps: [Step]
    @State private var step: Step
    @State private var forward = true
    @State private var imports = BrowserImports()

    init(start: Step) {
        steps = start == .welcome ? Step.allCases : [start]
        _step = State(initialValue: start)
    }

    private var isFirstRun: Bool { steps.count > 1 }
    private var index: Int { steps.firstIndex(of: step) ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                page
                    .id(step)
                    .transition(Onboarding.pageTransition(forward: forward, reduceMotion: reduceMotion))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            footer
        }
        .padding(32)
        .frame(width: 640, height: 600)
        .background(Theme.hero)
        .environment(\.colorScheme, .dark)
        .onExitCommand { if !isFirstRun { dismiss() } }
    }

    // MARK: Pages

    @ViewBuilder private var page: some View {
        switch step {
        case .welcome:
            VStack(spacing: 24) {
                Spacer(minLength: 0)
                OnboardingHero(size: 112)
                OnboardingHeading(title: "Welcome to Boaz",
                                  message: "Sign in to iCloud to keep your spaces, pins and tabs in step on your Mac and iPhone.")
                SyncPanel()
                Spacer(minLength: 0)
            }
        case .browsers:
            VStack(spacing: 24) {
                OnboardingHero(size: 64)
                OnboardingHeading(title: "Bring your browser",
                                  message: "Import your sidebar or bookmarks. Boaz only reads them, and running it again won't make duplicates.")
                BrowserImportList(imports: imports, spaceID: browser.spaceID)
            }
        case .defaultBrowser:
            VStack(spacing: 24) {
                OnboardingHero(size: 64)
                OnboardingHeading(title: "Make Boaz your default",
                                  message: "Links you click in Mail, Messages and other apps open in Little Boaz, ready to keep or toss.")
                DefaultBrowserPanel()
            }
        case .done:
            VStack(spacing: 28) {
                Spacer()
                OnboardingHero(size: 148)
                OnboardingHeading(title: "You're all set", message: doneMessage)
                Spacer()
            }
        }
    }

    private var doneMessage: String {
        imports.finished.isEmpty
            ? "Press ⌘T to open your first tab. You can import from another browser any time from the File menu."
            : "Your tabs and bookmarks from \(ListFormatter.localizedString(byJoining: imports.finished)) are in the sidebar."
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if isFirstRun {
                OnboardingDots(count: steps.count, index: index)
                if index > 0 && step != .done {
                    Button("Back", systemImage: "chevron.left") { go(by: -1) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .tint(.white.opacity(0.12))
                        .keyboardShortcut("[", modifiers: .command)
                        .help("Back")
                }
            }
            Spacer()
            if let secondary {
                Button(secondary) { go(by: 1) }
                    .buttonStyle(.glass)
                    .tint(.white.opacity(0.12))
                    .keyboardShortcut(.cancelAction)
            }
            Button(primary, action: primaryAction)
                .buttonStyle(.glassProminent)
                .tint(.white)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.top, 20)
        .disabled(imports.isRunning)
    }

    private var primary: String {
        switch step {
        case .welcome where needsSignIn: "Sign In to iCloud…"
        case .welcome: "Continue"
        case .done: "Start Browsing"
        case _ where !isFirstRun: "Done"
        default: "Continue"
        }
    }

    /// Esc: skip this page (or, on the welcome page, the whole setup).
    private var secondary: String? {
        switch step {
        case .welcome: needsSignIn ? "Continue Without Syncing" : nil
        case .browsers: isFirstRun ? "Skip" : nil
        case .defaultBrowser: "Not Now"
        case .done: nil
        }
    }

    private var needsSignIn: Bool { model.sync.map { ICloudSignIn.needsSignIn($0.status) } ?? false }

    private func primaryAction() {
        if step == .welcome, needsSignIn {
            if let url = ICloudSignIn.settingsURL { openURL(url) }
        } else if step == steps.last {
            finish()
        } else {
            go(by: 1)
        }
    }

    private func go(by delta: Int) {
        let next = steps[min(max(index + delta, 0), steps.count - 1)]
        forward = delta > 0
        // Let the outgoing page pick up the new direction before it animates out.
        DispatchQueue.main.async { withAnimation(Onboarding.spring) { step = next } }
    }

    private func finish() {
        if isFirstRun {
            Onboarding.markCompleted()
            if let store = model.store { try? StarterLibrary.finishSetup(store, syncing: model.sync?.isConnected == true) }
        }
        dismiss()
    }
}

// MARK: - Bring your browser

/// What was imported during this run, for the summary on the last page.
@Observable
final class BrowserImports {
    var finished: [String] = []
    var isRunning = false
}

private struct SourceBrowser: Identifiable {
    enum Kind { case arc, chromium(supportFolder: String), bookmarksFile }

    let id: String
    let name: String
    let kind: Kind
    let appURL: URL?

    static let known: [(bundleID: String, name: String, kind: Kind)] = [
        ("company.thebrowser.Browser", "Arc", .arc),
        ("com.google.Chrome", "Chrome", .chromium(supportFolder: "Google/Chrome")),
        ("com.brave.Browser", "Brave", .chromium(supportFolder: "BraveSoftware/Brave-Browser")),
        ("com.microsoft.edgemac", "Edge", .chromium(supportFolder: "Microsoft Edge")),
        ("com.apple.Safari", "Safari", .bookmarksFile),
    ]

    /// Browsers installed on this Mac, then "another browser" for any bookmarks export.
    static func installed() -> [SourceBrowser] {
        known.compactMap { entry in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleID)
                .map { SourceBrowser(id: entry.bundleID, name: entry.name, kind: entry.kind, appURL: $0) }
        } + [SourceBrowser(id: "other", name: "Another browser", kind: .bookmarksFile, appURL: nil)]
    }

    var detail: String {
        switch kind {
        case .arc: "Spaces, favorites, pinned tabs and folders"
        case .chromium: "Bookmarks bar and folders, as pinned tabs"
        case .bookmarksFile where id == "com.apple.Safari": "In Safari, choose File › Export › Bookmarks…, then pick that file"
        case .bookmarksFile: "A bookmarks file (.html) exported from any browser"
        }
    }

    /// Id prefix for imported rows; keeps each browser's import separate so re-imports replace only their own.
    var source: String {
        switch id {
        case "com.google.Chrome": "chrome"
        case "com.brave.Browser": "brave"
        case "com.microsoft.edgemac": "edge"
        case "com.apple.Safari": "safari"
        default: "html"
        }
    }
}

private struct BrowserImportList: View {
    let imports: BrowserImports
    let spaceID: String?
    @State private var browsers = SourceBrowser.installed()

    var body: some View {
        VStack(spacing: 0) {
            ForEach(browsers) { source in
                BrowserImportRow(source: source, imports: imports, spaceID: spaceID)
                if source.id != browsers.last?.id { Divider().padding(.leading, 56) }
            }
        }
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

private struct BrowserImportRow: View {
    enum Phase: Equatable { case idle, running, imported(String), failed(String) }

    let source: SourceBrowser
    let imports: BrowserImports
    let spaceID: String?
    @Environment(MacModel.self) private var model
    @State private var state = Phase.idle
    @State private var showArc = false

    var body: some View {
        HStack(spacing: 12) {
            icon.frame(width: 32, height: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.name).font(.headline)
                Group {
                    switch state {
                    case .imported(let summary): Text(summary)
                    case .failed(let message): Text(message).foregroundStyle(.red)
                    default: Text(source.detail)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .animation(Onboarding.spring, value: state)
        .sheet(isPresented: $showArc, onDismiss: arcSheetClosed) {
            ArcImportView(store: model.store,
                          applyKeyBindings: { try MacModel.shared.keyBindings.applyArcKeyBindings(fileURL: $0) })
        }
    }

    @ViewBuilder private var icon: some View {
        if let app = source.appURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable()
        } else {
            Image(systemName: "doc.text").font(.title2).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch state {
        case .running:
            ProgressView().controlSize(.small)
        case .imported:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel("Imported")
                Button("Import Again", action: start).buttonStyle(.glass)
                    .accessibilityLabel("Import from \(source.name) again")
            }
        default:
            Button(source.appURL == nil || source.id == "com.apple.Safari" ? "Choose File…" : "Import…", action: start)
                .buttonStyle(.glass)
                .accessibilityLabel("Import from \(source.name)")
        }
    }

    // MARK: Import

    private func start() {
        switch source.kind {
        case .arc: showArc = true
        case .chromium(let folder): importChromium(supportFolder: folder)
        case .bookmarksFile: importBookmarksFile()
        }
    }

    private func arcSheetClosed() {
        let spaces = model.sidebar.spaces.filter { $0.id.hasPrefix(ArcSidebarImporter.idPrefix) }.count
        guard spaces > 0 else { return }
        let tabs = model.sidebar.items.filter { $0.kind == .tab && $0.id.hasPrefix(ArcSidebarImporter.idPrefix) }.count
        succeed("\(spaces) \(spaces == 1 ? "space" : "spaces"), \(tabs) \(tabs == 1 ? "tab" : "tabs")")
    }

    private func importChromium(supportFolder: String) {
        let key = "bookmarksFolder.\(source.id)"
        let folder = ReadOnlyFolder.restore(key) ?? {
            let panel = NSOpenPanel()
            panel.message = "Boaz needs to read \(source.name)'s bookmarks. Choose its folder in Library › Application Support."
            panel.prompt = "Allow Access"
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.showsHiddenFiles = true
            panel.directoryURL = ReadOnlyFolder.realHome.appending(path: "Library/Application Support/\(supportFolder)",
                                                                   directoryHint: .isDirectory)
            guard panel.runModal() == .OK, let url = panel.url else { return nil }
            return ReadOnlyFolder.save(url, key: key)
        }()
        guard let folder else { return }
        let prefix = source.source
        run {
            let scoped = folder.startAccessingSecurityScopedResource()
            defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
            guard let file = BookmarkImporter.chromiumBookmarksFile(in: folder) else {
                UserDefaults.standard.removeObject(forKey: key)
                throw BookmarkImportError.missingFile
            }
            return try BookmarkImporter.chromium(Data(contentsOf: file), source: prefix)
        }
    }

    private func importBookmarksFile() {
        let panel = NSOpenPanel()
        panel.message = source.id == "com.apple.Safari"
            ? "Choose the bookmarks file you exported from Safari (File › Export › Bookmarks…)."
            : "Choose a bookmarks file exported from your browser."
        panel.prompt = "Import"
        panel.allowedContentTypes = [.html]
        panel.directoryURL = ReadOnlyFolder.realHome.appending(path: "Downloads", directoryHint: .isDirectory)
        guard panel.runModal() == .OK, let file = panel.url else { return }
        let prefix = source.source
        run {
            let scoped = file.startAccessingSecurityScopedResource()
            defer { if scoped { file.stopAccessingSecurityScopedResource() } }
            return try BookmarkImporter.netscapeHTML(String(decoding: Data(contentsOf: file), as: UTF8.self),
                                                     source: prefix)
        }
    }

    /// Reads off the main thread, then merges into the window's current space.
    private func run(_ read: @escaping @Sendable () throws -> BookmarkImporter) {
        guard let store = model.store, let spaceID = spaceID ?? model.sidebar.spaces.first?.id else { return }
        state = .running
        imports.isRunning = true
        Task {
            defer { imports.isRunning = false }
            do {
                let summary = try await Task.detached { try read().importInto(store, spaceID: spaceID) }.value
                var text = "\(summary.folders) \(summary.folders == 1 ? "folder" : "folders"), "
                    + "\(summary.bookmarks) \(summary.bookmarks == 1 ? "bookmark" : "bookmarks")"
                if summary.skipped > 0 { text += " (\(summary.skipped) skipped)" }
                succeed(text)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func succeed(_ summary: String) {
        state = .imported(summary)
        if !imports.finished.contains(source.name) { imports.finished.append(source.name) }
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "\(source.name) imported: \(summary)"])
    }
}

/// A folder the user granted once, kept as a read-only security-scoped bookmark (as the Arc import does).
enum ReadOnlyFolder {
    /// The user's real home; inside the sandbox `homeDirectoryForCurrentUser` is the app container.
    static var realHome: URL {
        URL(fileURLWithPath: getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory())
    }

    static func save(_ url: URL, key: String) -> URL? {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                                               includingResourceValuesForKeys: nil, relativeTo: nil) else { return url }
        UserDefaults.standard.set(data, forKey: key)
        return restore(key) ?? url
    }

    static func restore(_ key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
                                 bookmarkDataIsStale: &stale), !stale else {
            UserDefaults.standard.removeObject(forKey: key)
            return nil
        }
        return url
    }
}

// MARK: - Sync

/// The iCloud account and sync state; a folder picker only when iCloud can't sync.
private struct SyncPanel: View {
    @Environment(MacModel.self) private var model
    @State private var message: String?

    var body: some View {
        if let sync = model.sync {
            ICloudSignInCard(sync: sync, library: model.sidebar.syncSummary, message: message,
                             showsSignInButton: false) {
                Button(sync.folderURL == nil ? "Sync Through a Folder Instead…" : "Change Folder…") {
                    Task { message = await sync.chooseFolder() }
                }
                .buttonStyle(.glass)
            }
            .frame(maxWidth: 460)
        }
    }
}

extension LibrarySync {
    /// Asks for the fallback sync folder, starting in iCloud Drive, and syncs through it. Returns a message if that failed.
    func chooseFolder() async -> String? {
        let panel = NSOpenPanel()
        panel.message = "Choose a folder to sync Boaz through, e.g. iCloud Drive › Boaz. Use the same one on your iPhone."
        panel.prompt = "Use Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        // The sandbox's home is the app container; iCloud Drive lives under the real one.
        if let home = getpwuid(getuid())?.pointee.pw_dir {
            panel.directoryURL = URL(fileURLWithPath: String(cString: home))
                .appending(path: "Library/Mobile Documents/com~apple~CloudDocs", directoryHint: .isDirectory)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try await setFolder(url)
            return nil
        } catch {
            return "Couldn't use that folder: \(error.localizedDescription)"
        }
    }
}

// MARK: - Default browser

private struct DefaultBrowserPanel: View {
    @State private var current = DefaultBrowser.current()
    @State private var message: String?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let app = current.appURL {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable()
                } else {
                    Image(systemName: "globe").font(.title).foregroundStyle(.secondary)
                }
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(current.isBoaz ? "Boaz is your default browser" : "Links open in \(current.name)").font(.headline)
                Text(message ?? (current.isBoaz ? "You're good to go." : "macOS will ask you to confirm."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if current.isBoaz {
                Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
                    .accessibilityHidden(true)
            } else {
                Button("Make Default", action: makeDefault).buttonStyle(.glass)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .animation(Onboarding.spring, value: current.isBoaz)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            current = DefaultBrowser.current()
        }
    }

    /// Asks macOS, which shows its own confirmation; Boaz never changes the setting itself.
    private func makeDefault() {
        Task {
            do {
                try await DefaultBrowser.makeBoazDefault()
                message = nil
            } catch {
                message = "Your default browser didn't change."
            }
            current = DefaultBrowser.current()
        }
    }
}

struct DefaultBrowser: Equatable {
    var appURL: URL?
    var name: String
    var isBoaz: Bool

    static func makeBoazDefault() async throws {
        for scheme in ["http", "https"] {
            try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
        }
    }

    static func current() -> DefaultBrowser {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else {
            return DefaultBrowser(appURL: nil, name: "another browser", isBoaz: false)
        }
        return DefaultBrowser(appURL: app, name: FileManager.default.displayName(atPath: app.path),
                              isBoaz: Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier)
    }
}
