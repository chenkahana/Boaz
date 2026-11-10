import BoazKit
import SwiftUI

/// The wide inner screen's list of tabs along the leading edge: New Tab, then the phone's tabs. Tap one to show it,
/// close it with its ×.
struct TabStrip: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let style = SpaceStyle(model.currentSpace, scheme: scheme)
        ScrollViewReader { proxy in
            List {
                Button { model.beginSearch(.newTab) } label: {
                    Label("New Tab", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                ForEach(model.phoneTabs) { tab in
                    TabStripRow(tab: tab, tint: style.tint)
                }
            }
            // The selected tab stays in view, wherever it was picked (the carousel, a link, a relaunch).
            .onChange(of: model.activeTabID, initial: true) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .buttonStyle(.plain)
        .font(.callout)
        .foregroundStyle(style.foreground, style.secondary)
        .animation(.snappy, value: model.phoneTabs.map(\.id))
        .background(style.gradient.ignoresSafeArea())
    }
}

private struct TabStripRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast
    let tab: SidebarItem
    let tint: Color

    var body: some View {
        let selected = tab.id == model.activeTabID
        let title = tab.title ?? tab.url?.host() ?? "New Tab"
        HStack(spacing: 10) {
            Button { model.activate(tab) } label: {
                HStack(spacing: 10) {
                    Monogram(url: tab.url, tint: tint, size: 22)
                    Text(title).lineLimit(1).fontWeight(selected ? .semibold : .regular)
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 36)
                .contentShape(.rect)
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
            Button("Close \(title)", systemImage: "xmark") { model.close(tab) }
                .labelStyle(.iconOnly)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 36)
                .contentShape(.rect)
        }
        .listRowBackground(
            RoundedRectangle(cornerRadius: Theme.Radius.row)
                .fill(.primary.opacity(selected ? (contrast == .increased ? 0.3 : 0.12) : 0))
                .padding(.horizontal, 6)
        )
        .listRowSeparator(.hidden)
    }
}
