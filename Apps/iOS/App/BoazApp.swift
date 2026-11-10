import BackgroundTasks
import CloudKit
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
        }
        .onChange(of: scenePhase) { _, phase in
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
