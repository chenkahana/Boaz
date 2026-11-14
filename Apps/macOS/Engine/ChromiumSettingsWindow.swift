#if BOAZ_CHROMIUM
import AppKit
import SwiftUI

/// Boaz ▸ Settings in the DMG: a standard Mac settings window with one toolbar tab per pane, titled after the pane
/// and sized to it.
final class ChromiumSettingsWindow: NSWindowController {
    init(model: MacModel) {
        let tabs = PaneTabs()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true
        for pane in MacSettingsPane.allCases {
            let host = NSHostingController(rootView: MacSettingsPaneView(pane: pane).environment(model))
            host.sizingOptions = .preferredContentSize
            host.title = pane.title
            let item = NSTabViewItem(viewController: host)
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: pane.title)
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
        tabs.fitWindow(animate: false)
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

private final class PaneTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animate: true)
    }

    /// Keeps the window's top edge where it is and fits the content to the selected pane. A taller pane scrolls.
    func fitWindow(animate: Bool) {
        guard let window = view.window, tabViewItems.indices.contains(selectedTabViewItemIndex),
              var size = tabViewItems[selectedTabViewItemIndex].viewController?.preferredContentSize,
              size.width > 0, size.height > 0 else { return }
        size.height = min(size.height, 640)
        let content = window.contentRect(forFrameRect: window.frame)
        let frame = window.frameRect(forContentRect: NSRect(x: content.minX, y: content.maxY - size.height,
                                                            width: size.width, height: size.height))
        window.setFrame(frame, display: true, animate: animate && window.isVisible)
    }
}
#endif
