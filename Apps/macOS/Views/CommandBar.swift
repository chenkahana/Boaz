import AppKit
import BoazKit
import SwiftUI

/// Arc's command bar (⌘T new tab, ⌘L current tab, ⌃⇧= split): a floating field that searches open and pinned
/// tabs, the search engine's suggestions and history, or goes to an address / search.
struct CommandBar: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    #if BOAZ_CHROMIUM
    private static let backing = 0.92
    #else
    private static let backing = 0.0
    #endif
    let mode: BrowserState.CommandMode
    /// What the field shows: `query`, or the selected row's text while the arrow keys preview it.
    @State private var text = ""
    /// What was typed. Rows match this, so previewing a row doesn't change them.
    @State private var query = ""
    @State private var selection = 0
    /// The rows as they were when a preview began; answers landing meanwhile wait until the next edit or row 1.
    @State private var frozen: [Suggestion]?
    @State private var history: [HistoryVisit] = []
    /// Where the pointer was when it last picked a row. Rows appearing under a resting pointer report a hover too,
    /// so only a pointer that has moved since takes the selection, as in Spotlight.
    @State private var pointer = NSEvent.mouseLocation
    /// Settings › Sidebar text size, the Mac's text size for all of Boaz's chrome (`ChromeType`).
    @AppStorage(Preferences.sidebarTextSizeKey) private var textSize = SidebarStyle.defaultTextSize
    @FocusState private var focused: Bool

    enum Suggestion: Identifiable {
        case go(URL, label: String, isSearch: Bool)
        case tab(SidebarItem)
        case search(String)
        case history(HistoryVisit)

        var id: String {
            switch self {
            case .go(let url, _, _): "go:\(url.absoluteString)"
            case .tab(let tab): "tab:\(tab.id)"
            case .search(let suggestion): "search:\(suggestion)"
            case .history(let visit): "history:\(visit.id)"
            }
        }

        /// What the field shows while this row is selected: what was typed for the first row.
        func preview(typed: String) -> String {
            switch self {
            case .go: typed
            case .tab(let tab): tab.url?.absoluteString ?? typed
            case .search(let suggestion): suggestion
            case .history(let visit): visit.url.absoluteString
            }
        }
    }

    var body: some View {
        let tint = SpaceStyle(browser.currentSpace, scheme: scheme).tint
        let suggestions = frozen ?? self.suggestions
        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .onTapGesture { browser.commandMode = nil }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: ChromeType(base: textSize).scaled(17), weight: .medium))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    #if BOAZ_CHROMIUM
                    if let field = browser.chromiumAddressField {
                        ChromiumAddressField(field: field, text: fieldText, placeholder: placeholder,
                            moveUp: { select(selection - 1, in: suggestions) },
                            moveDown: { select(selection + 1, in: suggestions) },
                            submit: { run(suggestions.indices.contains(selection) ? suggestions[selection] : nil) },
                            cancel: { browser.commandMode = nil },
                            fontSize: ChromeType(base: textSize).commandFieldSize)
                    } else {
                    TextField(placeholder, text: fieldText)
                        .textFieldStyle(.plain)
                        .font(ChromeType(base: textSize).commandField)
                        .focused($focused)
                        .onSubmit { run(suggestions.indices.contains(selection) ? suggestions[selection] : nil) }
                        .onKeyPress(.downArrow) { select(selection + 1, in: suggestions); return .handled }
                        .onKeyPress(.upArrow) { select(selection - 1, in: suggestions); return .handled }
                        .onKeyPress(.escape) { browser.commandMode = nil; return .handled }
                        .accessibilityIdentifier("control.commandBar.field")
                    }
                    #else
                    TextField(placeholder, text: fieldText)
                        .textFieldStyle(.plain)
                        .font(ChromeType(base: textSize).commandField)
                        .focused($focused)
                        .onSubmit { run(suggestions.indices.contains(selection) ? suggestions[selection] : nil) }
                        .onKeyPress(.downArrow) { select(selection + 1, in: suggestions); return .handled }
                        .onKeyPress(.upArrow) { select(selection - 1, in: suggestions); return .handled }
                        .onKeyPress(.escape) { browser.commandMode = nil; return .handled }
                        .accessibilityIdentifier("control.commandBar.field")
                    #endif
                }
                .padding(.horizontal, 18).frame(height: 56)
                if !suggestions.isEmpty {
                    Divider().opacity(0.5)
                    VStack(spacing: 2) {
                        ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                            Button { run(suggestion) } label: {
                                SuggestionRow(suggestion: suggestion, selected: index == selection, tint: tint)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(index == selection ? .isSelected : [])
                            .onContinuousHover { phase in
                                guard case .active = phase, NSEvent.mouseLocation != pointer else { return }
                                pointer = NSEvent.mouseLocation
                                selection = index
                            }
                        }
                    }
                    .padding(6)
                }
            }
            .frame(width: 620)
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.panel))
            // Glass can't sample Chromium's page layer, so without a backing the page reads straight through; with
            // Reduce Transparency both builds show the same solid bar.
            .background(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
                .fill(.background.opacity(reduceTransparency ? 1 : Self.backing)))
            .overlay(RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(.white.opacity(0.35)))
            .shadow(color: tint.opacity(0.25), radius: 30)
            .shadow(color: .black.opacity(0.25), radius: 40, y: 20)
            .padding(.top, 110)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.commandBar")
        .onAppear {
            if mode == .currentTab { text = browser.activeURL?.absoluteString ?? ""; query = text }
            if !browser.isIncognito { browser.searchSuggestions.warm(Preferences.searchEngine) }
        }
        // While the web view is first responder, SwiftUI can report the field focused and the keys still go to the
        // page. So the web view gives the keyboard up, and the field is asked until AppKit's first responder is its
        // editor. Another field that had the keyboard (the find bar) doesn't count.
        .task {
            let otherField = fieldEditorOwner
            // A bar still closing while the next one opens leaves the keyboard and the held keys to that one.
            let session = browser.commandSession
            // Keys typed meanwhile were held for the field (`BrowserState.beginTypeAhead`).
            defer { if browser.commandSession == session { takeTypeAhead() } }
            for _ in 0..<10 {
                if browser.commandSession != session || fieldHasKeyboard(besides: otherField) { return }
                #if BOAZ_CHROMIUM
                if let field = browser.chromiumAddressField {
                    if field.window === browser.window, field.window?.makeFirstResponder(field) == true {
                        field.selectText(nil)
                    }
                    do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                    continue
                }
                #endif
                if focused {
                    // Asking again only takes effect once SwiftUI has seen the field unfocused.
                    focused = false
                } else {
                    browser.window?.makeFirstResponder(nil)
                    focused = true
                }
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
            if browser.commandSession == session, !fieldHasKeyboard(besides: otherField) {
                #if BOAZ_CHROMIUM
                if let field = browser.chromiumAddressField {
                    if field.window === browser.window { field.window?.makeFirstResponder(field) }
                } else { focused = true }
                #else
                focused = true
                #endif
            }
        }
        // History is looked up once typing pauses, off the main thread.
        .task(id: query) {
            let query = self.query.trimmingCharacters(in: .whitespaces)
            guard !browser.isIncognito, query.count >= 2 else { history = []; return }
            // Until the lookup lands, only rows that still match are offered.
            history.removeAll { !$0.matches(query) }
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            let found = await model.historySuggestions(query)
            if !Task.isCancelled { history = found }
        }
    }

    private func takeTypeAhead() {
        let (typed, clear, submit) = browser.endTypeAhead()
        // ⌘L's address is selected on focus, so typing (or Delete) replaces it.
        edit(mode == .currentTab && (clear || !typed.isEmpty) ? typed : text + typed)
        if clear || !typed.isEmpty { showTextInField() }
        // With nothing typed, Return only means something for ⌘L's address.
        if submit, !text.isEmpty { run(suggestions.first) }
    }

    /// Typing in the field: the text becomes the query, matched afresh from the first row.
    private var fieldText: Binding<String> {
        Binding(get: { text }, set: { edit($0) })
    }

    private func edit(_ newText: String) {
        guard newText != text else { return }
        text = newText
        query = newText
        selection = 0
        frozen = nil
        // Neither Incognito typing nor an address is sent to the search engine.
        if browser.isIncognito || SearchSuggestions.looksLikeAddress(newText) {
            browser.searchSuggestions.clear()
        } else {
            browser.searchSuggestions.update(newText, engine: Preferences.searchEngine)
        }
    }

    /// Selects a row and shows its text in the field, as Chrome's address bar does; the rows stay as they are.
    private func select(_ index: Int, in suggestions: [Suggestion]) {
        guard index != selection, suggestions.indices.contains(index) else { return }
        selection = index
        frozen = index == 0 ? nil : frozen ?? suggestions
        text = suggestions[index].preview(typed: query)
        showTextInField()
    }

    /// Puts `text` in the Chromium field's editor with the caret at the end; the binding alone would keep the old
    /// caret position.
    private func showTextInField() {
        #if BOAZ_CHROMIUM
        if let field = browser.chromiumAddressField,
           let editor = field.currentEditor() as? NSTextView, !editor.hasMarkedText() {
            editor.string = text
            field.stringValue = text
            editor.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        #endif
    }

    /// Whether typing reaches the field: AppKit's first responder is a text field's editor, not the web view, and
    /// not `otherField`'s.
    private func fieldHasKeyboard(besides otherField: NSTextField?) -> Bool {
        #if BOAZ_CHROMIUM
        if let field = browser.chromiumAddressField { return fieldEditorOwner === field }
        #endif
        guard focused, let owner = fieldEditorOwner else { return false }
        return owner !== otherField
    }

    /// The text field whose editor is AppKit's first responder.
    private var fieldEditorOwner: NSTextField? {
        guard let editor = browser.window?.firstResponder as? NSTextView, editor.isFieldEditor else { return nil }
        return editor.delegate as? NSTextField
    }

    private var icon: String {
        switch mode {
        case .newTab: browser.isIncognito ? "eyeglasses" : "magnifyingglass"
        case .currentTab: "arrow.turn.down.right"
        case .split: "rectangle.split.2x1"
        }
    }

    private var placeholder: String {
        switch mode {
        case .newTab: "Search or enter address"
        case .currentTab: "Go to…"
        case .split: "Open in split view…"
        }
    }

    private var suggestions: [Suggestion] {
        let query = self.query.trimmingCharacters(in: .whitespaces)
        var result: [Suggestion] = []
        let engine = Preferences.searchEngine
        if let url = SearchInput.url(for: query, searchTemplate: engine.template, schemes: SearchInput.typedSchemes) {
            let isSearch = url.absoluteString.hasPrefix(engine.template.replacingOccurrences(of: "%@", with: ""))
            result.append(.go(url, label: isSearch ? "Search \(engine.name) for “\(query)”" : url.absoluteString,
                              isSearch: isSearch))
        }
        // Skip tab matching while the field still holds the current page's own URL (⌘L).
        let currentURL = browser.activeURL?.absoluteString
        guard query != currentURL else { return result }
        let tabs = openTabs.filter { tab in
            tab.id != browser.activeTabID && (query.isEmpty
                || (tab.title ?? "").localizedCaseInsensitiveContains(query)
                || (tab.url?.absoluteString ?? "").localizedCaseInsensitiveContains(query))
        }
        result += tabs.prefix(query.isEmpty ? 6 : 4).map(Suggestion.tab)
        let typed = query.lowercased()
        result += browser.searchSuggestions.suggestions.filter { $0.lowercased() != typed }.prefix(4)
            .map(Suggestion.search)
        let tabURLs = Set(openTabs.compactMap(\.url))
        result += history.filter { !tabURLs.contains($0.url) }.prefix(3).map(Suggestion.history)
        return result
    }

    private var openTabs: [SidebarItem] {
        if browser.isIncognito { return browser.incognitoTabs }
        guard let space = browser.currentSpace else { return [] }
        return model.todayTabs(in: space) + model.allPinnedTabs(in: space) + model.favorites(profileID: space.profileID)
    }

    private func run(_ suggestion: Suggestion?) {
        guard let suggestion else { return }
        switch suggestion {
        case .go(let url, _, _): open(url)
        case .search(let suggestion):
            // Like iOS, a suggestion opens as if typed: a suggested address goes to the site.
            guard let url = SearchInput.url(for: suggestion, searchTemplate: Preferences.searchEngine.template,
                                            schemes: SearchInput.typedSchemes) else { return }
            open(url)
        case .history(let visit): open(visit.url)
        case .tab(let tab):
            if mode == .split { browser.openInSplit(tab) } else { browser.activate(tab) }
        }
        browser.commandMode = nil
    }

    private func open(_ url: URL) {
        switch mode {
        case .newTab: browser.openTab(url, below: browser.newTabAnchor)
        case .currentTab: browser.load(url)
        case .split: browser.openInSplit(url)
        }
    }
}

