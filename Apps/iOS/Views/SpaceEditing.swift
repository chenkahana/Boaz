import FolioKit
import SwiftUI

/// Space management on iPhone: what the space title menu and the home menu offer, and the editor sheet they open.
/// Writes go straight to the store; the app model picks them up through its sidebar observation.
@Observable final class SpaceEditing {
    enum Request: Identifiable {
        case create(profileID: String)
        case edit(Space)
        var id: String {
            switch self {
            case .create: "create"
            case .edit(let space): space.id
            }
        }
    }

    var request: Request?
}

extension EnvironmentValues {
    @Entry var spaceEditing = SpaceEditing()
}

/// Presents the space editor for whatever `SpaceEditing` asks for. Attach once, high in the hierarchy.
struct SpaceEditorPresenter: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var editing = SpaceEditing()

    func body(content: Content) -> some View {
        @Bindable var editing = editing
        content
            .environment(\.spaceEditing, editing)
            .sheet(item: $editing.request) { request in
                switch request {
                case .create(let profileID):
                    SpaceEditor(mode: .create) { title, icon, palette in
                        guard let space = try? model.store?.createSpace(title: title, icon: icon,
                                                                        palette: palette ?? .defaultPalette,
                                                                        profileID: profileID) else { return }
                        // The new space shows once the sidebar observation delivers it.
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(150))
                            withAnimation(.smooth) { model.currentSpaceID = space.id }
                        }
                    }
                case .edit(let space):
                    SpaceEditor(mode: .edit(space, canDelete: model.spaces.count > 1)) { title, icon, palette in
                        try? model.store?.updateSpace(space.id, title: title, icon: icon, palette: palette)
                    } onDelete: {
                        if let other = model.spaces.first(where: { $0.id != space.id }) {
                            model.currentSpaceID = other.id
                        }
                        try? model.store?.deleteSpace(space.id)
                    }
                }
            }
    }
}

extension View {
    func spaceEditorPresenter() -> some View { modifier(SpaceEditorPresenter()) }
}

/// The space's name and icon as a menu: switch spaces, add one, edit or reorder this one.
struct SpaceTitleMenu<Label: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.spaceEditing) private var editing
    let space: Space
    @ViewBuilder var label: () -> Label

    var body: some View {
        Menu {
            Section {
                ForEach(model.spaces) { other in
                    Button {
                        withAnimation(.smooth) { model.currentSpaceID = other.id }
                    } label: {
                        if other.id == space.id {
                            SwiftUI.Label("\(other.icon ?? "✦")  \(other.title)", systemImage: "checkmark")
                        } else {
                            Text("\(other.icon ?? "✦")  \(other.title)")
                        }
                    }
                }
            }
            Section {
                Button("Edit Space…", systemImage: "paintpalette") { editing.request = .edit(space) }
                Button("New Space…", systemImage: "plus") { editing.request = .create(profileID: space.profileID) }
            }
            if model.spaces.count > 1, let index = model.spaces.firstIndex(where: { $0.id == space.id }) {
                Section {
                    Button("Move Left", systemImage: "arrow.left") { move(to: index - 1) }.disabled(index == 0)
                    Button("Move Right", systemImage: "arrow.right") { move(to: index + 1) }
                        .disabled(index == model.spaces.count - 1)
                }
            }
        } label: {
            label()
        }
        .menuOrder(.fixed)
        .accessibilityHint("Switch, add or edit spaces")
    }

    private func move(to index: Int) {
        withAnimation(.smooth) { try? model.store?.moveSpace(space.id, to: index) }
    }
}
