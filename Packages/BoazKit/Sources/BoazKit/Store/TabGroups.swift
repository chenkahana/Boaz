import Foundation

/// Tab groups: the folders in a space's Today. A group made on a Mac records that Mac's `deviceID`, so only that
/// Mac's Today lists it, as with its Today tabs; folders that recorded no device (Tidy Tabs and Arc imports before
/// 0.5.0) show on every Mac. Pinned folders are untouched: in Pinned it's a folder, in Today it's a group.
extension Sidebar {
    public static let newGroupTitle = "New Group"

    /// A space's Today as `deviceID` lists it, in order: its own tabs and groups, plus those that recorded no device.
    public func today(in spaceID: String, onDevice deviceID: String) -> [SidebarItem] {
        guard let box = container(.unpinned, in: spaceID) else { return [] }
        return children(of: box.id).filter { $0.kind != .container && ($0.deviceID == nil || $0.deviceID == deviceID) }
    }

    /// The groups `deviceID` lists in a space's Today.
    public func groups(in spaceID: String, onDevice deviceID: String) -> [SidebarItem] {
        today(in: spaceID, onDevice: deviceID).filter { $0.kind == .folder }
    }

    /// What Clear archives on `deviceID`: its Today tabs and the tabs in its groups, and those groups. Another
    /// device's groups, which this one doesn't show, stay.
    public func clearable(in spaceID: String, onDevice deviceID: String) -> (tabs: [SidebarItem], groups: [SidebarItem]) {
        let rows = today(in: spaceID, onDevice: deviceID)
        let groups = rows.filter { $0.kind == .folder }
        let tabs = rows.filter { $0.kind == .tab } + groups.flatMap { children(of: $0.id).filter { $0.kind == .tab } }
        return (tabs, groups)
    }

    /// A new, expanded group named "New Group" in `tab`'s slot, with `tab` inside: the group record, then the tab.
    public func newGroup(around tab: SidebarItem, id: String = UUID().uuidString, deviceID: String,
                         at date: Date = .now) -> [SidebarItem]? {
        guard tab.kind == .tab, let parentID = tab.parentID else { return nil }
        let group = SidebarItem(id: id, spaceID: tab.spaceID, profileID: tab.profileID, parentID: parentID,
                                kind: .folder, title: Self.newGroupTitle, position: tab.position,
                                createdAt: date, modifiedAt: date, deviceID: deviceID)
        var moved = tab
        moved.parentID = group.id
        moved.position = 0
        moved.modifiedAt = date
        return [group, moved]
    }

    /// A new, empty, expanded group at the top of a space's Today.
    public func newEmptyGroup(in spaceID: String, id: String = UUID().uuidString, deviceID: String,
                              at date: Date = .now) -> SidebarItem? {
        guard let box = container(.unpinned, in: spaceID), let space = box.spaceID else { return nil }
        let top = children(of: box.id).map(\.position).min().map { $0 - 1 } ?? 0
        return SidebarItem(id: id, spaceID: space, profileID: box.profileID, parentID: box.id, kind: .folder,
                           title: Self.newGroupTitle, position: top, createdAt: date, modifiedAt: date,
                           deviceID: deviceID)
    }

    /// A folder becoming a group stays one level deep: the tabs in its subfolders join it where they showed, in
    /// sidebar order, and the subfolders go (tombstones, last). No tab is lost. Empty when there's nothing to flatten.
    public func flattened(_ folder: SidebarItem, at date: Date = .now) -> [SidebarItem] {
        guard children(of: folder.id).contains(where: { $0.kind == .folder }) else { return [] }
        func tabs(under id: String) -> [SidebarItem] {
            children(of: id).flatMap { $0.kind == .folder ? tabs(under: $0.id) : [$0] }
        }
        func folders(under id: String) -> [SidebarItem] {
            children(of: id).filter { $0.kind == .folder }.flatMap { [$0] + folders(under: $0.id) }
        }
        var records = tabs(under: folder.id).enumerated().map { index, item in
            var item = item
            item.parentID = folder.id
            item.position = Double(index)
            item.modifiedAt = date
            return item
        }
        records += folders(under: folder.id).map { var sub = $0; sub.deletedAt = date; sub.modifiedAt = date; return sub }
        return records
    }

    /// Ungrouping: the group's items, in their order, take the group's slot between its neighbours, and the group
    /// goes (a tombstone, last). Nothing closes.
    public func ungrouped(_ group: SidebarItem, at date: Date = .now) -> [SidebarItem] {
        guard group.kind == .folder, let parentID = group.parentID else { return [] }
        let inside = children(of: group.id)
        let siblings = children(of: parentID).filter { $0.id != group.id }.map(\.position)
        let lower = siblings.filter { $0 < group.position }.max() ?? group.position - 1
        let upper = siblings.filter { $0 > group.position }.min() ?? group.position + 1
        let step = (upper - lower) / Double(inside.count + 1)
        var records = inside.enumerated().map { index, item in
            var item = item
            item.parentID = parentID
            item.position = lower + step * Double(index + 1)
            item.modifiedAt = date
            return item
        }
        var removed = group
        removed.deletedAt = date
        removed.modifiedAt = date
        records.append(removed)
        return records
    }
}
