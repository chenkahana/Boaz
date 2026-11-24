import SwiftUI
import TipKit

/// Swiping the toolbar (sideways on the bottom bar, up and down on the rail) pages through tabs; nothing on screen says so.
struct SwipeTabsTip: Tip {
    /// Today's tab count: the tip only makes sense with another tab to swipe to.
    @Parameter static var openTabs: Int = 0
    /// The page under the toolbar has finished loading, so the tip never covers a page that's still arriving.
    @Parameter static var pageLoaded: Bool = false

    var title: Text { Text("Swipe the toolbar to switch tabs") }
    var image: Image? { Image(systemName: "hand.draw") }
    var rules: [Rule] { [#Rule(Self.$openTabs) { $0 >= 2 }, #Rule(Self.$pageLoaded) { $0 }] }
    var options: [any TipOption] { [MaxDisplayCount(1)] }
}
