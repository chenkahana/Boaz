import SwiftUI
import UIKit

/// Settings section that switches between the pretzel family (`AppIcon-*` sets, rendered by `Tools/make-icon.swift`;
/// names and captions in `AppIconChoice`).
struct AppIconPicker: View {
    private typealias Choice = AppIconChoice
    private static let choices = AppIconChoice.all

    private static let iconSize: CGFloat = 60
    private static let iconShape = RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous)

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var current = UIApplication.shared.alternateIconName
    @State private var error: String?
    @State private var gridWidth: CGFloat = 0
    @AppStorage(AppIconChoice.selectionKey) private var selection = AppIconChoice.classic.id

    /// 18 alternates divide evenly into 3 or 6 columns, so no row is left with an orphan.
    private var columnCount: Int {
        let tile: CGFloat = 68 + 12
        return gridWidth >= tile * 6 ? 6 : 3
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
            Text("App Icon")
        } footer: {
            if let error { Text(error) }
        }
        .sensoryFeedback(.selection, trigger: current)
        .onAppear { selection = AppIconChoice.with(alternateName: current).id }
    }

    private func choiceButton(_ choice: Choice, @ViewBuilder label: () -> some View) -> some View {
        Button { select(choice) } label: { label() }
            .buttonStyle(TileStyle())
            .accessibilityLabel(choice.title)
            .accessibilityValue(choice.caption)
            .accessibilityIdentifier(choice.accessibilityIdentifier)
            .accessibilityAddTraits(choice.alternateName == current ? .isSelected : [])
    }

    private func featured(_ choice: Choice) -> some View {
        let selected = choice.alternateName == current
        return HStack(spacing: 14) {
            icon(choice, selected: selected)
            VStack(alignment: .leading, spacing: 2) {
                Text(choice.title).font(.body.weight(selected ? .semibold : .regular)).foregroundStyle(.primary)
                Text(choice.caption).font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(.rect)
    }

    private func tile(_ choice: Choice) -> some View {
        let selected = choice.alternateName == current
        return VStack(spacing: 7) {
            icon(choice, selected: selected)
            Text(choice.title)
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
            if let image = UIImage(named: choice.previewName) {
                Image(uiImage: image).resizable().interpolation(.high)
            } else {
                Theme.hero
            }
        }
        .frame(width: Self.iconSize, height: Self.iconSize)
        .clipShape(Self.iconShape)
        // Hairline keeps the light icons (Classic, Holo Foil) from melting into a light list.
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
        guard choice.alternateName != current else { return }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(choice.alternateName)
                current = choice.alternateName
                selection = choice.id
                error = nil
            } catch {
                self.error = "Couldn't change the icon: \(error.localizedDescription)"
            }
        }
    }
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
