import FolioKit
import Foundation
import FoundationModels

@Generable
nonisolated struct TabGrouping {
    @Guide(description: "Two to five folders, each holding at least two related tabs", .count(1...6))
    var folders: [TabFolder]
}

@Generable
nonisolated struct TabFolder {
    @Guide(description: "Folder name: one to three words in Title Case, naming the shared topic or task, no emoji")
    var name: String
    @Guide(description: "Numbers of the tabs that belong in this folder, from the numbered list")
    var tabs: [Int]
}

@Generable
nonisolated struct TitleRewrites {
    @Guide(description: "One entry for each tab whose title is long or unclear; skip tabs whose title is already short and clear")
    var titles: [TitleRewrite]
}

@Generable
nonisolated struct TitleRewrite {
    @Guide(description: "Number of the tab from the numbered list")
    var tab: Int
    @Guide(description: "New title: two to four words naming the page itself, without the site's name unless it's needed, no emoji")
    var title: String
}

/// Groups a space's Today tabs into named folders, and shortens tab titles, with the on-device model.
enum TabTidier {
    /// Tidy needs at least this many Today tabs.
    static let minimumTabs = 4
    /// More than this and the list wouldn't fit the model's context; the rest stay where they are.
    static let maximumTabs = 60

    struct Group: Identifiable {
        let id = UUID()
        var name: String
        var tabs: [SidebarItem]
    }

    struct Plan {
        var groups: [Group]
        /// Tabs the model didn't place; they stay in Today.
        var leftovers: [SidebarItem]
    }

    struct TitleChange: Identifiable {
        var id: String { tab.id }
        let tab: SidebarItem
        var title: String
        var isIncluded = true
    }

    enum Failure: LocalizedError {
        case nothingToGroup, nothingToRename
        var errorDescription: String? {
            switch self {
            case .nothingToGroup: "Apple Intelligence didn't find groups among these tabs."
            case .nothingToRename: "These titles are already short and clear."
            }
        }
    }

    // MARK: Grouping

    private static let groupInstructions = """
        You organize a person's open browser tabs into folders by topic or task. Use the tab titles and website hosts. \
        Make two to five folders, each with at least two tabs. Leave out any tab that doesn't fit a folder. Every \
        tab number can appear in at most one folder.
        \(AIFeatures.untrustedContentRule)
        """

    static func groups(for tabs: [SidebarItem]) async throws -> Plan {
        let candidates = Array(tabs.prefix(maximumTabs))
        let session = LanguageModelSession(model: .default, instructions: groupInstructions)
        let prompt = """
            \(AIFeatures.delimited(numberedList(candidates)))

            Group the tabs above into folders.
            """
        let grouping = try await session.respond(to: prompt, generating: TabGrouping.self).content
        return validate(grouping, tabs: candidates, extra: Array(tabs.dropFirst(maximumTabs)))
    }

    /// Keeps indexes that exist and haven't been used yet, drops folders left with fewer than two tabs, and keeps
    /// each folder's tabs in their sidebar order. Everything not placed stays where it is.
    static func validate(_ grouping: TabGrouping, tabs: [SidebarItem], extra: [SidebarItem] = []) -> Plan {
        var used = Set<Int>()
        var groups: [Group] = []
        for folder in grouping.folders {
            let indexes = folder.tabs.map { $0 - 1 }.filter { tabs.indices.contains($0) && used.insert($0).inserted }
            guard indexes.count >= 2 else { indexes.forEach { used.remove($0) }; continue }
            let name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)
            groups.append(Group(name: name.isEmpty ? "Folder" : String(name), tabs: indexes.sorted().map { tabs[$0] }))
        }
        let leftovers = tabs.indices.filter { !used.contains($0) }.map { tabs[$0] } + extra
        return Plan(groups: groups, leftovers: leftovers)
    }

    /// The new folders (at the end of Today) and the moved tabs, ready to save.
    static func records(for plan: Plan, today box: SidebarItem, in sidebar: Sidebar, now: Date = .now) -> [SidebarItem] {
        var position = sidebar.nextPosition(in: box.id)
        var records: [SidebarItem] = []
        for group in plan.groups where !group.tabs.isEmpty {
            let folder = SidebarItem(id: UUID().uuidString, spaceID: box.spaceID, profileID: box.profileID,
                                     parentID: box.id, kind: .folder, title: group.name, position: position,
                                     createdAt: now, modifiedAt: now)
            position += 1
            records.append(folder)
            for (offset, tab) in group.tabs.enumerated() {
                var moved = tab
                moved.parentID = folder.id
                moved.position = Double(offset)
                moved.modifiedAt = now
                records.append(moved)
            }
        }
        return records
    }

    // MARK: Titles

    /// Tabs whose titles are worth shortening: long ones, ones made of several parts ("Story | Site"), and ones
    /// that are just an address.
    static func messyTitled(_ tabs: [SidebarItem]) -> [SidebarItem] {
        tabs.filter { tab in
            guard tab.kind == .tab, tab.url != nil else { return false }
            guard let title = tab.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty else { return true }
            let separators = [" | ", " - ", " – ", " — ", " · ", " : ", " :: "]
            return title.count > 28 || separators.contains { title.contains($0) } || title == tab.url?.host()
        }
    }

    private static let titleInstructions = """
        You rename browser tabs so a list of them is easy to scan. Each new title is two to four words that name the \
        page itself, in the page's language. Drop site names, slogans, notification counts and separators. Keep \
        names of people, products and places.
        \(AIFeatures.untrustedContentRule)
        """

    static func titles(for tabs: [SidebarItem]) async throws -> [TitleChange] {
        let candidates = Array(tabs.prefix(maximumTabs))
        let session = LanguageModelSession(model: .default, instructions: titleInstructions)
        let prompt = """
            \(AIFeatures.delimited(numberedList(candidates)))

            Write a short new title for each tab above whose title is long or unclear.
            """
        let rewrites = try await session.respond(to: prompt, generating: TitleRewrites.self).content
        var seen = Set<Int>()
        return rewrites.titles.compactMap { rewrite in
            let index = rewrite.tab - 1
            let title = rewrite.title.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"'")))
            guard candidates.indices.contains(index), seen.insert(index).inserted,
                  !title.isEmpty, title.count <= 48, title != candidates[index].title else { return nil }
            return TitleChange(tab: candidates[index], title: title)
        }
    }

    // MARK: Helpers

    /// "1. Title — host" per tab. Titles are capped so one long title can't crowd out the rest.
    private static func numberedList(_ tabs: [SidebarItem]) -> String {
        tabs.enumerated().map { index, tab in
            let host = tab.url?.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
            let title = String((tab.title ?? host).replacingOccurrences(of: "\n", with: " ").prefix(90))
            return "\(index + 1). \(title) — \(host)"
        }
        .joined(separator: "\n")
    }
}
