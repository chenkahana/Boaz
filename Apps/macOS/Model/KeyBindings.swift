import AppKit
import SwiftUI

/// Rebindable browser commands. Defaults follow Arc; `arcIDs` are the identifiers Arc uses for the same
/// action (`arcKeyBindingID` in Arc's main menu), so overrides from `StorableKeyBindings.json` map across.
enum BrowserCommand: String, CaseIterable {
    case newTab, openLocation, closeTab, reopenClosedTab, pinTab, toggleSidebar, copyURL
    case reload, goBack, goForward, find, nextTab, previousTab, nextSpace, previousSpace
    case addSplitView, newWindow, newIncognitoWindow, newLittleWindow, showArchive, newSpace

    var arcIDs: [String] {
        switch self {
        case .newTab: ["newTab"]
        case .openLocation: ["openLocation", "addressBar"]
        case .closeTab: ["closeCurrentTab", "closeTab", "archiveTab"]
        case .reopenClosedTab: ["reopenClosedTab", "reopenLastClosedTab"]
        case .pinTab: ["pinTab"]
        case .toggleSidebar: ["showSidebar", "toggleSidebar"]
        case .copyURL: ["copyCurrentURL"]
        case .reload: ["reloadPage"]
        case .goBack: ["goBack"]
        case .goForward: ["goForward"]
        case .find: ["find"]
        case .nextTab: ["cycleTabForward", "cycleNextTab", "selectNextTab", "nextTab"]
        case .previousTab: ["cycleTabBackward", "cyclePreviousTab", "selectPreviousTab", "previousTab"]
        case .nextSpace: ["nextSpace", "focusNextSpace"]
        case .previousSpace: ["previousSpace", "focusPreviousSpace"]
        case .addSplitView: ["addSplitView"]
        case .newWindow: ["newWindow"]
        case .newIncognitoWindow: ["newIncognitoWindow"]
        case .newLittleWindow: ["newLittleBrowserWindow", "littleBrowser", "showLittleArc"]
        case .showArchive: ["showArchive", "archive", "openLibrary"]
        case .newSpace: ["newSpace"]
        }
    }

    var defaultShortcut: KeyboardShortcut? {
        switch self {
        case .newTab: KeyboardShortcut("t")
        case .openLocation: KeyboardShortcut("l")
        case .closeTab: KeyboardShortcut("w")
        case .reopenClosedTab: KeyboardShortcut("t", modifiers: [.command, .shift])
        case .pinTab: KeyboardShortcut("d")
        case .toggleSidebar: KeyboardShortcut("s")
        case .copyURL: KeyboardShortcut("c", modifiers: [.command, .shift])
        case .reload: KeyboardShortcut("r")
        case .goBack: KeyboardShortcut("[")
        case .goForward: KeyboardShortcut("]")
        case .find: KeyboardShortcut("f")
        case .nextTab: KeyboardShortcut(.tab, modifiers: .control)
        case .previousTab: KeyboardShortcut(.tab, modifiers: [.control, .shift])
        case .nextSpace: KeyboardShortcut(.rightArrow, modifiers: [.command, .option])
        case .previousSpace: KeyboardShortcut(.leftArrow, modifiers: [.command, .option])
        case .addSplitView: KeyboardShortcut("=", modifiers: [.control, .shift])
        case .newWindow: KeyboardShortcut("n")
        case .newIncognitoWindow: KeyboardShortcut("n", modifiers: [.command, .shift])
        case .newLittleWindow: KeyboardShortcut("n", modifiers: [.command, .option])
        case .showArchive: KeyboardShortcut("a", modifiers: [.command, .option])
        case .newSpace: nil
        }
    }

    static func matching(arcID raw: String) -> BrowserCommand? {
        var id = raw
        if id.hasSuffix("MenuItem") { id.removeLast("MenuItem".count) }
        return allCases.first { command in command.arcIDs.contains { $0.caseInsensitiveCompare(id) == .orderedSame } }
    }
}

