import SwiftUI
import UIKit

/// Settings section that switches between the primary icon and the palette alternates
/// (`AppIcon-*` sets, rendered by `Tools/make-icon.swift`).
struct AppIconPicker: View {
    private struct Choice: Identifiable {
        let label: String
        let iconName: String?
        /// Spoken after the name, so VoiceOver users can tell the palettes apart.
        let detail: String
        var id: String { iconName ?? "AppIcon" }
    }

    private static let choices = [
        Choice(label: "Default", iconName: nil, detail: "Cobalt and coral on night"),
        Choice(label: "Midnight", iconName: "AppIcon-Midnight", detail: "Cyan and violet on deep navy"),
        Choice(label: "Glass", iconName: "AppIcon-Glass", detail: "White and blush on indigo"),
        Choice(label: "Aurora", iconName: "AppIcon-Aurora", detail: "Green and violet northern lights"),
        Choice(label: "Electric", iconName: "AppIcon-Electric", detail: "White and yellow on bright blue"),
        Choice(label: "Tide", iconName: "AppIcon-Tide", detail: "Aqua and blue on deep teal"),
        Choice(label: "Violet", iconName: "AppIcon-Violet", detail: "Lavender and pink on deep purple"),
        Choice(label: "Sunset", iconName: "AppIcon-Sunset", detail: "Amber and rose at dusk"),
        Choice(label: "Peach", iconName: "AppIcon-Peach", detail: "Warm peach and rose"),
        Choice(label: "Sorbet", iconName: "AppIcon-Sorbet", detail: "Mint and pink pastels"),
        Choice(label: "Paper", iconName: "AppIcon-Paper", detail: "Ink and vermilion on warm paper"),
        Choice(label: "Graphite", iconName: "AppIcon-Graphite", detail: "Monochrome gray"),
        Choice(label: "Noir", iconName: "AppIcon-Noir", detail: "High contrast, black and white"),
    ]

    private static let iconSize: CGFloat = 60
    private static let iconShape = RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var current = UIApplication.shared.alternateIconName
    @State private var error: String?
    @State private var gridWidth: CGFloat = 0

    /// 12 alternates divide evenly into 3, 4 or 6 columns, so no row is left with an orphan.
    private var columnCount: Int {
        let tile: CGFloat = 68 + 12
        return gridWidth >= tile * 6 ? 6 : gridWidth >= tile * 4 ? 4 : 3
    }

    var body: some View {
        Section {
            Group {
                // The primary icon gets its own row; the alternates fill an even grid below it.
                if let primary = Self.choices.first {
                    choiceButton(primary) { featured(primary) }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columnCount), spacing: 16) {
                    ForEach(Self.choices.dropFirst()) { choice in
                        choiceButton(choice) { tile(choice) }
                    }
                }
                .padding(.vertical, 8)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
            }
            .disabled(!UIApplication.shared.supportsAlternateIcons)
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: current)
        } header: {
            Text("App icon")
        } footer: {
            if let error { Text(error) }
        }
        .sensoryFeedback(.selection, trigger: current)
    }

    private func choiceButton(_ choice: Choice, @ViewBuilder label: () -> some View) -> some View {
        Button { select(choice) } label: { label() }
            .buttonStyle(TileStyle())
            .accessibilityLabel(choice.label)
            .accessibilityValue(choice.detail)
            .accessibilityAddTraits(choice.iconName == current ? .isSelected : [])
    }

    private func featured(_ choice: Choice) -> some View {
        let selected = choice.iconName == current
        return HStack(spacing: 14) {
            icon(choice, selected: selected)
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.label).font(.body.weight(selected ? .semibold : .regular)).foregroundStyle(.primary)
                Text(choice.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }

    private func tile(_ choice: Choice) -> some View {
        let selected = choice.iconName == current
        return VStack(spacing: 7) {
            icon(choice, selected: selected)
            Text(choice.label)
                .font(.caption.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
    }

    private func icon(_ choice: Choice, selected: Bool) -> some View {
        Group {
            if let image = Self.preview(choice.id) {
                Image(uiImage: image).resizable().interpolation(.high)
            } else {
                Theme.hero
            }
        }
        .frame(width: Self.iconSize, height: Self.iconSize)
        .clipShape(Self.iconShape)
        // Hairline keeps the light icons (Paper, Sorbet) from melting into a light list.
        .overlay { Self.iconShape.strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
        .padding(4)
        .overlay {
            RoundedRectangle(cornerRadius: (Self.iconSize + 8) * 0.225 + 1, style: .continuous)
                .strokeBorder(Theme.brand, lineWidth: 2.5)
                .opacity(selected ? 1 : 0)
        }
        .overlay(alignment: .bottomTrailing) {
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Theme.brand)
                    .background(Circle().fill(Color(uiColor: .secondarySystemGroupedBackground)).padding(-2))
                    .offset(x: 3, y: 3)
                    .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
            }
        }
    }

    private func select(_ choice: Choice) {
        guard choice.iconName != current else { return }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(choice.iconName)
                current = choice.iconName
                error = nil
            } catch {
                self.error = "Couldn't change the icon: \(error.localizedDescription)"
            }
        }
    }

    /// Previews written by `Tools/make-icon.swift` to Delight/IconPreviews.
    private static func preview(_ name: String) -> UIImage? { UIImage(named: "\(name)-Preview") }
}

/// Press feedback for icon tiles; a dim instead of a springy squash when Reduce Motion is on.
private struct TileStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.6 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}
