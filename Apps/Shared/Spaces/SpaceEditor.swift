import FolioKit
import SwiftUI

/// Creates or edits a space: name, emoji and color, with a live preview. Shared by the iPhone and Mac apps.
struct SpaceEditor: View {
    enum Mode { case create, edit(Space, canDelete: Bool) }

    let mode: Mode
    /// Saves the space; a nil palette keeps its current theme (one imported from Arc, say).
    let onSave: (_ title: String, _ icon: String?, _ palette: SpacePalette?) -> Void
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var title: String
    @State private var icon: String
    @State private var palette: SpacePalette?
    @State private var confirmDelete = false
    @State private var deleted = false
    @FocusState private var nameFocused: Bool

    static let suggestedIcons = ["🏡", "💼", "📚", "✈️", "🎨", "💻", "🧪", "🎵", "🛒", "🏋️", "🍳", "🎮",
                                 "📰", "💡", "🌱", "⚽️", "🎬", "🧘", "💰", "🗂️", "🚀", "🎓", "🧳", "🐾",
                                 "☕️", "❤️", "⭐️", "✦"]

    init(mode: Mode, onSave: @escaping (String, String?, SpacePalette?) -> Void, onDelete: (() -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        switch mode {
        case .create:
            _title = State(initialValue: "")
            _icon = State(initialValue: "✦")
            _palette = State(initialValue: SpacePalette.defaultPalette)
        case .edit(let space, _):
            _title = State(initialValue: space.title)
            _icon = State(initialValue: space.icon ?? "✦")
            _palette = State(initialValue: SpacePalette.matching(space.themeJSON))
        }
    }

    private var isCreating: Bool { if case .create = mode { true } else { false } }
    private var editing: Space? { if case .edit(let space, _) = mode { space } else { nil } }
    private var canDelete: Bool { if case .edit(_, let canDelete) = mode { canDelete && onDelete != nil } else { false } }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            form
            Divider()
            HStack {
                if canDelete { deleteButton }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(isCreating ? "Create Space" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedTitle.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 460, height: 560)
        #else
        NavigationStack {
            form
                .navigationTitle(isCreating ? "New Space" : "Edit Space")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isCreating ? "Create" : "Save", action: save).disabled(trimmedTitle.isEmpty)
                    }
                }
        }
        .presentationDetents([.large])
        #endif
    }

    private var form: some View {
        Form {
            Section { preview.listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }

            Section("Name") {
                TextField("Name", text: $title, prompt: Text("Work, Home, Reading…"))
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { if !trimmedTitle.isEmpty { save() } }
            }

            Section("Icon") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 6)], spacing: 6) {
                    ForEach(Self.suggestedIcons, id: \.self) { emoji in
                        Button { icon = emoji } label: {
                            Text(emoji).font(.title2)
                                .frame(width: 44, height: 44)
                                .background(icon == emoji ? Color.accentColor.opacity(0.2) : .clear, in: .rect(cornerRadius: 10))
                                .overlay {
                                    if icon == emoji {
                                        RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2)
                                    }
                                }
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(emoji == "✦" ? "Sparkle" : emoji)
                        .accessibilityAddTraits(icon == emoji ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
                TextField("Or type any emoji", text: Binding(
                    get: { Self.suggestedIcons.contains(icon) ? "" : icon },
                    set: { if let first = $0.trimmingCharacters(in: .whitespaces).first { icon = String(first) } }))
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 10)], spacing: 10) {
                    ForEach(SpacePalette.all) { option in
                        Button { palette = option } label: { swatch(option) }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.name)
                            .accessibilityAddTraits(palette == option ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Color")
            } footer: {
                if palette == nil, editing != nil {
                    Text("This space keeps its current colors until you pick one.")
                }
            }

            #if os(iOS)
            if canDelete {
                Section { deleteButton.frame(maxWidth: .infinity) }
            }
            #endif
        }
        .formStyle(.grouped)
        .onAppear { if isCreating { nameFocused = true } }
    }

    /// The confirmation hangs off the button itself: on iOS 26 and later a dialog anchors to its source view.
    private var deleteButton: some View {
        Button("Delete Space…", role: .destructive) { confirmDelete = true }
            .confirmationDialog("Delete \"\(editing?.title ?? "")\"?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Space", role: .destructive) {
                    onDelete?()
                    deleted = true
                }
            } message: {
                Text("Its tabs move to the Archive, on all your devices.")
            }
            // Dismissing from the dialog's own action would close only the dialog, so the editor closes after it.
            .onChange(of: confirmDelete) { _, showing in if !showing, deleted { dismiss() } }
    }

    /// The space as it will look: its gradient, icon and name.
    private var preview: some View {
        let style = previewStyle
        return HStack(spacing: 12) {
            Text(icon).font(.system(size: 34))
            Text(trimmedTitle.isEmpty ? "New Space" : trimmedTitle)
                .font(.system(.title, design: .rounded, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(style.foreground)
                .opacity(trimmedTitle.isEmpty ? 0.45 : 1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(height: 96)
        .background(style.gradient, in: .rect(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview: \(icon) \(trimmedTitle)")
        .animation(.smooth, value: palette)
    }

    private var previewStyle: SpaceStyle {
        var space = editing ?? Space(id: "preview", title: "", profileID: "", position: 0)
        if let palette { space.themeJSON = palette.themeJSON }
        return SpaceStyle(space, scheme: scheme)
    }

    private func swatch(_ option: SpacePalette) -> some View {
        let selected = palette == option
        let light = option.lightRGB, accent = option.accentRGB
        return ZStack {
            Circle().fill(Color(red: light.red, green: light.green, blue: light.blue))
            Circle().fill(Color(red: accent.red, green: accent.green, blue: accent.blue)).padding(12)
        }
        .frame(width: 40, height: 40)
        .overlay { Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
        .padding(3)
        .overlay { if selected { Circle().strokeBorder(Color.accentColor, lineWidth: 2.5) } }
        .frame(width: 48, height: 48)
        .contentShape(.circle)
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        onSave(trimmedTitle, icon, palette)
        dismiss()
    }
}
