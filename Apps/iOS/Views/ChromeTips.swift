import SwiftUI
import TipKit

/// Swiping the toolbar (sideways on the bottom bar, up and down on the rail) pages through tabs; nothing on screen says so.
struct SwipeTabsTip: Tip {
    /// Today's tab count: the tip only makes sense with another tab to swipe to.
    @Parameter static var openTabs: Int = 0

    var title: Text { Text("Swipe the toolbar to switch tabs") }
    var image: Image? { Image(systemName: "hand.draw") }
    var rules: [Rule] { [#Rule(Self.$openTabs) { $0 >= 2 }] }
    var options: [any TipOption] { [MaxDisplayCount(1)] }
}
