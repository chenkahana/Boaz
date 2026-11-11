import AppKit
import CloudKit
import BoazKit
import SwiftUI

@main
struct BoazMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = MacModel.shared

    var body: some Scene {
        WindowGroup("Boaz", id: "main") {
            BrowserWindow(incognito: false)
                .environment(model)
                .tint(Theme.brand)
                .task { await model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .handlesExternalEvents(matching: [])
        // The app reopens its main windows itself (`MacModel.SavedWindow`), whatever the system setting.
        .restorationBehavior(.disabled)
        .commands {
            BoazCommands(model: model)
            #if SPARKLE
            UpdateCommands()
            #endif
        }

        WindowGroup("Incognito", id: "incognito") {
            BrowserWindow(incognito: true)
                .environment(model)
                .tint(Theme.violet)
                .task { await model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 760)
        .handlesExternalEvents(matching: [])
        .restorationBehavior(.disabled)

        WindowGroup("Quick Window", id: "little", for: URL.self) { $url in
            QuickWindow(url: url)
                .environment(model)
                .task { await model.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 620)
        .handlesExternalEvents(matching: [])
        // A peek window is for one link; relaunching shouldn't bring back a stack of empty ones.
        .restorationBehavior(.disabled)

        Window("Archive", id: "archive") {
            ArchiveWindow().environment(model)
        }
        .defaultSize(width: 540, height: 640)
        .handlesExternalEvents(matching: [])

        Window("History", id: "history") {
            HistoryWindow().environment(model)
        }
        .defaultSize(width: 560, height: 680)
        .handlesExternalEvents(matching: [])

        Settings {
            MacSettingsView().environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
        LinkDownloadMenu.install()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MacModel.shared.isQuitting = true
        return .terminateNow
    }

    /// Writes queued off the main thread would be lost with the process.
    func applicationWillTerminate(_ notification: Notification) {
        MacModel.shared.saveOpenWindows()
        MacModel.shared.store?.waitForQueuedWritesNow()
    }

    /// iCloud change pushes: fetch right away.
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { return }
        Task { await MacModel.shared.sync?.syncNow() }
    }

    /// Links opened from other apps (Boaz as the target of `open -a` or as default browser) go to a Quick Window.
    func application(_ application: NSApplication, open urls: [URL]) {
        MacModel.shared.openExternal(urls)
    }
}

/// Menu bar with Arc's default shortcuts; rebindable ones read from `KeyBindings`.
struct BoazCommands: Commands {
    let model: MacModel
    @FocusedValue(BrowserState.self) private var browser
    @Environment(\.openWindow) private var openWindow

    private func key(_ command: BrowserCommand) -> KeyboardShortcut? { model.keyBindings.shortcut(command) }

    var body: some Commands {
        // The menu is built at launch even when no window opens (a cold launch to open links), so links never
        // wait for a window that isn't coming.
        let _ = model.registerOpenWindow(openWindow)
        CommandGroup(replacing: .newItem) {
            Button("New Tab") { browser?.commandMode = .newTab }
                .keyboardShortcut(key(.newTab)).disabled(browser == nil)
            Button("New Window") { openWindow(id: "main") }.keyboardShortcut(key(.newWindow))
            Button("New Incognito Window") { openWindow(id: "incognito") }.keyboardShortcut(key(.newIncognitoWindow))
            Button("New Quick Window") { openWindow(id: "little") }.keyboardShortcut(key(.newLittleWindow))
            Divider()
            Button("Open Location…") { browser?.commandMode = browser?.activeTab == nil ? .newTab : .currentTab }
                .keyboardShortcut(key(.openLocation)).disabled(browser == nil)
            Divider()
            // Owning ⌘W takes it off the system's Close item, so this closes the other windows (History, Settings) too.
            Button(browser?.activeTab == nil ? "Close Window" : "Close Tab") {
                if let browser {
                    browser.closeActive()
                } else if let window = NSApp.keyWindow, window.styleMask.contains(.closable), window.sheetParent == nil {
                    // Not WebKit's full-screen video window or a sheet, which have no close button of their own.
                    window.performClose(nil)
                }
            }
            .keyboardShortcut(key(.closeTab))
            Button("Reopen Closed Tab") { browser?.reopenClosedTab() }
                .keyboardShortcut(key(.reopenClosedTab)).disabled(browser == nil)
            Divider()
            Button("Import from Arc…") {
                if let browser { browser.showImport = true } else { openWindow(id: "main") }
            }
            Button("Import from Another Browser…") {
                if let browser { browser.onboarding = .browsers } else { openWindow(id: "main") }
            }
            .disabled(browser?.isIncognito == true)
        }
        CommandGroup(replacing: .saveItem) {}
        CommandGroup(replacing: .printItem) {
            Button("Print…") { browser?.printActive() }.keyboardShortcut("p").disabled(browser?.activeTab == nil)
        }

        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy URL") { browser?.copyActiveURL() }
                .keyboardShortcut(key(.copyURL)).disabled(browser?.activeTab == nil)
        }
        // After, not replacing: the system Find, Spelling, Substitutions and Speech items stay for text fields.
        CommandGroup(after: .textEditing) {
            Button("Find in Page…") { browser?.findVisible = true }
                .keyboardShortcut(key(.find)).disabled(browser?.activeTab == nil)
        }

        CommandGroup(replacing: .sidebar) {
            Button(browser?.sidebarVisible == false ? "Show Sidebar" : "Hide Sidebar") { browser?.toggleSidebar() }
                .keyboardShortcut(key(.toggleSidebar)).disabled(browser == nil)
        }
        CommandGroup(before: .toolbar) {
            Button("Reload Page") { browser?.reload() }.keyboardShortcut(key(.reload)).disabled(browser?.activeTab == nil)
            Button("Reload Ignoring Cache and Cookies") { browser?.hardReload() }
                .keyboardShortcut(key(.hardReload)).disabled(browser?.activeTab == nil)
            Button("Back") { browser?.goBack() }.keyboardShortcut(key(.goBack)).disabled(browser?.activeTab == nil)
            Button("Forward") { browser?.goForward() }.keyboardShortcut(key(.goForward)).disabled(browser?.activeTab == nil)
            Divider()
            Button(browser?.split == nil ? "Add Split View" : "Close Split View") { browser?.toggleSplit() }
                .keyboardShortcut(key(.addSplitView)).disabled(browser?.activeTab == nil)
            Button("Customize Space…") {
                if let browser, let id = browser.spaceID { browser.spaceEditor = .init(spaceID: id) }
            }
            .disabled(browser == nil || browser?.isIncognito == true)
            Button("Archive") { openWindow(id: "archive") }.keyboardShortcut(key(.showArchive))
            Divider()
            PageAICommands(browser: browser)
            Button("Zoom In") { browser?.zoom(.in) }.keyboardShortcut("+").disabled(browser?.activeTab == nil)
            Button("Zoom Out") { browser?.zoom(.out) }.keyboardShortcut("-").disabled(browser?.activeTab == nil)
            Button("Actual Size") { browser?.zoom(.reset) }.keyboardShortcut("0").disabled(browser?.activeTab == nil)
            Divider()
        }

        CommandMenu("History") {
            Button("Show All History") { openWindow(id: "history") }.keyboardShortcut("y")
        }

        CommandMenu("Tabs") {
            Button(browser?.activeTab.map { model.isPinned($0) } == true ? "Unpin Tab" : "Pin Tab") { browser?.togglePinActive() }
                .keyboardShortcut(key(.pinTab)).disabled(browser?.activeTab == nil)
            Button("Next Tab") { browser?.cycleTab(by: 1) }.keyboardShortcut(key(.nextTab)).disabled(browser == nil)
            Button("Previous Tab") { browser?.cycleTab(by: -1) }.keyboardShortcut(key(.previousTab)).disabled(browser == nil)
            Divider()
            let favoriteCount = browser.map { model.favorites(profileID: $0.currentSpace?.profileID).count } ?? 0
            ForEach(1...9, id: \.self) { number in
                Button("Favorite \(number)") { browser?.selectFavorite(number) }
                    .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                    .disabled(number > favoriteCount)
            }
        }

        CommandMenu("Extensions") {
            Button("Manage Extensions…") { browser?.extensionSheet = .manage }.disabled(browser == nil || browser?.isIncognito == true)
            Divider()
            #if DIRECT_DISTRIBUTION
            Button("Install from Chrome Web Store…") { browser?.extensionSheet = .webStore() }
                .disabled(browser == nil || browser?.isIncognito == true)
            #endif
            Button("Load Unpacked…") { browser?.chooseExtension(folder: true) }.disabled(browser == nil || browser?.isIncognito == true)
            Button("Install from File…") { browser?.chooseExtension(folder: false) }
                .disabled(browser == nil || browser?.isIncognito == true)
        }

        CommandMenu("Spaces") {
            Button("Next Space") { browser?.shiftSpace(by: 1) }.keyboardShortcut(key(.nextSpace)).disabled(browser == nil)
            Button("Previous Space") { browser?.shiftSpace(by: -1) }.keyboardShortcut(key(.previousSpace)).disabled(browser == nil)
            Divider()
            ForEach(Array(model.sidebar.spaces.prefix(9).enumerated()), id: \.element.id) { index, space in
                Button("\(space.icon.map { $0 + " " } ?? "")\(space.title)") { browser?.selectSpace(index + 1) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .control)
                    .disabled(browser == nil)
            }
            Divider()
            Button("New Space") { browser?.newSpace() }.keyboardShortcut(key(.newSpace)).disabled(browser == nil)
        }
    }
}
