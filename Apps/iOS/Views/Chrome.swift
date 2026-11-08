import FolioKit
import SwiftUI

/// Address/search entry that slides up over whatever is on screen.
struct SearchOverlay: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool
    /// Off right after a deletion, so backspacing over a completion doesn't bring it straight back.
    @State private var completes = true

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.25).ignoresSafeArea()
                .onTapGesture { model.searchTarget = nil }
            VStack(spacing: 8) {
                ForEach(historySuggestions) { visit in
                    Button { model.openNewTab(visit.url, title: visit.title) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath").frame(width: 24).foregroundStyle(.secondary)
                            VStack(alignment: .leading) {
                                Text(visit.title ?? visit.url.host() ?? "").lineLimit(1)
                                Text(visit.url.host() ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(suggestions) { item in
                    Button {
                        model.searchTarget = nil
                        model.activate(item)
                    } label: {
                        HStack(spacing: 10) {
                            Monogram(url: item.url, tint: Theme.brand, size: 24)
                            VStack(alignment: .leading) {
                                Text(item.title ?? "").lineLimit(1)
                                Text(item.url?.host() ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                if let completion {
                    Button(action: submit) {
                        HStack(spacing: 10) {
                            Monogram(url: URL(string: "https://" + completion), tint: Theme.brand, size: 24)
                            let typed = typedPart(of: completion)
                            Text("\(typed)\(Text(completion.dropFirst(typed.count)).foregroundStyle(.secondary))")
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "return").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.brand.opacity(0.12), in: .rect(cornerRadius: 16))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search or enter address", text: $model.searchText)
                        .focused($focused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.webSearch)
                        .submitLabel(.go)
                        .onSubmit(submit)
                    if !model.searchText.isEmpty {
                        Button { model.searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .glassEffect(.regular, in: .capsule)
            }
            .padding(12)
            .background(.regularMaterial, in: .rect(cornerRadius: 30))
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .onAppear { focused = true }
        .onChange(of: model.searchText) { old, new in completes = new.count >= old.count }
        .animation(.snappy(duration: 0.2), value: completion)
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

    /// History matches, minus addresses already open as a tab (those show as "switch to tab" below).
    private var historySuggestions: [HistoryVisit] {
        let open = Set(suggestions.compactMap(\.url))
        return model.historySuggestions.filter { !open.contains($0.url) }
    }

    /// Open and pinned tabs whose title or address matches what's typed.
    private var suggestions: [SidebarItem] {
        let query = model.searchText.lowercased()
        guard query.count > 1, model.searchTarget == .newTab, !model.isIncognito else { return [] }
        return model.sidebar.items
            .filter { $0.kind == .tab && (($0.title ?? "").lowercased().contains(query)
                                           || ($0.url?.absoluteString.lowercased().contains(query) ?? false)) }
            .prefix(4)
            .map { $0 }
    }
}

struct ToastView: View {
    @Environment(AppModel.self) private var model
    let toast: AppModel.Toast

    var body: some View {
        HStack(spacing: 14) {
            Text(toast.message).font(.callout.weight(.medium))
            if toast.canUndo {
                Button("Undo") { model.undoClose() }.font(.callout.weight(.bold))
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .transition(.move(edge: .top).combined(with: .opacity))
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
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}
