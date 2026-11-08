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
        case .accessoryCircular:
            Link(destination: FolioLink.search()) {
                Image(systemName: "magnifyingglass")
            }
        case .systemMedium:
            VStack(alignment: .leading, spacing: 10) {
                searchPill
                HStack(spacing: 8) {
                    ForEach(entry.favorites) { favorite in
                        if let url = favorite.url {
                            Link(destination: FolioLink.open(url)) { FavoriteTile(item: favorite) }
                        }
                    }
                }
            }
            .padding(14)
            .containerBackground(for: .widget) { Theme.hero }
        default:
            Link(destination: FolioLink.search()) {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.title2)
                    Text("Search Folio").font(.caption).bold()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(.white)
            }
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

private struct FavoriteTile: View {
    let item: SidebarItem

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "globe")
            Text(item.title ?? item.url?.host() ?? "Site").font(.caption2).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
    }
}