private struct SuggestionRow: View {
    @AppStorage(Preferences.sidebarTextSizeKey) private var textSize = SidebarStyle.defaultTextSize
    let suggestion: CommandBar.Suggestion
    let selected: Bool
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            switch suggestion {
            case .go(let url, let label, let isSearch):
                Image(systemName: isSearch ? "magnifyingglass" : "globe").frame(width: 20)
                Text(label).lineLimit(1)
                Spacer()
                Text(isSearch ? "Search" : url.host() ?? "").font(.caption).foregroundStyle(.secondary)
            case .tab(let tab):
                SiteMonogram(url: tab.url, tint: tint, size: 20)
                Text(tab.title ?? tab.url?.host() ?? "New Tab").lineLimit(1)
                Spacer()
                Text("Switch to Tab").font(.caption).foregroundStyle(.secondary)
            case .search(let suggestion):
                Image(systemName: "magnifyingglass").frame(width: 20)
                Text(suggestion).lineLimit(1)
                Spacer()
                Text("Search").font(.caption).foregroundStyle(.secondary)
            case .history(let visit):
                Image(systemName: "clock").frame(width: 20)
                Text(visit.title ?? visit.url.absoluteString).lineLimit(1)
                Spacer()
                // Safari's word: a history row is told apart from a typed address, which also shows a host.
                Text("History · \(visit.url.host() ?? "")").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .font(ChromeType(base: textSize).commandRow)
        .padding(.horizontal, 12).frame(height: 36)
        .background(selected ? tint.opacity(0.22) : .clear, in: .rect(cornerRadius: Radius.row, style: .continuous))
        .contentShape(Rectangle())
    }
}
