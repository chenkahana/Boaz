import FolioKit
import SwiftUI

/// Folders inside Today (from Tidy Tabs or an Arc import), listed above Today's cards. Shows nothing when there are none.
struct TodayFolders: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isSidebar) private var isSidebar
    let space: Space
    let tint: Color

    var body: some View {
        let folders = model.sidebar.container(.unpinned, in: space.id)
            .map { model.sidebar.children(of: $0.id).filter { $0.kind == .folder } } ?? []
        if !folders.isEmpty {
            VStack(spacing: 0) {
                ForEach(folders) { TodayFolderRow(folder: $0, tint: tint) }
            }
            .padding(isSidebar ? 4 : 8)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: Theme.Radius.tile))
            .animation(.snappy, value: folders.map(\.id))
        }
    }
}

private struct TodayFolderRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sidebar) private var sidebar
    let folder: SidebarItem
    let tint: Color

    var body: some View {
        Button { withAnimation(.snappy) { model.toggleExpanded(folder) } } label: {
            HStack(spacing: 10) {
                Image(systemName: folder.isExpanded ? "folder.fill" : "folder").frame(width: 24)
                Text(folder.title ?? "Folder")
                Spacer()
                Image(systemName: "chevron.right").rotationEffect(.degrees(folder.isExpanded ? 90 : 0)).font(.caption)
            }
            .font(.callout)
            .padding(.vertical, 7).padding(.horizontal, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityValue(folder.isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Shows or hides the folder's tabs")
        .contextMenu {
            Button("Ungroup", systemImage: "folder.badge.minus") { model.ungroup(folder) }
        }
        if folder.isExpanded {
            ForEach(model.sidebar.children(of: folder.id).filter { $0.kind == .tab }) { tab in
                let active = model.activeTabID == tab.id
                Button { model.activate(tab); sidebar?.didPick() } label: {
                    HStack(spacing: 10) {
                        Monogram(url: tab.url, tint: tint, size: 24)
                        Text(tab.title ?? tab.url?.host() ?? "New Tab").lineLimit(1)
                            .fontWeight(active ? .semibold : .regular)
                        Spacer()
                    }
                    .font(.callout)
                    .padding(.vertical, 7).padding(.horizontal, 10).padding(.leading, 18)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .background(.white.opacity(active ? 0.3 : 0), in: .rect(cornerRadius: Theme.Radius.row))
                .contextMenu {
                    Button("Pin", systemImage: "pin") { model.togglePin(tab) }
                    Button("Archive Tab", systemImage: "archivebox", role: .destructive) { model.close(tab) }
                }
            }
        }
    }
}
