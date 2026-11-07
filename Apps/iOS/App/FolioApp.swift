import SwiftUI

@main
struct FolioApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.brand)
                .task { await model.start() }
        }
    }
}
