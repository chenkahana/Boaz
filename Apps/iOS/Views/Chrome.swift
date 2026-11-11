import BoazKit
import SwiftUI

/// Address and search entry: a panel in the page area, riding above the keyboard, with the field on top and
/// suggestions below it. Local matches (completion, open tabs, history) update on every keystroke; the search
/// engine's suggestions follow as they arrive (`SearchSuggestions`).
struct SearchPanel: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Preferences.tintWithSiteColorsKey) private var tintWithSiteColors = true
    @FocusState private var focused: Bool
    /// Off right after a deletion, so backspacing over a completion doesn't bring it straight back.
    @State private var completes = true

    var body: some View {
        // Matched once per keystroke, however many times the rows are laid out.
        let tabs = tabSuggestions
        BottomPanel(site: site, maxHeight: 0.85, onDismiss: dismiss) {
            VStack(spacing: 4) {
                field
                if expanded {
                    ScrollView { VStack(spacing: 0) { rows(tabs) } }
                        .scrollBounceBehavior(.basedOnSize)
                        .transition(.opacity)
                } else if !query.isEmpty {
                    ViewThatFits(in: .vertical) {
                        VStack(spacing: 0) { rows(tabs) }
                        ScrollView { VStack(spacing: 0) { rows(tabs) } }
                    }
                    .transition(.opacity)
                }
            }
            .padding(8)
        }
        .onAppear { focused = true }
        .onChange(of: model.searchText) { old, new in completes = new.count >= old.count }
        .animation(BottomPanelStyle.motion, value: expanded)
    }

    /// A query grows the panel to its full height on the first keystroke and keeps it there, so the field doesn't
    /// jump as suggestions come and go. Without engine suggestions (an address, Incognito, turned off) the panel
    /// fits its few local rows.
    private var expanded: Bool {
        !query.isEmpty && model.asksSearchEngine && !SearchSuggestions.looksLikeAddress(query)
    }

    private var query: String { model.searchText.trimmingCharacters(in: .whitespaces) }

    private var site: SiteColor? {
        guard tintWithSiteColors, let id = model.activeTabID else { return nil }
        return model.siteEdges[id]?.bottom
    }

    private var field: some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("Search or enter address", text: $model.searchText)
                .focused($focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .onSubmit(submit)
            if !model.searchText.isEmpty {
                Button { model.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").frame(minWidth: 28, minHeight: 28).contentShape(.rect)
                }
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("Clear Text")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        // Flat inside the glass panel: glass doesn't stack on glass.
        .background(Color.primary.opacity(0.07), in: .capsule)
    }

    @ViewBuilder private func rows(_ tabSuggestions: [SidebarItem]) -> some View {
        if let completion {
            Button(action: submit) {
                row {
                    Monogram(url: URL(string: "https://" + completion), tint: Theme.brand, size: 24)
                    let typed = typedPart(of: completion)
                    Text("\(typed)\(Text(completion.dropFirst(typed.count)).foregroundStyle(Theme.textSecondary))")
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "return").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                }
                .background(Theme.brand.opacity(0.12), in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.plain)
        } else {
            // What was typed, as typed: the list is never empty while there's text.
            Button(action: submit) {
                row {
                    let isAddress = SearchSuggestions.looksLikeAddress(query)
                    Image(systemName: isAddress ? "globe" : "magnifyingglass").frame(width: 24).foregroundStyle(Theme.textSecondary)
                    Text(query).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "return").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
        ForEach(tabSuggestions) { item in
            Button {
                model.searchTarget = nil
                model.activate(item)
            } label: {
                row {
                    Monogram(url: item.url, tint: Theme.brand, size: 24)
                    titleAndHost(item.title, item.url)
                    Spacer(minLength: 0)
                    if model.isOpen(item) {
                        Text("Switch to Tab").font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Image(systemName: "arrow.right.circle").foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
        }
        ForEach(historySuggestions(besides: tabSuggestions)) { visit in
            Button {
                // Ignored once the panel is closing, like Go (`submitSearch`).
                guard model.searchTarget != nil else { return }
                model.openNewTab(visit.url, title: visit.title)
            } label: {
                row {
                    Image(systemName: "clock.arrow.circlepath").frame(width: 24).foregroundStyle(Theme.textSecondary)
                    titleAndHost(visit.title, visit.url)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
        }
        ForEach(remoteSuggestions, id: \.self) { suggestion in
            HStack(spacing: 0) {
                Button { search(suggestion) } label: {
                    row {
                        Image(systemName: "magnifyingglass").frame(width: 24).foregroundStyle(Theme.textSecondary)
                        highlighted(suggestion).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                Button { model.searchText = suggestion + " " } label: {
                    Image(systemName: "arrow.up.left")
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fill In \(suggestion)")
            }
        }
    }

    private func row(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 12) { content() }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .contentShape(.rect)
    }

    private func titleAndHost(_ title: String?, _ url: URL?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title ?? url?.host() ?? "").lineLimit(1)
            Text(url?.host() ?? "").font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
        }
    }

    /// The typed part in regular weight, the rest of the suggestion bold.
    private func highlighted(_ suggestion: String) -> Text {
        let typed = model.searchText.drop(while: \.isWhitespace)
        guard let range = suggestion.range(of: typed, options: [.caseInsensitive, .anchored]) else {
            return Text(suggestion).fontWeight(.semibold)
        }
        return Text("\(Text(suggestion[range]))\(Text(suggestion[range.upperBound...]).fontWeight(.semibold))")
    }

    private func dismiss() { model.searchTarget = nil }

    private func search(_ suggestion: String) {
        model.searchText = suggestion
        model.submitSearch()
    }

    /// Host the typed text completes to, from history hosts first, then popular domains.
    private var completion: String? {
        guard completes else { return nil }
        return DomainCompletion.complete(model.searchText, historyHosts: model.historySuggestions.compactMap { $0.url.host() })
    }

    /// The part of the completion the user already typed (kept in their own spelling).
    private func typedPart(of completion: String) -> String {
        String(completion.prefix(DomainCompletion.query(model.searchText).count))
    }

    private func submit() {
        if let completion { model.searchText = completion }
        model.submitSearch()
    }

    /// The engine's suggestions, minus repeats of the row above them.
    private var remoteSuggestions: [String] {
        let typed = query.lowercased()
        return model.remoteSuggestions.suggestions.filter { $0 != completion && $0.lowercased() != typed }
    }

    /// History matches, minus addresses already open as a tab (those show as "switch to tab" above).
    private func historySuggestions(besides tabs: [SidebarItem]) -> [HistoryVisit] {
        let open = Set(tabs.compactMap(\.url))
        return model.historySuggestions.filter { !open.contains($0.url) }.prefix(3).map { $0 }
    }

    /// Open and pinned tabs whose title or address matches what's typed. Stops at the third match, and matches
    /// without lowercasing a copy of every title and address.
    private var tabSuggestions: [SidebarItem] {
        let query = query
        guard query.count > 1, model.searchTarget == .newTab, !model.isIncognito else { return [] }
        func contains(_ text: String?) -> Bool { text?.range(of: query, options: .caseInsensitive) != nil }
        // The phone's own tabs first, then the spaces' (pinned, favorites, open on a Mac), which open as copies.
        let spaceTabs = model.sidebar.items.lazy.filter { $0.kind == .tab && $0.parentID != nil }
        return Array((model.phoneTabs + spaceTabs)
            .filter { contains($0.title) || contains($0.url?.absoluteString) }
            .prefix(3))
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let toast: AppModel.Toast

    var body: some View {
        HStack(spacing: 14) {
            Text(toast.message).font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if toast.canUndo {
                Button("Undo") { model.undoClose() }.font(.callout.weight(.bold))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        // A capsule while the message fits one line; a rounded card once it wraps.
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        // The glass isn't hit-testable by itself: a tap that just misses Undo would reach what lies beneath,
        // the tab carousel, say, which closes on a tap between its cards.
        .contentShape(.rect(cornerRadius: 22))
        .frame(maxWidth: 360)
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
    }
}

/// Shows the site's real favicon once known, falling back to a tinted letter tile (no third-party
/// favicon service, so no browsing data leaves the device for an icon we can't resolve ourselves).
struct Monogram: View {
    let url: URL?
    let tint: Color
    let size: CGFloat

    var body: some View {
        FaviconTile(url: url, tint: tint, size: size)
    }
}

/// Springy press-down used on cards and tiles.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
