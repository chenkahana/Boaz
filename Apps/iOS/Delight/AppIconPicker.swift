import SwiftUI
import UIKit

/// Settings section that switches between the primary icon and the palette alternates
/// (`AppIcon-*` sets, rendered by `Tools/make-icon.swift`).
struct AppIconPicker: View {
    private struct Choice: Identifiable {
        let label: String
        let iconName: String?
        var id: String { iconName ?? "AppIcon" }
    }

    private static let choices = [
        Choice(label: "Folio", iconName: nil),
        Choice(label: "Peach", iconName: "AppIcon-Peach"),
        Choice(label: "Electric", iconName: "AppIcon-Electric"),
        Choice(label: "Violet", iconName: "AppIcon-Violet"),
        Choice(label: "Midnight", iconName: "AppIcon-Midnight"),
    ]

    @State private var current = UIApplication.shared.alternateIconName
    @State private var error: String?

    var body: some View {
        Section {
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(Self.choices) { choice in
                        Button { select(choice) } label: { tile(choice) }
                            .buttonStyle(PressableStyle())
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .disabled(!UIApplication.shared.supportsAlternateIcons)
        } header: {
            Text("App icon")
        } footer: {
            if let error { Text(error) }
        }
        .sensoryFeedback(.selection, trigger: current)
    }

    private func tile(_ choice: Choice) -> some View {
        let selected = choice.iconName == current
        return VStack(spacing: 6) {
            Group {
                if let image = Self.preview(choice.id) {
                    Image(uiImage: image).resizable()
                } else {
                    RoundedRectangle(cornerRadius: 14).fill(Theme.hero)
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .strokeBorder(selected ? Theme.brand : .clear, lineWidth: 2.5)
                    .padding(-4)
            }
            Text(choice.label).font(.caption).foregroundStyle(selected ? .primary : .secondary)
        }
        .padding(4)
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
