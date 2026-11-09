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

/// iPhone Duo: the rail can be swiped toward the screen edge to get it out of the way.
struct TuckRailTip: Tip {
    var title: Text { Text("Swipe the rail toward the edge to hide it") }
    var image: Image? { Image(systemName: "sidebar.trailing") }
    var options: [any TipOption] { [MaxDisplayCount(1)] }
}
