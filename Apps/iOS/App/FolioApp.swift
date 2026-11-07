import SwiftUI

@main
struct FolioApp: App {
    @State private var model = BrowserModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.brand)
        }
    }
}
