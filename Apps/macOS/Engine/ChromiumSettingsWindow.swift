#if BOAZ_CHROMIUM
import AppKit
import SwiftUI

/// Boaz ▸ Settings in the DMG: a standard Mac settings window with one toolbar tab per pane, titled after the pane
/// and sized to it.
final class ChromiumSettingsWindow: NSWindowController, NSWindowDelegate {
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
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// The tab controller resizes the window to each pane, growing it downward; keep it on screen.
    func windowDidResize(_ notification: Notification) {
        if let window { PaneTabs.keepOnScreen(window) }
    }

    override func showWindow(_ sender: Any?) {
        if let window { PaneTabs.keepOnScreen(window) }
        super.showWindow(sender)
    }
}

private final class PaneTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animate: true)
    }

    /// Keeps the window's top edge where it is and fits the content to the selected pane, which caps its own height
    /// to the screen and scrolls past it.
    func fitWindow(animate: Bool) {
        guard let window = view.window, tabViewItems.indices.contains(selectedTabViewItemIndex),
              let size = tabViewItems[selectedTabViewItemIndex].viewController?.preferredContentSize,
              size.width > 0, size.height > 0 else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        var frame = window.frameRect(forContentRect: NSRect(x: content.minX, y: content.maxY - size.height,
                                                            width: size.width, height: size.height))
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
        }
        window.setFrame(frame, display: true, animate: animate && window.isVisible)
    }

    /// Moves the window up or across, never resizing it, so every edge is on its screen.
    static func keepOnScreen(_ window: NSWindow) {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return }
        var origin = window.frame.origin
        origin.y = min(max(origin.y, visible.minY), visible.maxY - window.frame.height)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - window.frame.width)
        if origin != window.frame.origin { window.setFrameOrigin(origin) }
    }
}
#endif
