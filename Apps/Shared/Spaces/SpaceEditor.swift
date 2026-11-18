import BoazKit
import SwiftUI

/// Creates or edits a space: name, emoji and color, with a live preview. Shared by the iPhone and Mac apps; on the
/// Mac it is Customize Space, where Arc's theme color picker edits the colors, appearance, texture and transparency.
struct SpaceEditor: View {
    enum Mode { case create, edit(Space, canDelete: Bool) }

    let mode: Mode
    /// Saves the space; a nil theme keeps its current one (one imported from Arc, say).
    let onSave: (_ title: String, _ icon: String?, _ themeJSON: Data?) -> Void
    var onDelete: (() -> Void)?
    /// The theme as edited so far, to show on the space while the editor is open (Mac); nil when it closes.
    var onPreview: ((Data?) -> Void)?
    /// What deleting takes with it, for the confirmation.
    var deleteMessage = "Its tabs move to the Archive, on all your devices."

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @State private var title: String
    @State private var icon: String
    @State private var palette: SpacePalette?
    /// The theme the edits are written over (Mac): the space's own, or the palette picked last.
    @State private var base: Data?
    /// The theme's customizable parts as they will be saved (Mac).
    @State private var options: SpaceThemeOptions
    @State private var confirmDelete = false
    @State private var deleted = false
    @FocusState private var nameFocused: Bool

    static let suggestedIcons = ["🏡", "💼", "📚", "✈️", "🎨", "💻", "🧪", "🎵", "🛒", "🏋️", "🍳", "🎮",
                                 "📰", "💡", "🌱", "⚽️", "🎬", "🧘", "💰", "🗂️", "🚀", "🎓", "🧳", "🐾",
                                 "☕️", "❤️", "⭐️", "✦"]

    init(mode: Mode, deleteMessage: String? = nil, onSave: @escaping (String, String?, Data?) -> Void,
         onDelete: (() -> Void)? = nil, onPreview: ((Data?) -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        self.onPreview = onPreview
        if let deleteMessage { self.deleteMessage = deleteMessage }
        switch mode {
        case .create:
            _title = State(initialValue: "")
            _icon = State(initialValue: "✦")
            _palette = State(initialValue: SpacePalette.defaultPalette)
            _base = State(initialValue: SpacePalette.defaultPalette.themeJSON)
            _options = State(initialValue: SpaceThemeOptions(themeJSON: SpacePalette.defaultPalette.themeJSON))
        case .edit(let space, _):
            _title = State(initialValue: space.title)
            _icon = State(initialValue: space.icon ?? "✦")
            _palette = State(initialValue: SpacePalette.matching(space.themeJSON))
            _base = State(initialValue: space.themeJSON)
            _options = State(initialValue: SpaceThemeOptions(themeJSON: space.themeJSON))
        }
    }

    private var isCreating: Bool { if case .create = mode { true } else { false } }
    private var editing: Space? { if case .edit(let space, _) = mode { space } else { nil } }
    private var canDelete: Bool { if case .edit(_, let canDelete) = mode { canDelete && onDelete != nil } else { false } }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The theme to save; nil keeps the space's.
    private var themeJSON: Data? {
        #if os(macOS)
        let json = options == SpaceThemeOptions(themeJSON: base) ? base : options.applied(to: base)
        return json == editing?.themeJSON ? nil : json
        #else
        palette?.themeJSON
        #endif
    }

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
        .frame(width: 480, height: 680)
        .onChange(of: options) { onPreview?(options.applied(to: base)) }
        .onDisappear { onPreview?(nil) }
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
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Icons")
                TextField("Or type any emoji", text: Binding(
                    get: { Self.suggestedIcons.contains(icon) ? "" : icon },
                    set: { if let first = $0.trimmingCharacters(in: .whitespaces).first { icon = String(first) } }))
                    .accessibilityLabel("Or type any emoji")
            }

            #if os(macOS)
            Section("Color") { ThemeColorPicker(options: $options).padding(.vertical, 6) }
            #else
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
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Colors")
            } header: {
                Text("Color")
            } footer: {
                if palette == nil, editing != nil {
                    Text("This space keeps its current colors until you pick one.")
                }
            }

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
                Text(deleteMessage)
            }
            // Dismissing from the dialog's own action would close only the dialog, so the editor closes after it.
            .onChange(of: confirmDelete) { _, showing in if !showing, deleted { dismiss() } }
    }

    /// The space as it will look: its gradient, icon and name.
    private var preview: some View {
        #if os(macOS)
        // Light and Dark side by side, unless the space keeps to one.
        let schemes: [ColorScheme] = switch options.appearance {
        case .system: [.light, .dark]
        case .light: [.light]
        case .dark: [.dark]
        }
        return HStack(spacing: 10) {
            ForEach(schemes, id: \.self) { previewCard(scheme: $0) }
        }
        // A picture of the space, not text to read off its gradient.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview: \(icon) \(trimmedTitle)")
        .accessibilityAddTraits(.isImage)
        .animation(.smooth, value: options)
        #else
        let style = previewStyle(scheme: scheme)
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
        #endif
    }

    private func previewStyle(scheme: ColorScheme) -> SpaceStyle {
        var space = editing ?? Space(id: "preview", title: "", profileID: "", position: 0)
        #if os(macOS)
        space.themeJSON = options.applied(to: base)
        #else
        if let palette { space.themeJSON = palette.themeJSON }
        #endif
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
        onSave(trimmedTitle, icon, themeJSON)
        dismiss()
    }
}

#if os(macOS)
extension SpaceEditor {
    /// A small window in one appearance: the backdrop with its texture, the space's name and a selected row.
    fileprivate func previewCard(scheme: ColorScheme) -> some View {
        let style = previewStyle(scheme: scheme)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(icon).font(.system(size: 15))
                Text(trimmedTitle.isEmpty ? "New Space" : trimmedTitle).font(SidebarStyle.titleFont()).lineLimit(1)
            }
            .frame(height: SidebarStyle.rowHeight)
            Text("Selected Tab")
                .font(SidebarStyle.rowFont(selected: true))
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: SidebarStyle.rowHeight, alignment: .leading)
                .background(SidebarStyle.selection(), in: .rect(cornerRadius: Radius.row, style: .continuous))
            Text("Tab").font(SidebarStyle.rowFont()).padding(.horizontal, 8).frame(height: SidebarStyle.rowHeight)
        }
        .foregroundStyle(style.foreground)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background { SpaceBackdrop(style: style, streakRadius: 220) }
        .environment(\.colorScheme, style.dark ? .dark : .light)
        .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(.primary.opacity(0.1)) }
    }
}
#endif
