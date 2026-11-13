#if BOAZ_CHROMIUM
import AppKit
import SwiftUI

/// Hosts the field retained by BrowserState and observed by NativeLocationBar.
struct ChromiumAddressField: NSViewRepresentable {
    let field: NSTextField
    @Binding var text: String
    let placeholder: String
    let moveUp: () -> Void
    let moveDown: () -> Void
    let submit: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        field.isBordered = false
        field.drawsBackground = false
        field.isEditable = true
        field.isSelectable = true
        field.font = .systemFont(ofSize: 19)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        updateNSView(field, context: context)
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        guard field.delegate === context.coordinator else { return }
        let editor = field.currentEditor() as? NSTextView
        guard editor?.hasMarkedText() != true else { return }
        guard field.stringValue != text else { return }
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        if let editor {
            let selection = editor.selectedRange()
            editor.string = text
            let length = (text as NSString).length
            let start = min(selection.location, length)
            editor.setSelectedRange(NSRange(location: start, length: min(selection.length, length - start)))
        }
        field.stringValue = text
    }
    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        if field.delegate === coordinator { field.delegate = nil }
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ChromiumAddressField
        var updating = false
        init(_ parent: ChromiumAddressField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard !updating, let field = notification.object as? NSTextField,
                  field === parent.field else { return }
            if parent.text != field.stringValue { parent.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch commandSelector {
            case #selector(NSResponder.moveUp(_:)): parent.moveUp()
            case #selector(NSResponder.moveDown(_:)): parent.moveDown()
            case #selector(NSResponder.insertNewline(_:)): parent.submit()
            case #selector(NSResponder.cancelOperation(_:)): parent.cancel()
            default: return false
            }
            return true
        }
    }
}
#endif
