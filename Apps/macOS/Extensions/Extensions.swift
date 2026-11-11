import AppKit
import BoazKit
import WebKit

/// Chrome-style web extensions through WebKit's `WKWebExtension`: one controller per profile, attached to every page
/// of that profile, with the installed extensions, their granted permissions and enabled state kept in
/// Application Support/Extensions. See docs/extensions.md.
@Observable
final class Extensions: NSObject {
    static let shared = Extensions()

    /// An installed extension in one profile.
    struct Installed: Codable, Identifiable, Hashable {
        var id: String { "\(profileID)/\(extensionID)" }
        /// The Chrome Web Store ID, or a UUID for one loaded from disk.
        var extensionID: String
        var profileID: String
        /// Names the extension's storage and its `webkit-extension://` origin across launches.
        var contextID: UUID
        var name: String
        var enabled = true
        var permissions: [String] = []
        var matchPatterns: [String] = []
        var fromWebStore = false
    }

    /// An extension downloaded or chosen, waiting for the user to accept its permissions.
    struct PendingInstall: Identifiable {
        let id = UUID()
        let extensionID: String
        let profileID: String
        let fromWebStore: Bool
        /// A ZIP archive, or an unpacked folder, still where it was found.
        let source: URL
        let webExtension: WKWebExtension
    }

    enum InstallError: LocalizedError {
        case notAnExtensionID, notACRX
        var errorDescription: String? {
            switch self {
            case .notAnExtensionID: "That isn't a Chrome Web Store address or extension ID."
            case .notACRX: "That file isn't a Chrome extension."
            }
        }
    }

    private(set) var installed: [Installed] = []
    /// Changes when an extension's toolbar button (icon, badge, title) changes, so the buttons redraw.
    private(set) var actionsVersion = 0

    @ObservationIgnored private let model = MacModel.shared
    @ObservationIgnored private var controllers: [String: WKWebExtensionController] = [:]
    @ObservationIgnored private var contexts: [Installed.ID: WKWebExtensionContext] = [:]
    @ObservationIgnored private var tabRefs: [String: ExtensionTab] = [:]
    @ObservationIgnored private var windowRefs: [ObjectIdentifier: ExtensionWindow] = [:]
    /// Where each extension's toolbar button is, for its popup to point at.
    @ObservationIgnored var actionAnchors: [String: WeakView] = [:]
    @ObservationIgnored private var loaded = false

    struct WeakView { weak var view: NSView? }

