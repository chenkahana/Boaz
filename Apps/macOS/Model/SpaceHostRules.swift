import AppKit
import BoazKit
import Foundation

/// Site rules (`SpaceRoute`, synced): a rule decides which space a new tab opens in; a tab that already exists never
/// moves. Evaluated only where a tab is born: links from other apps (`openExternal`), the command bar's new tab, and
/// new tabs a page opens in the same profile. Never for searches, ⌘L, Incognito, pop-up windows or the iPhone.
enum SiteRuleInput {
    /// `github.com`, `github.com/acme`, or a pasted URL (host only). Nil for anything that isn't a web site.
    static func parse(_ input: String) -> (host: String, pathPrefix: String?)? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains(where: \.isWhitespace) else { return nil }
        var path: String?
        if value.contains(":") {
            guard let components = URLComponents(string: value),
                  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                  let host = components.host, !host.isEmpty else { return nil }
            value = host
        } else if let slash = value.firstIndex(of: "/") {
            path = String(value[slash...])
            value = String(value[..<slash])
        }
        if value.lowercased().hasPrefix("www.") { value = String(value.dropFirst(4)) }
        guard value.contains("."),
              let route = try? SpaceRoute(host: value, pathPrefix: path, spaceID: "-", profileID: "-", position: 0)
        else { return nil }
        return (route.host, route.pathPrefix)
    }

    /// The host a tab's "Always Open … in …" item names: the page's host without `www.`.
    static func host(of url: URL?) -> String? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host() else { return nil }
        return parse(host)?.host
    }

    static func label(_ host: String, _ pathPrefix: String?) -> String { host + (pathPrefix ?? "") }

    /// What a rule for this input will match, said in full.
    static func caption(host: String, pathPrefix: String?, space: String) -> String {
        if let pathPrefix { return "Opens \(host), its subdomains and everything under \(pathPrefix) in \(space)." }
        return "Opens \(host) and its subdomains in \(space)."
    }
}

/// #98's rules, kept in UserDefaults before rules synced: read once to copy them into the store.
private struct LegacySpaceHostRule: Codable {
    var host: String
    var spaceID: String
}

extension MacModel {
    private static let legacySpaceHostRulesKey = "spaceHostRules"

    /// Copies #98's UserDefaults rules into the store, then removes the key, only once the copy is written (#13).
    func migrateLegacySpaceHostRules(_ store: BoazStore) {
        guard let data = UserDefaults.standard.data(forKey: Self.legacySpaceHostRulesKey) else { return }
        do {
            let rules = try JSONDecoder().decode([LegacySpaceHostRule].self, from: data)
            let valid = rules.compactMap { rule in SiteRuleInput.parse(rule.host).map { ($0.host, rule.spaceID) } }
            try store.importSpaceHostRules(valid)
            UserDefaults.standard.removeObject(forKey: Self.legacySpaceHostRulesKey)
        } catch {
            Self.routesLog.error("Site rules weren't migrated: \(String(describing: error), privacy: .public)")
        }
    }

    /// The space a new tab for `url` opens in, by the first fitting rule whose space exists.
    func routedSpace(for url: URL) -> Space? {
        let live = Set(sidebar.spaces.map(\.id))
        return SpaceRoute.route(for: url, in: spaceRoutes, liveSpaceIDs: live).flatMap { space($0.spaceID) }
    }

    func routes(in space: Space) -> [SpaceRoute] { spaceRoutes.filter { $0.spaceID == space.id } }

    /// The tab's rule shortcut: the site-wide rule for its host, if any.
    func siteRoute(host: String) -> SpaceRoute? { spaceRoutes.first { $0.host == host && $0.pathPrefix == nil } }

    @discardableResult
    func addRoute(host: String, pathPrefix: String?, to space: Space) -> SpaceRoute? {
        do {
            let route = try store?.addSpaceRoute(host: host, pathPrefix: pathPrefix, spaceID: space.id,
                                                 profileID: space.profileID)
            refreshRoutes()
            return route
        } catch {
            showError("Couldn't save this site rule. Try again.", error)
            return nil
        }
    }

    func repoint(_ route: SpaceRoute, to space: Space) {
        do { try store?.setSpaceRoute(id: route.id, spaceID: space.id, profileID: space.profileID) }
        catch { showError("Couldn't save this site rule. Try again.", error) }
        refreshRoutes()
    }

    func removeRoute(_ route: SpaceRoute) {
        do { try store?.removeSpaceRoute(id: route.id) } catch { showError("Couldn't remove this site rule. Try again.", error) }
        refreshRoutes()
    }

    func moveRoute(_ route: SpaceRoute, before other: SpaceRoute?) {
        do { try store?.moveSpaceRoute(id: route.id, before: other?.id) }
        catch { showError("Couldn't move this site rule. Try again.", error) }
        refreshRoutes()
    }

