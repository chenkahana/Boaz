import FolioKit
import SwiftUI
import WidgetKit

struct FolioWidgetEntry: TimelineEntry {
    let date: Date
    let favorites: [SidebarItem]
}

struct FolioWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FolioWidgetEntry {
        FolioWidgetEntry(date: .now, favorites: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (FolioWidgetEntry) -> Void) {
        completion(FolioWidgetEntry(date: .now, favorites: loadFavorites()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FolioWidgetEntry>) -> Void) {
        let entry = FolioWidgetEntry(date: .now, favorites: loadFavorites())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(900))))
    }

    /// Read-only: the store is opened fresh each refresh since widgets run in their own process.
    private func loadFavorites() -> [SidebarItem] {
        guard let store = try? FolioStore.onDisk(appGroup: FolioStore.appGroup, migrate: false),
              let sidebar = try? store.sidebar(),
              let profileID = (sidebar.profiles.first { $0.isDefault } ?? sidebar.profiles.first)?.id
        else { return [] }
        return Array(sidebar.favorites(profileID: profileID).prefix(4))
    }
}

struct FolioSearchWidget: Widget {
    let kind = "FolioSearchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FolioWidgetProvider()) { entry in
            FolioWidgetView(entry: entry)
        }
        .configurationDisplayName("Search Folio")
        .description("Jump straight into a search, or one of your favorites.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct FolioWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FolioWidgetEntry

    var body: some View {
        switch family {
        // Small and accessory widgets have a single tap target: `widgetURL`, not `Link`.
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "magnifyingglass").font(.title2).widgetAccentable()
            }
            .widgetURL(FolioLink.search())
            .containerBackground(for: .widget) { Color.clear }
            .accessibilityLabel("Search Folio")
        case .systemMedium:
            VStack(alignment: .leading, spacing: 10) {
                searchPill
                if entry.favorites.isEmpty {
                    Text("Add favorites in Folio to see them here.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack(spacing: 8) {
                        ForEach(entry.favorites) { favorite in
                            if let url = favorite.url {
                                Link(destination: FolioLink.open(url)) { FavoriteTile(item: favorite) }
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
                Text("Search Folio").font(.caption).bold()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(.white)
            .widgetURL(FolioLink.search())
            .containerBackground(for: .widget) { Theme.hero }
        }
    }

    private var searchPill: some View {
        Link(destination: FolioLink.search()) {
            Label("Search Folio", systemImage: "magnifyingglass")
                .font(.subheadline.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(.white.opacity(0.18), in: .capsule)
                .foregroundStyle(.white)
        }
    }
}

/// A letter tile per favorite: favicons are cached in the app's own container, which the widget can't read.
private struct FavoriteTile: View {
    let item: SidebarItem

    private var name: String { item.title ?? item.url?.host() ?? "Site" }
    private var letter: String {
        let host = item.url?.host() ?? name
        let trimmed = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return trimmed.first.map { String($0).uppercased() } ?? "•"
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(letter)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.22), in: .rect(cornerRadius: Theme.Radius.row, style: .continuous))
                .widgetAccentable()
            Text(name).font(.caption2).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
    }
}