    private static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "Extensions", directoryHint: .isDirectory)
    }
    private static var listURL: URL { folder.appending(path: "installed.json") }

    // MARK: Controllers

    /// The controller for a profile's pages; nil for private pages, which run no extensions.
    func controller(profileID: String?) -> WKWebExtensionController? {
        guard let profileID, let profile = model.sidebar.profiles.first(where: { $0.id == profileID }) else { return nil }
        if let controller = controllers[profileID] { return controller }
        // Keyed by the profile's data store, so extension storage stays with the profile's logins.
        let configuration = WKWebExtensionController.Configuration(identifier: profile.dataStoreID)
        configuration.defaultWebsiteDataStore = model.dataStore(for: profileID)
        let controller = WKWebExtensionController(configuration: configuration)
        controller.delegate = self
        controllers[profileID] = controller
        return controller
    }

    func context(_ installed: Installed) -> WKWebExtensionContext? { contexts[installed.id] }

    /// Enabled extensions with a toolbar button, for a profile.
    func actions(profileID: String?) -> [(installed: Installed, context: WKWebExtensionContext)] {
        installed.filter { $0.profileID == profileID && $0.enabled }.compactMap { item in contexts[item.id].map { (item, $0) } }
    }

    /// Loads the installed extensions, once the library (and so the profiles) is there.
    func loadInstalled() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: Self.listURL),
              let list = try? JSONDecoder().decode([Installed].self, from: data) else { return }
        installed = list.filter { item in model.sidebar.profiles.contains { $0.id == item.profileID } }
        Task {
            for item in installed where item.enabled { await load(item) }
        }
    }

    private func load(_ item: Installed) async {
        guard let controller = controller(profileID: item.profileID),
              let url = Self.storedURL(item), let webExtension = try? await WKWebExtension(resourceBaseURL: url),
              // Turned on twice, or while launch loads it: it's loaded once.
              contexts[item.id] == nil else { return }
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = item.contextID.uuidString
        context.baseURL = URL(string: "webkit-extension://\(item.contextID.uuidString.lowercased())/")!
        for permission in item.permissions { context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission(permission)) }
        for pattern in item.matchPatterns {
            if let pattern = try? WKWebExtension.MatchPattern(string: pattern) { context.setPermissionStatus(.grantedExplicitly, for: pattern) }
        }
        do {
            try controller.load(context)
            contexts[item.id] = context
            actionsVersion += 1
        } catch {
            model.showToast("Couldn't load \(item.name): \(error.localizedDescription)")
        }
    }

    private func unload(_ item: Installed) {
        guard let context = contexts.removeValue(forKey: item.id) else { return }
        try? controllers[item.profileID]?.unload(context)
        actionsVersion += 1
    }

    private func save() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(installed).write(to: Self.listURL, options: .atomic)
    }

    private static func directory(_ extensionID: String, profileID: String) -> URL {
        folder.appending(path: profileID, directoryHint: .isDirectory).appending(path: extensionID, directoryHint: .isDirectory)
    }

    /// A ZIP archive (`extension.zip`), or an unpacked folder (`Extension`), which WebKit reads alike.
    private static func storedURL(_ item: Installed) -> URL? {
        let directory = directory(item.extensionID, profileID: item.profileID)
        return ["extension.zip", "Extension"].map { directory.appending(path: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    // MARK: Installing

    /// The extension ID in a Chrome Web Store address (`chromewebstore.google.com/detail/<name>/<id>`), or the ID itself.
    static func webStoreID(in text: String) -> String? {
        let isID = { (s: Substring) in s.count == 32 && s.allSatisfy { ("a"..."p").contains($0) } }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isID(Substring(trimmed)) { return trimmed }
        guard let url = URL(string: trimmed), let host = url.host(),
              host == "chromewebstore.google.com" || host == "chrome.google.com" else { return nil }
        let parts = url.pathComponents
        guard parts.contains("detail"), let id = parts.last.map({ Substring($0) }), isID(id) else { return nil }
        return String(id)
    }

    #if DIRECT_DISTRIBUTION
    /// Downloads a Chrome Web Store extension through Google's public update service, as Chrome fetches one.
    func prepare(webStoreID id: String, profileID: String) async throws -> PendingInstall {
        var components = URLComponents(string: "https://clients2.google.com/service/update2/crx")!
        components.queryItems = [.init(name: "response", value: "redirect"), .init(name: "acceptformat", value: "crx2,crx3"),
                                 .init(name: "prodversion", value: "140.0.0.0"), .init(name: "x", value: "id=\(id)&uc")]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try await prepare(archive: try Self.zip(fromCRX: data), extensionID: id, profileID: profileID, fromWebStore: true)
    }
    #endif

    /// A `.crx` or `.zip` file, or an unpacked extension folder, chosen on disk.
    func prepare(file url: URL, profileID: String) async throws -> PendingInstall {
        let id = UUID().uuidString.lowercased()
        if url.hasDirectoryPath {
            let webExtension = try await WKWebExtension(resourceBaseURL: url)
            return PendingInstall(extensionID: id, profileID: profileID, fromWebStore: false, source: url, webExtension: webExtension)
        }
        return try await prepare(archive: try Self.zip(fromCRX: Data(contentsOf: url)), extensionID: id, profileID: profileID,
                                 fromWebStore: false)
    }

    private func prepare(archive: Data, extensionID: String, profileID: String, fromWebStore: Bool) async throws -> PendingInstall {
        let file = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).zip")
        try archive.write(to: file)
        let webExtension = try await WKWebExtension(resourceBaseURL: file)
        return PendingInstall(extensionID: extensionID, profileID: profileID, fromWebStore: fromWebStore, source: file,
                              webExtension: webExtension)
    }

    /// The ZIP inside a CRX: CRX3 is `Cr24`, version 3, a header length and the header; CRX2 is `Cr24`, version 2, then
    /// a key length and a signature length followed by both. A plain ZIP passes through.
    static func zip(fromCRX data: Data) throws -> Data {
        let bytes = [UInt8](data)
        func uint32(_ offset: Int) -> Int {
            // Past the end reads as the file's length, so a cut-off header fails the check below.
            guard bytes.count >= offset + 4 else { return bytes.count }
            return Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return data }
        guard bytes.starts(with: Array("Cr24".utf8)) else { throw InstallError.notACRX }
        let start = switch uint32(4) {
        case 3: 12 + uint32(8)
        case 2: 16 + uint32(8) + uint32(12)
        default: Int.max
        }
        guard start < bytes.count, bytes[start...].starts(with: [0x50, 0x4B, 0x03, 0x04]) else { throw InstallError.notACRX }
        return Data(bytes[start...])
    }

    /// Installs an accepted extension with the permissions it asked for, replacing an earlier copy of it.
    func install(_ pending: PendingInstall) async {
        let item = Installed(extensionID: pending.extensionID, profileID: pending.profileID, contextID: UUID(),
                             name: pending.webExtension.displayName ?? "Extension",
                             permissions: pending.webExtension.requestedPermissions.map(\.rawValue).sorted(),
                             matchPatterns: pending.webExtension.requestedPermissionMatchPatterns.map(\.string).sorted(),
                             fromWebStore: pending.fromWebStore)
        if let old = installed.first(where: { $0.id == item.id }) { remove(old) }
        let directory = Self.directory(item.extensionID, profileID: item.profileID)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if pending.source.hasDirectoryPath {
                try FileManager.default.copyItem(at: pending.source, to: directory.appending(path: "Extension"))
            } else {
                try FileManager.default.moveItem(at: pending.source, to: directory.appending(path: "extension.zip"))
            }
        } catch {
            model.showToast("Couldn't install \(item.name): \(error.localizedDescription)")
            return
        }
        installed.append(item)
        save()
        await load(item)
        model.showToast("Added \(item.name)")
    }

    func setEnabled(_ enabled: Bool, for item: Installed) {
        guard let index = installed.firstIndex(of: item) else { return }
        installed[index].enabled = enabled
        save()
        let item = installed[index]
        if enabled { Task { await load(item) } } else { unload(item) }
    }

    func remove(_ item: Installed) {
        unload(item)
        installed.removeAll { $0.id == item.id }
        save()
        try? FileManager.default.removeItem(at: Self.directory(item.extensionID, profileID: item.profileID))
    }

    /// A deleted profile's extensions go with it, and its controller, which holds the profile's data store.
    func forget(profileIDs: Set<String>) {
        for item in installed where profileIDs.contains(item.profileID) { remove(item) }
        profileIDs.forEach { controllers[$0] = nil }
    }

    func openOptions(_ item: Installed) {
        guard let url = contexts[item.id]?.optionsPageURL else { return }
        model.lastActiveBrowser?.openTab(url)
    }

    /// Records permissions granted after install (a prompt from the extension), so they hold after relaunch.
    private func remember(_ context: WKWebExtensionContext) {
        guard let index = installed.firstIndex(where: { contexts[$0.id] === context }) else { return }
        installed[index].permissions = context.grantedPermissions.keys.map(\.rawValue).sorted()
        installed[index].matchPatterns = context.grantedPermissionMatchPatterns.keys.map(\.string).sorted()
        save()
    }

    // MARK: Tabs and windows

    func tabRef(_ tabID: String, in browser: BrowserState) -> ExtensionTab {
        if let ref = tabRefs[tabID], ref.browser === browser { return ref }
        let ref = ExtensionTab(id: tabID, browser: browser)
        tabRefs[tabID] = ref
        return ref
    }

    func windowRef(_ browser: BrowserState) -> ExtensionWindow {
        if let ref = windowRefs[ObjectIdentifier(browser)] { return ref }
        let ref = ExtensionWindow(browser: browser)
        windowRefs[ObjectIdentifier(browser)] = ref
        return ref
    }

    private var windows: [ExtensionWindow] { model.openBrowsers.map(windowRef) }

    func didOpenWindow(_ browser: BrowserState) {
        guard !browser.isIncognito else { return }
        controllers.values.forEach { $0.didOpenWindow(windowRef(browser)) }
    }

    func didCloseWindow(_ browser: BrowserState) {
        guard let ref = windowRefs.removeValue(forKey: ObjectIdentifier(browser)) else { return }
        controllers.values.forEach { $0.didCloseWindow(ref) }
    }

    func didFocusWindow(_ browser: BrowserState) {
        guard !browser.isIncognito else { return }
        controllers.values.forEach { $0.didFocusWindow(windowRef(browser)) }
    }

    func didActivate(_ tab: SidebarItem, previous: String?, in browser: BrowserState) {
        guard !browser.isIncognito, let controller = controllers[tab.profileID] else { return }
        controller.didActivateTab(tabRef(tab.id, in: browser), previousActiveTab: previous.map { tabRef($0, in: browser) })
    }

    /// Clicks an extension's toolbar button: its popup, or its `action.onClicked`.
    func performAction(_ context: WKWebExtensionContext, in browser: BrowserState) {
        context.performAction(for: browser.activeTabID.map { tabRef($0, in: browser) })
    }
}