    /// Customize Space's "Sites that open here" on Save: rules dropped there are removed, new ones added (one already
    /// pointing elsewhere is re-pointed here).
    func saveRoutes(_ labels: [String], in space: Space) {
        let current = routes(in: space)
        let kept = Set(labels)
        for route in current where !kept.contains(SiteRuleInput.label(route.host, route.pathPrefix)) { removeRoute(route) }
        let existing = Set(current.map { SiteRuleInput.label($0.host, $0.pathPrefix) })
        for label in labels where !existing.contains(label) {
            guard let site = SiteRuleInput.parse(label) else { continue }
            addRoute(host: site.host, pathPrefix: site.pathPrefix, to: space)
        }
    }

    /// Reads the list right after an edit, so Settings and menus don't wait for the observation.
    func refreshRoutes() {
        if let routes = try? store?.spaceRoutes() { spaceRoutes = routes }
    }

    /// Follows the synced rule list for the life of the app.
    func observeSpaceRoutes(_ store: BoazStore) async {
        var failures = 0
        while !Task.isCancelled {
            do {
                for try await routes in store.spaceRouteUpdates() {
                    failures = 0
                    spaceRoutes = routes
                }
                return
            } catch {
                failures += 1
                try? await Task.sleep(for: .seconds(min(1 << min(failures, 5), 30)))
            }
        }
    }

    // MARK: Per-tab override

    func hasSpaceOverride(_ tabID: String) -> Bool { tabSpaceOverrides.contains(tabID) }

    /// The user put this tab in a space (moved or dragged it, or sent it back from a rule's space): rules never move
    /// it, and tabs it opens follow it. This Mac only.
    func setSpaceOverride(_ tab: SidebarItem) {
        guard tab.kind == .tab, tabSpaceOverrides.insert(tab.id).inserted else { return }
        do { try store?.setTabSpaceOverride(tabID: tab.id, profileID: tab.profileID) }
        catch { Self.routesLog.error("Tab override not saved: \(String(describing: error), privacy: .public)") }
    }

    // MARK: Links from other apps

    /// The normal window a routed link opens in: the last active one, else any visible one.
    var visibleMainBrowser: BrowserState? {
        ([lastActiveBrowser].compactMap { $0 } + openBrowsers).first { !$0.isIncognito && $0.window?.isVisible == true }
    }

    /// Links that match a rule: each opens as a Today tab in its rule's space, and the last active normal window
    /// switches to the last one's space in place (#2). A new window only when no normal window is visible.
    func openRouted(_ links: [(url: URL, space: Space)]) {
        let tabs = links.compactMap { newTab($0.url, in: $0.space.id) }
        guard let last = tabs.last else { return }
        guard let browser = visibleMainBrowser, let window = browser.window else { openInNewWindow(last); return }
        let previous = browser.spaceID
        browser.activate(last)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        if let previous { browser.showRoutedToast(last, from: previous) }
    }
}

extension BrowserState {
    /// The space a rule sends a new tab for `url` to, when that isn't the one showing. Nil in Incognito, for tabs
    /// opened from a tab the user placed by hand, and (`profileID`) for another profile's space.
    func routedSpace(for url: URL, from source: SidebarItem?, inProfile profileID: String? = nil) -> Space? {
        guard !isIncognito, source.map({ model.hasSpaceOverride($0.id) }) != true,
              let space = model.routedSpace(for: url), space.id != spaceID,
              profileID.map({ $0 == space.profileID }) ?? true else { return nil }
        return space
    }

    /// "Opened in Work", with "Open in Personal" to put the tab back where the window was. Nothing when the rule's
    /// space was already showing.
    func showRoutedToast(_ tab: SidebarItem, from previousSpaceID: String, select: Bool = true) {
        guard let space = model.space(tab.spaceID), space.id != previousSpaceID,
              let previous = model.space(previousSpaceID) else { return }
        model.showToast("Opened in \(space.title)", action: .init(title: "Open in \(previous.title)") { [weak self] in
            self?.sendBack(tab.id, to: previous.id, select: select)
        })
    }

    /// The toast's override: the routed tab goes back to the space that was showing and is never routed again. In
    /// the same profile it moves with its page; across profiles the URL reopens there (that profile's session).
    func sendBack(_ tabID: String, to spaceID: String, select: Bool) {
        guard let tab = model.item(tabID), let target = model.space(spaceID) else { return }
        if tab.profileID == target.profileID {
            model.move(tab, to: target)
            if select, let moved = model.item(tabID) { activate(moved) }
            return
        }
        guard let url = tab.url, let reopened = model.newTab(url, title: tab.title, in: target.id) else { return }
        model.setSpaceOverride(reopened)
        unload(tab.id)
        model.archive(tab, toast: false)
        activate(reopened)
    }
}
