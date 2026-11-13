#if BOAZ_CHROMIUM
import AppKit
import SwiftUI

@MainActor
struct ChromiumHistoryButton: NSViewRepresentable {
    let adapter: ChromiumEnginePageAdapter
    let forward: Bool
    let hint: String
    var onError: (String) -> Void = { _ in }

    final class Coordinator: NSObject, NSMenuDelegate {
        var control: ChromiumHistoryButton
        private var menuAdapter: ChromiumEnginePageAdapter?
        init(_ control: ChromiumHistoryButton) { self.control = control }

        @objc func clicked(_ button: NSButton) {
            do {
                if control.forward { try control.adapter.goForward() } else { try control.adapter.goBack() }
            } catch { control.onError("Navigation failed: \(error.localizedDescription)") }
        }
        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            menuAdapter = control.adapter
            do {
                let entries = try control.adapter.historySnapshot()
                    .filter { control.forward ? $0.offset > 0 : $0.offset < 0 }
                    .sorted { abs(Int64($0.offset)) < abs(Int64($1.offset)) }
                for entry in entries {
                    let item = NSMenuItem(title: entry.title.isEmpty ? entry.url : entry.title,
                                          action: #selector(selectEntry(_:)), keyEquivalent: "")
                    item.target = self
                    item.representedObject = NSNumber(value: entry.id)
                    item.toolTip = entry.url
                    menu.addItem(item)
                }
                if entries.isEmpty {
                    let empty = NSMenuItem(title: "No history", action: nil, keyEquivalent: "")
                    empty.isEnabled = false
                    menu.addItem(empty)
                }
            } catch {
                control.onError("Could not read page history: \(error.localizedDescription)")
                let item = NSMenuItem(title: "History unavailable", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }
        @objc func selectEntry(_ item: NSMenuItem) {
            guard let id = item.representedObject as? NSNumber, let adapter = menuAdapter else { return }
            let entryID = id.int32Value
            let report = control.onError
            DispatchQueue.main.async {
                do { try adapter.gotoStableEntry(entryID) }
                catch { report("Could not open history entry: \(error.localizedDescription)") }
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        button.isBordered = false
        let menu = NSMenu(title: "Page history")
        menu.autoenablesItems = false
        menu.delegate = context.coordinator
        button.menu = menu
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.control = self
        button.image = NSImage(systemSymbolName: forward ? "chevron.right" : "chevron.left",
                               accessibilityDescription: hint)
        button.toolTip = hint + " — Control-click for history"
        button.setAccessibilityLabel(hint)
        button.isEnabled = adapter.state.lifecycle == .active &&
            (forward ? adapter.state.canGoForward : adapter.state.canGoBack)
        button.setFrameSize(NSSize(width: 26, height: 26))
    }
    static func dismantleNSView(_ button: NSButton, coordinator: Coordinator) {
        button.target = nil
        button.menu?.delegate = nil
        button.menu = nil
    }
}
#endif
