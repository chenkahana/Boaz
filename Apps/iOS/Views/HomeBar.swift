import BoazKit
import SwiftUI

/// The empty browser's toolbar: search and the menu. Runs down the right-hand rail, or across the bottom.
struct HomeBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.paneIndex) private var pane
    let axis: Axis

    var body: some View {
        if axis == .vertical {
            RailColumn {
                Button(action: search) {
                    RailGlyph(symbol: searchSymbol)
                        .foregroundStyle(.white)
                        .background(Theme.brand.gradient, in: .circle)
                        .padding(2)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Search")
            } bottom: {
                HomeMenu(inDock: true)
            }
        } else {
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    HomeMenu()
                    Button(action: search) {
                        HStack {
                            Image(systemName: model.isIncognito ? "eyeglasses" : "magnifyingglass")
                            Text(model.isIncognito ? "Private search" : "Search or enter address")
                            Spacer()
                            Image(systemName: "plus")
                        }
                        .font(.body.weight(.medium))
                        .padding(.horizontal, 18).padding(.vertical, 14)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
        }
    }

    private var searchSymbol: String { model.isIncognito ? "eyeglasses" : "magnifyingglass" }

    private func search() {
        model.focusPane(pane)
        model.beginSearch(.newTab)
    }
}

/// Library, Incognito and Settings.
struct HomeMenu: View {
    @Environment(AppModel.self) private var model
    var inDock = false

    var body: some View {
        Menu {
            HomeMenuItems()
        } label: {
            if inDock { RailGlyph(symbol: "line.3.horizontal") } else { RailIcon(symbol: "line.3.horizontal", size: 50) }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Menu")
    }
}

struct HomeMenuItems: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        SpaceAIMenuItems()
        Button("Library", systemImage: "archivebox") { model.sheet = .library }
        Button(model.isIncognito ? "Leave Incognito" : "Incognito",
               systemImage: "eyeglasses") { model.setIncognito(!model.isIncognito) }
        Button("Settings", systemImage: "gearshape") { model.sheet = .settings }
    }
}
