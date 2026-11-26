import AppKit
import SwiftUI

/// The Mac app's icon: the chosen pretzel replaces the Dock icon while Boaz runs. The DMG's Dock tile plug-in
/// (Apps/DockTile) reads the same preference to show it when Boaz isn't running.
enum MacAppIcon {
    /// Posted (distributed, object: the app's bundle identifier) after the choice changes, for the Dock tile plug-in.
    static let changedNotification = Notification.Name("com.chenkahana.boaz.appIconChanged")

    static var selected: AppIconChoice {
        AppIconChoice.with(id: UserDefaults.standard.string(forKey: AppIconChoice.selectionKey))
    }

    /// Where the alternates' .icns files live: the app's Resources, or the DMG's Boaz resource bundle.
    private static var resources: Bundle {
        #if BOAZ_CHROMIUM
        BoazRuntimeResources.bundle
        #else
        Bundle.main
        #endif
    }

    private static var cache: [String: NSImage] = [:]

    /// The icon for a choice; Classic is the bundle's own icon.
    static func image(_ choice: AppIconChoice) -> NSImage {
        if let hit = cache[choice.id] { return hit }
        let image = choice.alternateName
            .flatMap { resources.url(forResource: $0, withExtension: "icns") }
            .flatMap(NSImage.init(contentsOf:))
            ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        cache[choice.id] = image
        return image
    }

    /// Puts the saved choice on the Dock icon. Called at launch and after every change.
    static func apply() {
        let choice = selected
        // nil restores the bundle's icon.
        NSApplication.shared.applicationIconImage = choice.alternateName == nil ? nil : image(choice)
    }

    static func select(_ choice: AppIconChoice) {
        UserDefaults.standard.set(choice.id, forKey: AppIconChoice.selectionKey)
        apply()
        DistributedNotificationCenter.default().postNotificationName(changedNotification,
            object: Bundle.main.bundleIdentifier, userInfo: nil, deliverImmediately: true)
    }
}

/// Settings ▸ Theme ▸ App Icon: every pretzel as a tile; hover lifts it, the chosen one wears a ring.
struct AppIconSettings: View {
    @AppStorage(AppIconChoice.selectionKey) private var selection = AppIconChoice.classic.id

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 120), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Boaz wears it in the Dock. \(AppIconChoice.with(id: selection).caption).")
                .font(.callout)
                .foregroundStyle(.secondary)
            // Its own scroll view, so the long Theme pane doesn't grow by every row of pretzels.
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(AppIconChoice.all) { choice in
                        AppIconTile(choice: choice, selected: choice.id == selection) {
                            withAnimation(.snappy(duration: 0.25)) { MacAppIcon.select(choice) }
                        }
                    }
                }
                .padding(6)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("App icons")
            }
            .frame(height: 300)
        }
        .padding(.vertical, 4)
    }
}

private struct AppIconTile: View {
    let choice: AppIconChoice
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(nsImage: MacAppIcon.image(choice))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(hovering ? 0.25 : 0.12), radius: hovering ? 8 : 3, y: hovering ? 5 : 2)
                    .scaleEffect(hovering && !reduceMotion ? 1.08 : 1)
                    .offset(y: hovering && !reduceMotion ? -3 : 0)
                    .padding(5)
                    .background {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .opacity(selected ? 1 : 0)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                Text(choice.title)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { inside in withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) { hovering = inside } }
        .help(choice.caption)
        .accessibilityLabel(choice.title)
        .accessibilityValue(choice.caption)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(choice.accessibilityIdentifier)
    }
}