/// A shortcut in storable form: a key name or character plus `NSEvent.ModifierFlags` raw bits. Empty key = unbound.
struct StoredShortcut: Codable, Hashable {
    var key: String
    var modifiers: UInt

    var keyboardShortcut: KeyboardShortcut? {
        guard let equivalent = Self.keyEquivalent(key) else { return nil }
        let flags = NSEvent.ModifierFlags(rawValue: modifiers)
        var mods: EventModifiers = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        return KeyboardShortcut(equivalent, modifiers: mods)
    }

    static func keyEquivalent(_ key: String) -> KeyEquivalent? {
        switch key {
        case "": nil
        case "leftArrow", "\u{F702}": .leftArrow
        case "rightArrow", "\u{F703}": .rightArrow
        case "upArrow", "\u{F700}": .upArrow
        case "downArrow", "\u{F701}": .downArrow
        case "tab", "\t": .tab
        case "return", "\r", "\n": .return
        case "escape", "\u{1B}": .escape
        case "space", " ": .space
        case "delete", "\u{7F}", "\u{8}": .delete
        default: key.count == 1 ? KeyEquivalent(Character(key.lowercased())) : nil
        }
    }
}

extension KeyboardShortcut {
    /// Menu-style glyphs ("⇧⌘T"), so hints follow rebound shortcuts.
    var displayString: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        switch key {
        case .leftArrow: text += "←"
        case .rightArrow: text += "→"
        case .upArrow: text += "↑"
        case .downArrow: text += "↓"
        case .tab: text += "⇥"
        case .return: text += "↩"
        case .escape: text += "⎋"
        case .space: text += "Space"
        case .delete: text += "⌫"
        default: text += String(key.character).uppercased()
        }
        return text
    }
}

extension KeyBindings {
    /// "Title (⌘X)" for tooltips, using the live binding.
    func hint(_ title: String, _ command: BrowserCommand) -> String {
        shortcut(command).map { "\(title) (\($0.displayString))" } ?? title
    }
}

