import BackgroundTasks
import CloudKit
import CoreSpotlight
import BoazKit
import SwiftUI
import TipKit
import UIKit

@main
struct BoazApp: App {
    @UIApplicationDelegateAdaptor(BoazAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    private var model: AppModel { delegate.model }

    /// Background refresh that pulls other devices' changes.
    static let syncTaskID = "com.chenkahana.boaz.sync"

    init() {
        // Gesture tips: each shows once, and at most one a day, so they stay out of the way.
        try? Tips.configure([.displayFrequency(.daily)])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
                .onOpenURL { url in DeepLink.handle(url, model: model) }
                // A pinned tab or favorite picked in Spotlight opens as a new tab.
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
                          let url = model.sidebar.items.first(where: { $0.id == id })?.url else { return }
                    DeepLink.handle(url, model: model)
                }
        }
        // With a hardware keyboard: the Mac's shortcuts for a new tab and the address.
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Tab") { model.beginSearch(.newTab) }.keyboardShortcut("t")
                Button("Open Location") { model.beginSearch(.currentTab) }.keyboardShortcut("l")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // On the way out the page is still drawn; once in the background it can't render a preview.
            if phase == .inactive { model.captureActiveSnapshot() }
            // The database lives in the App Group container: never hold a lock on it while suspended.
            if phase == .background {
                Self.scheduleSyncRefresh()
                model.suspendDatabase()
            } else {
                BoazStore.resumeDatabases()
            }
        }
        .backgroundTask(.appRefresh(Self.syncTaskID)) {
            await Self.scheduleSyncRefresh()
            await model.backgroundSync()
        }
    }

    static func scheduleSyncRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: syncTaskID)
        request.earliestBeginDate = .now.addingTimeInterval(15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

/// Owns the app model so iCloud change pushes can reach sync.
final class BoazAppDelegate: NSObject, UIApplicationDelegate {
    let model = AppModel()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else { return .noData }
        await model.backgroundSync()
        return .newData
    }
}
