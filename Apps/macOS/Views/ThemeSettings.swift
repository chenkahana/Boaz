import BoazKit
import SwiftUI

/// Settings ▸ Theme: every design choice in one place. The app icon, each space's background (its colors, gradient,
/// texture and how much of the desktop shows through) and the sidebar's text size.
struct ThemeSettings: View {
    @Environment(MacModel.self) private var model
    @AppStorage(Preferences.sidebarTextSizeKey) private var sidebarTextSize = SidebarStyle.defaultTextSize
    @State private var spaceID: String?

    private var space: Space? { model.space(spaceID) ?? model.sidebar.spaces.first }

    var body: some View {
        Form {
            Section("App Icon") { AppIconSettings() }
            Section {
                if model.sidebar.spaces.isEmpty {
                    Text("No spaces yet")
                } else {
                    Picker("Space", selection: Binding(get: { space?.id }, set: { spaceID = $0 })) {
                        ForEach(model.sidebar.spaces) { space in
                            Text([space.icon, space.title].compactMap { $0 }.joined(separator: " ")).tag(Optional(space.id))
                        }
                    }
                }
                if let space { SpaceBackgroundEditor(space: space).id(space.id) }
            } header: {
                Text("Space Background")
            } footer: {
                Text("Changes show in every window right away and sync with the space.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Sidebar") {
                Picker("Sidebar Text Size", selection: $sidebarTextSize) {
                    Text("Small").tag(14.0)
                    Text("Medium").tag(15.0)
                    Text("Large").tag(17.0)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// One space's background, as Customize Space edits it, saved a moment after each change.
private struct SpaceBackgroundEditor: View {
    @Environment(MacModel.self) private var model
    let space: Space
    @State private var options: SpaceThemeOptions

    init(space: Space) {
        self.space = space
        _options = State(initialValue: SpaceThemeOptions(themeJSON: space.themeJSON))
    }

    var body: some View {
        VStack(spacing: 14) {
            preview
            ThemeColorPicker(options: $options)
        }
        .padding(.vertical, 6)
        .task(id: options) {
            guard options != SpaceThemeOptions(themeJSON: space.themeJSON) else { return }
            // A drag on the color field or a slider changes the options many times a second; save where it settles.
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let current = model.space(space.id) else { return }
            try? model.store?.updateSpace(current.id, title: current.title, icon: current.icon,
                                          themeJSON: options.applied(to: current.themeJSON))
        }
    }

    /// The space in Light and Dark, unless it keeps to one: its backdrop with its icon and name.
    private var preview: some View {
        let schemes: [ColorScheme] = switch options.appearance {
        case .system: [.light, .dark]
        case .light: [.light]
        case .dark: [.dark]
        }
        var previewed = space
        previewed.themeJSON = options.applied(to: space.themeJSON)
        return HStack(spacing: 10) {
            ForEach(schemes, id: \.self) { scheme in
                let style = SpaceStyle(previewed, scheme: scheme)
                HStack(spacing: 8) {
                    Text(space.icon ?? "").font(.title2)
                    Text(space.title).font(.system(.title3, design: .rounded, weight: .bold)).lineLimit(1)
                        .foregroundStyle(style.foreground)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background { SpaceBackdrop(style: style, streakRadius: 160) }
                .clipShape(.rect(cornerRadius: 14, style: .continuous))
                .environment(\.colorScheme, scheme)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: \(space.title)")
        .accessibilityAddTraits(.isImage)
        .animation(.smooth, value: options)
    }
}
