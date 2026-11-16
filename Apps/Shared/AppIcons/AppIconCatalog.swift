import SwiftUI

/// The app icon family, rendered by `Tools/make-icon.swift` (keep the ids and order in step with its `variants`).
/// iOS switches with alternate icon names (`AppIcon-<id>` sets); the Mac app loads `AppIcon-<id>.icns`.
struct AppIconChoice: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let caption: String

    /// The alternate icon name, or nil for the primary icon.
    var alternateName: String? { id == Self.classic.id ? nil : "AppIcon-\(id)" }
    /// The 180 px picker preview in Delight/IconPreviews.
    var previewName: String { (alternateName ?? "AppIcon") + "-Preview" }
    var accessibilityIdentifier: String { "control.appIcon.\(id.lowercased())" }

    /// User defaults key holding the chosen id. The Mac app (and its Dock tile plug-in) reads it at launch; on iPhone
    /// it mirrors the system's alternate icon so the rest of the app can show the current icon.
    static let selectionKey = "appIcon"

    static let all: [AppIconChoice] = [
        AppIconChoice(id: "Classic", title: "Classic", caption: "Flat blue knot, light or dark with the system"),
        AppIconChoice(id: "Dark", title: "Dark", caption: "Flat blue knot on black"),
        AppIconChoice(id: "Glossy", title: "Glossy", caption: "The knot in 3D: glossy blue on cream"),
        AppIconChoice(id: "Midnight", title: "Midnight Snack", caption: "The classic, up past bedtime"),
        AppIconChoice(id: "Noir", title: "Film Noir", caption: "Black and white, lit through the blinds"),
        AppIconChoice(id: "Neon", title: "Neon Night", caption: "Open late: pink and cyan glass tubes"),
        AppIconChoice(id: "Wood", title: "Woodshop", caption: "Hand-carved and oiled, grain and all"),
        AppIconChoice(id: "Salted", title: "Fresh Baked", caption: "Golden, glossy and generously salted"),
        AppIconChoice(id: "Chocolate", title: "Choco Dip", caption: "Dipped, drizzled and sprinkled"),
        AppIconChoice(id: "Glass", title: "Glassblower", caption: "Clear glass, fresh from the furnace"),
        AppIconChoice(id: "Chrome", title: "Chrome", caption: "Polished to a mirror shine"),
        AppIconChoice(id: "Gold", title: "24 Karat", caption: "Solid gold on emerald velvet"),
        AppIconChoice(id: "Marble", title: "Museum Piece", caption: "Carrara marble, veined with gold"),
        AppIconChoice(id: "Clay", title: "Claymation", caption: "Squished by hand, one pastel at a time"),
        AppIconChoice(id: "Sunset", title: "Golden Hour", caption: "Warm light over a lilac sea"),
        AppIconChoice(id: "Ocean", title: "Deep Sea", caption: "Aqua, caustics and a few bubbles"),
        AppIconChoice(id: "Matcha", title: "Matcha Latte", caption: "Whisked green tea on oat-milk foam"),
        AppIconChoice(id: "Holo", title: "Holo Foil", caption: "A rare trading card, shimmering every color"),
        AppIconChoice(id: "Candy", title: "Candy Cane", caption: "Peppermint stripes, all twisted up"),
        AppIconChoice(id: "Graphite", title: "Graphite", caption: "Quiet charcoal on brushed silver"),
        AppIconChoice(id: "Bubblegum", title: "Bubblegum", caption: "Pink, chewy and about to pop"),
    ]

    static var classic: AppIconChoice { all[0] }

    static func with(id: String?) -> AppIconChoice { all.first { $0.id == id } ?? all[0] }
    static func with(alternateName: String?) -> AppIconChoice { all.first { $0.alternateName == alternateName } ?? all[0] }
}

/// The icon the app currently wears: the chosen alternate on iPhone, the Dock icon on the Mac.
struct CurrentAppIcon: View {
    var size: CGFloat = 64
    @AppStorage(AppIconChoice.selectionKey) private var selection = AppIconChoice.classic.id

    var body: some View {
        image
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            #if os(iOS)
            // The iOS artwork is full-bleed; give it the home-screen shape. The Mac icon arrives masked.
            .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
            #endif
            .id(selection)
            .accessibilityHidden(true)
    }

    private var image: Image {
        #if os(macOS)
        Image(nsImage: NSApplication.shared.applicationIconImage)
        #else
        UIImage(named: AppIconChoice.with(id: selection).previewName).map { Image(uiImage: $0) }
            ?? Image(systemName: "app")
        #endif
    }
}
