import BoazKit
import SwiftUI
import WidgetKit

struct BoazWidgetEntry: TimelineEntry {
    let date: Date
    let favorites: [SidebarItem]
}

struct BoazWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> BoazWidgetEntry {
        BoazWidgetEntry(date: .now, favorites: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (BoazWidgetEntry) -> Void) {
        completion(BoazWidgetEntry(date: .now, favorites: loadFavorites()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BoazWidgetEntry>) -> Void) {
        let entry = BoazWidgetEntry(date: .now, favorites: loadFavorites())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(900))))
    }

    /// Read-only: the store is opened fresh each refresh since widgets run in their own process.
    private func loadFavorites() -> [SidebarItem] {
        guard let store = try? BoazStore.onDisk(appGroup: BoazStore.appGroup, migrate: false),
              let sidebar = try? store.sidebar(),
              let profileID = (sidebar.profiles.first { $0.isDefault } ?? sidebar.profiles.first)?.id
        else { return [] }
        return Array(sidebar.favorites(profileID: profileID).prefix(4))
    }
}

struct BoazSearchWidget: Widget {
    let kind = "BoazSearchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BoazWidgetProvider()) { entry in
            BoazWidgetView(entry: entry)
        }
        .configurationDisplayName("Search Boaz")
        .description("Jump straight into a search, or one of your favorites.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct BoazWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BoazWidgetEntry

    var body: some View {
        switch family {
        // Small and accessory widgets have a single tap target: `widgetURL`, not `Link`.
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "magnifyingglass").font(.title2).widgetAccentable()
            }
            .widgetURL(BoazLink.search())
            .containerBackground(for: .widget) { Color.clear }
            .accessibilityLabel("Search Boaz")
        case .systemMedium:
            VStack(alignment: .leading, spacing: 10) {
                searchPill
                if entry.favorites.isEmpty {
                    Text("Add favorites in Boaz to see them here.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 8) {
                        ForEach(entry.favorites) { favorite in
                            if let url = favorite.url {
                                Link(destination: BoazLink.open(url)) { FavoriteTile(item: favorite) }
                            }
                        }
                    }
                }
            }
            .padding(14)
            .containerBackground(for: .widget) { Theme.hero }
        default:
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.title2).widgetAccentable()
                Text("Search Boaz").font(.caption).bold()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .widgetURL(BoazLink.search())
            .containerBackground(for: .widget) { Theme.hero }
        }
    }

    private var searchPill: some View {
        Link(destination: BoazLink.search()) {
            Label("Search Boaz", systemImage: "magnifyingglass")
                .font(.subheadline.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.18), in: .capsule)
                .foregroundStyle(.white)
        }
    }
}

/// A favorite's icon, from the favicons the app keeps in the App Group; a letter tile until the app has one.
private struct FavoriteTile: View {
    let item: SidebarItem

    private var name: String { item.title ?? item.url?.host() ?? "Site" }
    private var icon: UIImage? {
        guard let host = item.url?.host()?.lowercased(), let file = FaviconFiles.file(host: host) else { return nil }
        return UIImage(contentsOfFile: file.path)
    }
    private var letter: String {
        let host = item.url?.host() ?? name
        let trimmed = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return trimmed.first.map { String($0).uppercased() } ?? "•"
    }

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let icon {
                    Image(uiImage: icon).resizable().widgetAccentedRenderingMode(.fullColor)
                        .scaledToFit().frame(width: 24, height: 24)
                } else {
                    Text(letter).font(.system(.headline, design: .rounded, weight: .bold)).widgetAccentable()
                }
            }
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.22), in: .rect(cornerRadius: Radius.row, style: .continuous))
            Text(name).font(.caption2).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}
