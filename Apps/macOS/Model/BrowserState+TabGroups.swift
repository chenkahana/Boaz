import BoazKit
import SwiftUI

/// Tab groups from this window: a new group opens the Rename sheet on "New Group".
extension BrowserState {
    /// The group the active tab sits in, if any.
    var activeGroup: SidebarItem? { activeTab.flatMap(model.group(of:)) }

    /// Whether the active tab can start a group: a Today tab, not Incognito's.
    var canGroupActiveTab: Bool {
        guard let tab = activeTab, !isPrivate(tab) else { return false }
        return model.container(of: tab)?.containerKind == .unpinned
    }

    func addToNewGroup(_ tab: SidebarItem) {
        guard let group = withMotion(.standard, { model.addToNewGroup(tab) }) else { return }
        rename = .init(target: .item(group), text: group.title ?? Sidebar.newGroupTitle)
    }

    func addActiveTabToNewGroup() {
        guard canGroupActiveTab, let tab = activeTab else { return }
        addToNewGroup(tab)
    }

    func newGroup(in space: Space) {
        guard let group = withMotion(.standard, { model.newGroup(in: space) }) else { return }
        rename = .init(target: .item(group), text: group.title ?? Sidebar.newGroupTitle)
    }

    func toggleActiveGroup() {
        guard let group = activeGroup else { return }
        withAnimation(SidebarStyle.motion) { model.toggleExpanded(group) }
    }
}