// MARK: - Delegate

extension Extensions: WKWebExtensionControllerDelegate {
    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext)
        -> [any WKWebExtensionWindow] { windows }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext)
        -> (any WKWebExtensionWindow)? { model.lastActiveBrowser.map(windowRef) }

    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionTab)?, (any Error)?) -> Void) {
        guard let browser = (configuration.window as? ExtensionWindow)?.browser ?? model.lastActiveBrowser,
              let url = configuration.url else { completionHandler(nil, nil); return }
        let previous = browser.activeTabID
        browser.openTab(url)
        let tab = browser.activeTabID.flatMap { $0 == previous ? nil : tabRef($0, in: browser) }
        if let tab { controller.didOpenTab(tab) }
        completionHandler(tab, nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
                                for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any WKWebExtensionWindow)?, (any Error)?) -> Void) {
        // A new Boaz window would open asynchronously; the URLs open as tabs of the current one instead.
        guard let browser = model.lastActiveBrowser else { completionHandler(nil, nil); return }
        configuration.tabURLs.forEach { browser.openTab($0) }
        completionHandler(windowRef(browser), nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping ((any Error)?) -> Void) {
        if let url = extensionContext.optionsPageURL { model.lastActiveBrowser?.openTab(url) }
        completionHandler(nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.Permission>, Date?) -> Void) {
        let allowed = ask(extensionContext, for: permissions.map(Self.describe).sorted())
        completionHandler(allowed ? permissions : [], nil)
        if allowed { Task { self.remember(extensionContext) } }
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<WKWebExtension.MatchPattern>, Date?) -> Void) {
        let allowed = ask(extensionContext, for: matchPatterns.map(Self.describe).sorted())
        completionHandler(allowed ? matchPatterns : [], nil)
        if allowed { Task { self.remember(extensionContext) } }
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext,
                                completionHandler: @escaping (Set<URL>, Date?) -> Void) {
        let allowed = ask(extensionContext, for: urls.compactMap { $0.host() }.sorted())
        completionHandler(allowed ? urls : [], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action,
                                forExtensionContext context: WKWebExtensionContext) {
        actionsVersion += 1
    }

    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext, completionHandler: @escaping ((any Error)?) -> Void) {
        guard let popover = action.popupPopover else { completionHandler(nil); return }
        if let anchor = actionAnchors[context.uniqueIdentifier]?.view, anchor.window != nil {
            popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        } else if let view = model.lastActiveBrowser?.window?.contentView {
            popover.show(relativeTo: NSRect(x: 40, y: view.bounds.maxY - 80, width: 1, height: 1), of: view, preferredEdge: .maxY)
        }
        completionHandler(nil)
    }

    /// Asks before an extension gets more than it was installed with.
    private func ask(_ context: WKWebExtensionContext, for items: [String]) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\"\(context.webExtension.displayName ?? "An extension")\" wants more access"
        alert.informativeText = items.joined(separator: "\n")
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don't Allow")
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func describe(_ permission: WKWebExtension.Permission) -> String {
        switch permission {
        case .tabs: "See your tabs and their addresses"
        case .cookies: "Read and change cookies"
        case .storage, .unlimitedStorage: "Store data"
        case .webNavigation: "See the pages you visit"
        case .webRequest: "See network requests"
        case .declarativeNetRequest, .declarativeNetRequestWithHostAccess, .declarativeNetRequestFeedback:
            "Block or change content on pages"
        case .scripting: "Run scripts on pages"
        case .activeTab: "Use the current page when you click it"
        case .contextMenus, .menus: "Add items to menus"
        case .clipboardWrite: "Write to the clipboard"
        case .alarms: "Run on a schedule"
        case .nativeMessaging: "Talk to other apps"
        default: permission.rawValue
        }
    }

    static func describe(_ pattern: WKWebExtension.MatchPattern) -> String {
        pattern.matchesAllHosts ? "Read and change all websites" : "Read and change \(pattern.string)"
    }
}

/// WebPage keeps its WKWebView to itself, and WebKit's extension APIs need it to tell which tab a script runs in.
/// It's read through reflection: if WebKit renames the property, tabs still work, without per-tab scripting.
func backingWebView(of page: WebPage) -> WKWebView? {
    Mirror(reflecting: page).children.lazy.compactMap { $0.value as? WKWebView }.first
}
