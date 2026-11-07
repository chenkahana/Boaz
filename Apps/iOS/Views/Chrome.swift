import FolioKit
import SwiftUI

/// Address/search entry that slides up over whatever is on screen.
struct SearchOverlay: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var model = model
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.25).ignoresSafeArea()
                .onTapGesture { model.searchTarget = nil }
            VStack(spacing: 8) {
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
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search or enter address", text: $model.searchText)
                        .focused($focused)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.webSearch)
                        .submitLabel(.go)
                        .onSubmit { model.submitSearch() }
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
    }

    /// Open and pinned tabs whose title or address matches what's typed.
    private var suggestions: [SidebarItem] {
        let query = model.searchText.lowercased()
        guard query.count > 1, model.searchTarget == .newTab else { return [] }
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

/// Letter tile standing in for a favicon (no third-party favicon service, so no browsing data leaves the device).
struct Monogram: View {
    let url: URL?
    let tint: Color
    let size: CGFloat

    var body: some View {
        let host = url?.host()?.replacingOccurrences(of: "www.", with: "") ?? "?"
        Text(host.prefix(1).uppercased())
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .rect(cornerRadius: size * 0.28))
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
