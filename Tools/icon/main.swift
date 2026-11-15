import AppKit

// Entry point; see Tools/make-icon.swift for what it writes.

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let assets = root.appendingPathComponent("Apps/Shared/Resources/Assets.xcassets")
let previews = root.appendingPathComponent("Apps/iOS/Delight/IconPreviews")
let macIcons = root.appendingPathComponent("Apps/macOS/Resources/AppIcons")
let docs = root.appendingPathComponent("docs/assets")
let fm = FileManager.default

func clear(_ dir: URL, matching remove: (String) -> Bool) {
    for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] where remove(name) {
        try? fm.removeItem(at: dir.appendingPathComponent(name))
    }
}

// Start clean: alternates that were renamed or dropped must not linger.
clear(assets) { $0.hasPrefix("AppIcon-") && $0.hasSuffix(".appiconset") }
clear(previews) { $0.hasSuffix("-Preview.png") }
clear(macIcons) { $0.hasSuffix(".icns") }

var arts: [(Variant, CGImage)] = []
for v in variants {
    let art = icon(v)
    arts.append((v, art))
    write(scaled(art, to: 180, alpha: false), previews.appendingPathComponent("\(v.assetName)-Preview.png"), opaque: true)
    print("  \(v.id)")
    if v.id == classic.id { continue }
    let dir = assets.appendingPathComponent("\(v.assetName).appiconset")
    write(art, dir.appendingPathComponent("\(v.assetName).png"), opaque: true)
    try! """
    {
      "images" : [
        { "filename" : "\(v.assetName).png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    writeIcns(macIcon(art), macIcons.appendingPathComponent("\(v.assetName).icns"))
}

// Primary set: light, dark and tinted iOS appearances, and the macOS sizes.
let classicArt = arts[0].1
let primaryDir = assets.appendingPathComponent("AppIcon.appiconset")
write(classicArt, primaryDir.appendingPathComponent("AppIcon.png"), opaque: true)
let darkArt = icon(classicDark)
write(darkArt, primaryDir.appendingPathComponent("AppIcon-Dark.png"), opaque: true)
let tintedArt = icon(classicTinted, ground: false)
write(tintedArt, primaryDir.appendingPathComponent("AppIcon-Tinted.png"))
let mac = macIcon(classicArt)
for px in [16, 32, 64, 128, 256, 512, 1024] {
    write(px == 1024 ? mac : scaled(mac, to: px), primaryDir.appendingPathComponent("mac-\(px).png"))
}
print("  primary")

// Artwork.
write(scaled(mac, to: 256), docs.appendingPathComponent("icon.png"))
write(parade(arts), docs.appendingPathComponent("icon-parade.png"), opaque: true)
// The social card's footer keeps the sibling apps' icons from the current card.
let social = docs.appendingPathComponent("social-preview.png")
let family = NSImage(contentsOf: social).map(cgImage)?.cropping(to: CGRect(x: 1030, y: 548, width: 160, height: 72))
let fan = ["Neon", "Salted", "Gold", "Candy"].compactMap { id in arts.first { $0.0.id == id }?.1 }
write(socialPreview(primary: classicArt, fan: fan, family: family), social, opaque: true)
let confetti = ["Neon", "Salted", "Holo", "Candy", "Gold", "Clay", "Ocean"]
    .compactMap { id in arts.first { $0.0.id == id }?.1 }.map { scaled($0, to: 256) }
for scale in [1, 2] {
    write(dmgBackground(scale: scale, confetti: confetti),
          root.appendingPathComponent("Tools/chromium/dmg-background\(scale == 2 ? "@2x" : "").png"), opaque: true)
}
let sheet = arts.map { ($0.0.title, $0.1) } + [("Classic · Dark", darkArt)]
write(contactSheet(sheet), root.appendingPathComponent("build/icon-contact-sheet.png"), opaque: true)
print("wrote \(variants.count) Boaz icons under \(root.path)")
