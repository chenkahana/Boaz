import AppKit
import BoazKit
import SwiftUI

/// Arc's command bar (⌘T new tab, ⌘L current tab, ⌃⇧= split): a floating field that searches open and pinned
/// tabs and history, or goes to an address / search.
struct CommandBar: View {
    @Environment(MacModel.self) private var model
    @Environment(BrowserState.self) private var browser
    @Environment(\.colorScheme) private var scheme
    let mode: BrowserState.CommandMode
    @State private var text = ""
    @State private var selection = 0
    @State private var history: [HistoryVisit] = []
    @FocusState private var focused: Bool

    enum Suggestion: Identifiable {
        case go(URL, label: String, isSearch: Bool)
        case tab(SidebarItem)
        case history(HistoryVisit)

        var id: String {
            switch self {
            case .go(let url, _, _): "go:\(url.absoluteString)"
            case .tab(let tab): "tab:\(tab.id)"
            case .history(let visit): "history:\(visit.id)"
            }
        }
    }

    var body: some View {
        let tint = SpaceStyle(browser.currentSpace, scheme: scheme).tint
        let suggestions = self.suggestions
        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .onTapGesture { browser.commandMode = nil }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: icon).font(.system(size: 17, weight: .medium)).foregroundStyle(tint)
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 19))
                        .focused($focused)
                        .onSubmit { run(suggestions.indices.contains(selection) ? suggestions[selection] : nil) }
                        .onKeyPress(.downArrow) { selection = min(selection + 1, max(suggestions.count - 1, 0)); return .handled }
                        .onKeyPress(.upArrow) { selection = max(selection - 1, 0); return .handled }
                        .onKeyPress(.escape) { browser.commandMode = nil; return .handled }
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
                            .onHover { if $0 { selection = index } }
                        }
                    }
                    .padding(6)
                }
            }
            .frame(width: 620)
            .glassEffect(.regular, in: .rect(cornerRadius: MacRadius.panel))
            .overlay(RoundedRectangle(cornerRadius: MacRadius.panel, style: .continuous).strokeBorder(.white.opacity(0.35)))
            .shadow(color: tint.opacity(0.25), radius: 30)
            .shadow(color: .black.opacity(0.25), radius: 40, y: 20)
            .padding(.top, 110)
        }
        .onAppear {
            if mode == .currentTab { text = browser.activeURL?.absoluteString ?? "" }
        }
        // While the web view is first responder, SwiftUI can report the field focused and the keys still go to the
        // page. So the web view gives the keyboard up, and the field is asked until AppKit's first responder is its
        // editor.
        .task {
            for _ in 0..<10 {
                if fieldHasKeyboard { return }
                if focused {
                    // Asking again only takes effect once SwiftUI has seen the field unfocused.
                    focused = false
                } else {
                    browser.window?.makeFirstResponder(nil)
                    focused = true
                }
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
        }
        .onChange(of: text) { selection = 0 }
        // History is looked up once typing pauses, off the main thread.
        .task(id: text) {
            let query = text.trimmingCharacters(in: .whitespaces)
            guard !browser.isIncognito, query.count >= 2 else { history = []; return }
            // Until the lookup lands, only rows that still match are offered.
            history.removeAll { !$0.matches(query) }
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            let found = await model.historySuggestions(query)
            if !Task.isCancelled { history = found }
        }
    }

    /// Whether typing reaches the field: AppKit's first responder is a text field's editor, not the web view.
    private var fieldHasKeyboard: Bool {
        focused && (browser.window?.firstResponder as? NSTextView)?.isFieldEditor == true
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
        let query = text.trimmingCharacters(in: .whitespaces)
        var result: [Suggestion] = []
        let engine = Preferences.searchEngine
        if let url = SearchInput.url(for: query, searchTemplate: engine.template) {
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
        result += tabs.prefix(query.isEmpty ? 6 : 5).map(Suggestion.tab)
        let tabURLs = Set(openTabs.compactMap(\.url))
        result += history.filter { !tabURLs.contains($0.url) }.prefix(5).map(Suggestion.history)
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
        case .history(let visit): open(visit.url)
        case .tab(let tab):
            if mode == .split { browser.openInSplit(tab) } else { browser.activate(tab) }
        }
        browser.commandMode = nil
    }

    private func open(_ url: URL) {
        switch mode {
        case .newTab: browser.openTab(url)
        case .currentTab: browser.load(url)
        case .split: browser.openInSplit(url)
        }
    }
}

private struct SuggestionRow: View {
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
            case .history(let visit):
                Image(systemName: "clock").frame(width: 20)
                Text(visit.title ?? visit.url.absoluteString).lineLimit(1)
                Spacer()
                Text(visit.url.host() ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 12).frame(height: 36)
        .background(selected ? tint.opacity(0.22) : .clear, in: .rect(cornerRadius: MacRadius.row, style: .continuous))
        .contentShape(Rectangle())
    }
}