/// Live shortcut table: Arc defaults plus user overrides (persisted, and importable from Arc).
@Observable
final class KeyBindings {
    private static let defaultsKey = "keyBindingOverrides"
    private(set) var overrides: [String: StoredShortcut] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode([String: StoredShortcut].self, from: data) {
            overrides = saved
        }
    }

    func shortcut(_ command: BrowserCommand) -> KeyboardShortcut? {
        if let override = overrides[command.rawValue] { return override.keyboardShortcut }
        return command.defaultShortcut
    }

    func resetToDefaults() {
        overrides = [:]
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    /// Reads Arc's `StorableKeyBindings.json` (`{"version":1,"userOverrides":[…]}`) and applies every override
    /// that maps to a Folio command. Returns how many were applied. Works with a security-scoped URL.
    @discardableResult
    func applyArcKeyBindings(fileURL: URL) throws -> Int {
        let scoped = fileURL.startAccessingSecurityScopedResource()
        defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
        let parsed = try Self.parseArc(try Data(contentsOf: fileURL))
        for (command, shortcut) in parsed { overrides[command.rawValue] = shortcut }
        if let data = try? JSONEncoder().encode(overrides) { UserDefaults.standard.set(data, forKey: Self.defaultsKey) }
        return parsed.count
    }

    // MARK: Arc format

    /// Arc's override list is Swift-Codable output whose element shape isn't documented, and the sample on this
    /// machine is empty. Accept the plausible encodings: an array of `{id, shortcut}` objects, a Swift
    /// non-String-keyed dictionary (flat `[key, value, key, value]` array) or a JSON object keyed by action.
    /// A `null` shortcut unbinds the command.
    static func parseArc(_ data: Data) throws -> [BrowserCommand: StoredShortcut] {
        let root = try JSONSerialization.jsonObject(with: data)
        let overrides = (root as? [String: Any])?["userOverrides"] ?? root
        var pairs: [(Any, Any)] = []
        if let dict = overrides as? [String: Any] {
            pairs = dict.map { ($0.key, $0.value) }
        } else if let array = overrides as? [Any] {
            let objects = array.compactMap { $0 as? [String: Any] }
            if objects.count == array.count, objects.allSatisfy({ identifier(inObject: $0) != nil }) {
                pairs = objects.map { object in (identifier(inObject: object)!, shortcutPayload(inObject: object)) }
            } else if array.count.isMultiple(of: 2) {
                pairs = stride(from: 0, to: array.count, by: 2).map { (array[$0], array[$0 + 1]) }
            }
        }
        var result: [BrowserCommand: StoredShortcut] = [:]
        for (rawID, payload) in pairs {
            guard let id = identifier(rawID), let command = BrowserCommand.matching(arcID: id),
                  let shortcut = shortcut(payload) else { continue }
            result[command] = shortcut
        }
        return result
    }

    private static let idKeys = ["id", "action", "actionID", "keyBindingID", "bindingID", "identifier", "command", "name"]
    private static let shortcutKeys = ["shortcut", "keyBinding", "binding", "keyEquivalent", "value"]

    private static func identifier(_ value: Any) -> String? {
        if let string = value as? String { return string }
        if let object = value as? [String: Any] {
            for key in ["rawValue", "_0", "id"] { if let string = object[key] as? String { return string } }
        }
        return nil
    }

    private static func identifier(inObject object: [String: Any]) -> String? {
        for key in idKeys { if let value = object[key], let id = identifier(value) { return id } }
        return nil
    }

    private static func shortcutPayload(inObject object: [String: Any]) -> Any {
        for key in shortcutKeys where object.keys.contains(key) { return object[key] ?? NSNull() }
        return object
    }

    private static func shortcut(_ payload: Any) -> StoredShortcut? {
        if payload is NSNull { return StoredShortcut(key: "", modifiers: 0) }
        guard var object = payload as? [String: Any] else { return nil }
        for key in ["shortcut", "_0", "keyBinding"] {
            if let nested = object[key] as? [String: Any] { object = nested }
        }
        var key: String?
        for name in ["charactersIgnoringModifiers", "characters", "keyEquivalent", "key"] {
            if let string = object[name] as? String, !string.isEmpty { key = string; break }
        }
        if key == nil, let code = object["keyCode"] as? Int { key = keyName(forKeyCode: code) }
        guard let key, StoredShortcut.keyEquivalent(key) != nil else { return nil }
        var modifiers: UInt = 0
        for name in ["modifierFlags", "modifiers", "keyEquivalentModifierMask", "modifierMask"] {
            if let raw = object[name] as? Int { modifiers = UInt(raw); break }
            if let names = object[name] as? [String] {
                var flags = NSEvent.ModifierFlags()
                for flag in names.map({ $0.lowercased() }) {
                    if flag.contains("command") || flag == "cmd" { flags.insert(.command) }
                    if flag.contains("shift") { flags.insert(.shift) }
                    if flag.contains("option") || flag.contains("alt") { flags.insert(.option) }
                    if flag.contains("control") || flag == "ctrl" { flags.insert(.control) }
                }
                modifiers = UInt(flags.rawValue)
                break
            }
        }
        return StoredShortcut(key: key, modifiers: modifiers)
    }

    /// ANSI virtual key codes for the keys a browser shortcut plausibly uses.
    private static func keyName(forKeyCode code: Int) -> String? {
        let table: [Int: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b", 12: "q",
            13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
            24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i",
            35: "p", 36: "return", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "n", 46: "m", 47: ".", 48: "tab", 49: "space", 50: "`", 51: "delete", 53: "escape",
            123: "leftArrow", 124: "rightArrow", 125: "downArrow", 126: "upArrow",
        ]
        return table[code]
    }
}
