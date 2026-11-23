import BoazKit
import CoreSpotlight
import UniformTypeIdentifiers

/// Pinned tabs and favorites in Spotlight, so a system search finds them. Nothing else is indexed: no history, no
/// Today tabs, no Incognito tabs. The index lives on this iPhone only.
enum SpotlightIndex {
    private static let domain = "com.chenkahana.boaz.pinned"
    private static var indexed: [String] = []

    static func update(_ sidebar: Sidebar) {
        let byID = Dictionary(sidebar.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        func isPinnedOrFavorite(_ item: SidebarItem) -> Bool {
            var parentID = item.parentID
            for _ in 0..<16 {
                guard let id = parentID, let parent = byID[id] else { return false }
                if let kind = parent.containerKind { return kind == .pinned || kind == .favorites }
                parentID = parent.parentID
            }
            return false
        }
        let tabs = sidebar.items.filter { item in
            guard item.kind == .tab, item.deletedAt == nil, let scheme = item.url?.scheme?.lowercased(),
                  ["http", "https"].contains(scheme) else { return false }
            return isPinnedOrFavorite(item)
        }
        let signature = tabs.map { "\($0.id)\u{1F}\($0.title ?? "")\u{1F}\($0.url?.absoluteString ?? "")" }.sorted()
        guard signature != indexed else { return }
        indexed = signature
        let items = tabs.compactMap { tab -> CSSearchableItem? in
            guard let url = tab.url else { return nil }
            let attributes = CSSearchableItemAttributeSet(contentType: .url)
            attributes.title = tab.title ?? url.host()
            attributes.contentDescription = url.host()
            attributes.url = url
            return CSSearchableItem(uniqueIdentifier: tab.id, domainIdentifier: domain, attributeSet: attributes)
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            index.indexSearchableItems(items)
        }
    }
}
