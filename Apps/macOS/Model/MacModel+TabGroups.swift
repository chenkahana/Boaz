import BoazKit
import SwiftUI

/// Tab groups: folders in a space's Today, this Mac's own (`Sidebar.today(in:onDevice:)`). In Pinned it's a folder,
/// in Today it's a group.
extension MacModel {
    /// A folder in Today, not a live folder.
    func isGroup(_ item: SidebarItem) -> Bool {
        item.kind == .folder && item.liveSource == nil && container(of: item)?.containerKind == .unpinned
    }

    /// This Mac's groups in a space's Today, in sidebar order.
    func groups(in space: Space) -> [SidebarItem] { sidebar.groups(in: space.id, onDevice: deviceID) }

    /// Every Today tab of this Mac's, those in its groups too, for the command bar.
    func allTodayTabs(in space: Space) -> [SidebarItem] {
        let (tabs, _) = sidebar.clearable(in: space.id, onDevice: deviceID)
        return tabs
    }

    /// A new group in a Today tab's slot, with the tab inside.
    @discardableResult
    func addToNewGroup(_ tab: SidebarItem) -> SidebarItem? {
        guard container(of: tab)?.containerKind == .unpinned, item(tab.id) != nil,
              let records = sidebar.newGroup(around: tab, deviceID: deviceID) else { return nil }
        commit(records)
        return records.first
    }

    /// A new, empty group at the top of a space's Today.
    @discardableResult
    func newGroup(in space: Space) -> SidebarItem? {
        guard let group = sidebar.newEmptyGroup(in: space.id, deviceID: deviceID) else { return nil }
        commit(group)
        return group
    }

    /// The group a tab sits in, if it's in one.
    func group(of tab: SidebarItem) -> SidebarItem? {
        item(tab.parentID).flatMap { isGroup($0) ? $0 : nil }
    }

    /// A tab leaves its group and lands just below it.
    func removeFromGroup(_ tab: SidebarItem) {
        guard let group = group(of: tab), let today = group.parentID else { return }
        let next = sidebar.children(of: today).first { $0.position > group.position }
        move(tab.id, into: today, before: next?.id)
    }

    /// Opens a tab's collapsed group, so the tab the window jumps to shows in the sidebar.
    func reveal(_ tab: SidebarItem) {
        guard let group = group(of: tab), !group.isExpanded else { return }
        withAnimation(SidebarStyle.motion) { toggleExpanded(group) }
    }

    /// Ungroup: the group's tabs keep their order and take its slot, and the group goes. One undoable change.
    func ungroup(_ group: SidebarItem) {
        let records = sidebar.ungrouped(group)
        guard !records.isEmpty else { return }
        let before = records.compactMap { item($0.id) }
        withAnimation(SidebarStyle.motion) { commit(records) }
        showToast("Ungrouped \u{201C}\(group.title ?? Sidebar.newGroupTitle)\u{201D}", canUndo: true)
        AIUndo.register(toast: toast?.id) { [weak self] in
            withAnimation(SidebarStyle.motion) { self?.commit(before) }
        }
    }
}
