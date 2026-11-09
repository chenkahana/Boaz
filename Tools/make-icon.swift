// Boaz Browser app icons: a "BB" ligature. Two heavy monoline B's, the second raised a step, with the first
// B's lower bowl landing exactly on the second B's stem. Each B is its own gradient ribbon, and where they
// cross the colors mix into a third, as overlapping inks would. Soft colored light from each letter spills
// into the background.
//
// Regenerate every icon (run from anywhere; paths resolve from this file's location):
//   swift Tools/make-icon.swift [repo-root]
//
// Writes:
//   Apps/Shared/Resources/Assets.xcassets/AppIcon.appiconset/          AppIcon.png, AppIcon-Dark.png,
//       AppIcon-Tinted.png (iOS 1024) and mac-16 … mac-1024.png (macOS squircle on the Apple grid)
//   Apps/Shared/Resources/Assets.xcassets/AppIcon-<Name>.appiconset/   one 1024 PNG + Contents.json per alternate
//   Apps/iOS/Delight/IconPreviews/AppIcon[-<Name>]-Preview.png         180 px previews for Settings › App Icon
//   docs/assets/icon.png                                                256 px README icon
//   build/icon-contact-sheet.png                                        review sheet: 1024 tiles + 60/29 px rows
import AppKit
import UniformTypeIdentifiers

let size: CGFloat = 1024
let root = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("Apps/Shared/Resources/Assets.xcassets")
let previews = root.appendingPathComponent("Apps/iOS/Delight/IconPreviews")
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func gradient(_ colors: [CGColor]) -> CGGradient {
    let locations = (0..<colors.count).map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
    return CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

func context(_ px: Int, alpha: Bool) -> CGContext {
    CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
              bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
}

struct Palette {
    var background: [UInt32]                 // top-left → bottom-right; empty = transparent (tinted)
    var first: [UInt32]                      // the left B, top-left → bottom-right
    var second: [UInt32]                     // the raised B
    var mix: [UInt32]                        // where they cross
    var glows: (CGFloat, CGFloat) = (0.5, 0.36)   // light each B spills into the background (0 = none)
    var shade: UInt32 = 0x000000             // drop shadow color
    var shadow: CGFloat = 0.5
    var underside: CGFloat = 0.22            // inner shading along the letters' lower edges
    var rim: CGFloat = 0.28                  // inner highlight along their upper edges
    var gloss: CGFloat = 0.12                // sheen over the upper half
    var lift: CGFloat = 0.1                  // soft white light from above the icon
}

/// Boaz: cobalt and coral on night, mixing to plum.
let night: [UInt32] = [0x1E1B44, 0x0E0C22, 0x06050E]
let cobalt: [UInt32] = [0x67A6FF, 0x4870FF, 0x3A2FDA]
let coral: [UInt32] = [0xFFB547, 0xFF6C4A, 0xFF3A7E]
let plum: [UInt32] = [0xF0489C, 0xC236B6, 0x8E2BD0]
let primary = Palette(background: night, first: cobalt, second: coral, mix: plum)
/// iOS dark appearance: the same letters on near-black, with less spill.
let dark = Palette(background: [0x100E1E, 0x08070F, 0x030306], first: cobalt, second: coral, mix: plum,
                   glows: (0.3, 0.2), lift: 0.04)
/// iOS tinted appearance: grayscale letters on transparency; the system supplies the tint.
let tinted = Palette(background: [], first: [0xFFFFFF, 0xE6E6E6], second: [0xCFCFCF, 0xB4B4B4],
                     mix: [0x8E8E8E, 0x7A7A7A], glows: (0, 0), shadow: 0, underside: 0, rim: 0, gloss: 0, lift: 0)

// Order matches the Settings picker (AppIconPicker.swift).
let alternates: [(String, Palette)] = [
    ("Midnight", Palette(background: [0x13204E, 0x0A1030, 0x04071A], first: [0x8CE8FF, 0x45B0FF, 0x2F74FF],
                         second: [0xC4ACFF, 0x9474FF, 0x6A4BF0], mix: [0x6C8CFF, 0x5662F4, 0x4440DA])),
    ("Glass", Palette(background: [0x3B3FD0, 0x23208A, 0x100D3C], first: [0xFFFFFF, 0xE6EBFF],
                      second: [0xFFE9F1, 0xFFC9DC], mix: [0xC9C2FF, 0xA9A0F6], glows: (0.45, 0.45),
                      shade: 0x07052A, underside: 0.14, rim: 0.5, gloss: 0.2)),
    ("Aurora", Palette(background: [0x0F1E3A, 0x08102A, 0x04061A], first: [0x7DFFD0, 0x2EE6A6, 0x12B58A],
                       second: [0xC8A4FF, 0x8F62FF, 0x6A3CF0], mix: [0x46B4FF, 0x3F84FF, 0x3A5CF0])),
    ("Electric", Palette(background: [0x3F86FF, 0x1C44DC, 0x0C1674], first: [0xFFFFFF, 0xE2ECFF],
                         second: [0xFFF27A, 0xFFD23A, 0xFFAE2E], mix: [0x9CF2FF, 0x5CD8FF],
                         glows: (0.4, 0.4), shade: 0x050C4A, gloss: 0.16)),
    ("Tide", Palette(background: [0x0F5E72, 0x093A4C, 0x05202E], first: [0x9AFBE6, 0x42E2C8, 0x14B6AE],
                     second: [0x86D4FF, 0x429EFF, 0x2F6BFF], mix: [0x3ECDEA, 0x28A4E0, 0x1E80D0])),
    ("Violet", Palette(background: [0x2C1666, 0x170B3A, 0x0A0520], first: [0xD2B2FF, 0x9E70FF, 0x7646EE],
                       second: [0xFFA6DA, 0xFF62B4, 0xE6409A], mix: [0xDA6CEA, 0xB64CDC, 0x9234C8])),
    ("Sunset", Palette(background: [0x45124A, 0x220828, 0x100312], first: [0xFFDD72, 0xFFA03E, 0xFF6E3A],
                       second: [0xFF86B0, 0xFF4284, 0xD8306E], mix: [0xFF6466, 0xF2444E, 0xD8303E])),
    ("Peach", Palette(background: [0xFFF3EA, 0xFFE2D4, 0xFFD2C2], first: [0xFFBE86, 0xFF945E, 0xFF7A4E],
                      second: [0xFF9AB6, 0xFF6694, 0xF0487A], mix: [0xFF6E6C, 0xF2525E, 0xE03E50],
                      glows: (0, 0), shade: 0x8A2A30, shadow: 0.24, underside: 0.16, lift: 0)),
    ("Sorbet", Palette(background: [0xFDF0F7, 0xF2ECFF, 0xE6F6F1], first: [0xA2EACF, 0x6CD8B4, 0x3EC29A],
                       second: [0xFFBAD6, 0xFF8EBC, 0xF56AA2], mix: [0xC2A6F4, 0xA488EA, 0x8A6CDC],
                       glows: (0, 0), shade: 0x5A3A8A, shadow: 0.2, underside: 0.14, lift: 0)),
    ("Paper", Palette(background: [0xFFF9EC, 0xFAEED8, 0xF1E2C6], first: [0x45414F, 0x2A2732, 0x18161D],
                      second: [0xFF7A48, 0xF2582E, 0xD8431E], mix: [0x9A3220, 0x7E2618, 0x621C12],
                      glows: (0, 0), shade: 0x5A4220, shadow: 0.24, underside: 0.2, rim: 0.18, lift: 0)),
    ("Graphite", Palette(background: [0x56565E, 0x2C2C32, 0x141418], first: [0xFFFFFF, 0xDCDCE2, 0xC2C2CA],
                         second: [0xB4B4BE, 0x8E8E9A, 0x74747E], mix: [0x6A6A74, 0x56565F, 0x46464E],
                         glows: (0, 0), lift: 0.08)),
    ("Noir", Palette(background: [0x18181A, 0x050505, 0x000000], first: [0xFFFFFF, 0xFFFFFF],
                     second: [0xFFFFFF, 0xFFFFFF], mix: [0x1C1C1E, 0x0A0A0A], glows: (0, 0), shadow: 0,
                     underside: 0, rim: 0, gloss: 0, lift: 0.04)),
]

func stroked(_ path: CGPath, _ width: CGFloat) -> CGPath {
    path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
}

/// Rounds every concave corner to radius `r` (a morphological closing: grow by r, then shrink by r).
func smooth(_ path: CGPath, _ r: CGFloat) -> CGPath {
    let grown = path.union(stroked(path, 2 * r))
    return grown.subtracting(stroked(grown, 2 * r))
}

func moved(_ path: CGPath, _ t: CGAffineTransform) -> CGPath {
    var t = t
    return path.copy(using: &t)!
}

/// A capital B's centreline: stem at x = 0, top at y = 0 (y down), `h` tall. The upper bowl is a little
/// shorter and narrower than the lower one. Returns the path and how far right the lower bowl reaches.
func bCentreline(h: CGFloat) -> (path: CGPath, reach: CGFloat) {
    let waist = (h * 0.47).rounded(), r1 = waist / 2, r2 = (h - waist) / 2
    let a1 = h * 0.3, a2 = a1 + r1 - r2 + h * 0.06
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: a1, y: 0))
    p.addArc(center: CGPoint(x: a1, y: r1), radius: r1, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
    p.addLine(to: CGPoint(x: 0, y: waist)); p.addLine(to: CGPoint(x: a2, y: waist))
    p.addArc(center: CGPoint(x: a2, y: waist + r2), radius: r2, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
    p.addLine(to: CGPoint(x: 0, y: h))
    return (p, a2 + r2)
}

/// The two letters, fitted to the icon: the second B's stem sits on the first B's lower bowl, raised a step.
let mark: (first: CGPath, second: CGPath) = {
    let (line, reach) = bCentreline(h: 500)
    let first = smooth(stroked(line, 120), 16)
    let second = moved(first, CGAffineTransform(translationX: reach, y: -56))
    let box = first.union(second).boundingBoxOfPath, k = 600 / max(box.width, box.height)
    let t = CGAffineTransform(translationX: -box.midX, y: -box.midY).concatenating(CGAffineTransform(scaleX: k, y: k))
        .concatenating(CGAffineTransform(translationX: size / 2, y: size / 2 - 4))   // a hair high: the shadow adds weight below
    return (moved(first, t), moved(second, t))
}()

/// Renders one 1024 icon, full bleed (iOS masks the corners).
func render(_ p: Palette) -> CGImage {
    let ctx = context(Int(size), alpha: p.background.isEmpty)
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    let (first, second) = mark
    let both = first.union(second), overlap = first.intersection(second)

    /// Fills `path` with a diagonal gradient across its own bounds.
    func paint(_ path: CGPath, _ colors: [UInt32]) {
        let box = path.boundingBoxOfPath
        ctx.saveGState(); ctx.addPath(path); ctx.clip()
        ctx.drawLinearGradient(gradient(colors.map { rgb($0) }), start: CGPoint(x: box.minX + box.width * 0.2, y: box.minY),
                               end: CGPoint(x: box.maxX - box.width * 0.2, y: box.maxY),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        ctx.restoreGState()
    }

    if !p.background.isEmpty {
        ctx.drawLinearGradient(gradient(p.background.map { rgb($0) }), start: CGPoint(x: size * 0.25, y: 0),
                               end: CGPoint(x: size * 0.75, y: size),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let top = CGPoint(x: size / 2, y: -size * 0.3)
        ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, p.lift), rgb(0xFFFFFF, 0)]), startCenter: top, startRadius: 0,
                               endCenter: top, endRadius: size, options: [])
        for (letter, colors, alpha, dy) in [(first, p.first, p.glows.0, 60.0), (second, p.second, p.glows.1, -40.0)]
            where alpha > 0 {
            let box = letter.boundingBoxOfPath, c = CGPoint(x: box.midX, y: box.midY + dy)
            let color = colors[colors.count / 2]
            ctx.drawRadialGradient(gradient([rgb(color, alpha), rgb(color, alpha * 0.35), rgb(color, 0)]),
                                   startCenter: c, startRadius: 0, endCenter: c, endRadius: 430, options: [])
        }
    }

    // Drop shadows (offsets are in unflipped device space, so negative is down): a wide soft one and a contact one.
    // The shape is drawn off-canvas and only its shadow lands here.
    if p.shadow > 0 {
        let away: CGFloat = 4000
        for (dy, blur, k) in [(-30.0, 70.0, 1.0), (-6.0, 12.0, 0.6)] as [(CGFloat, CGFloat, CGFloat)] {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: -away, height: dy), blur: blur, color: rgb(p.shade, p.shadow * k))
            ctx.addPath(moved(both, CGAffineTransform(translationX: away, y: 0))); ctx.setFillColor(rgb(0x000000))
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    paint(first, p.first)
    paint(second, p.second)
    paint(overlap, p.mix)
    if p.gloss > 0 {
        for letter in [first, second] {
            let box = letter.boundingBoxOfPath
            ctx.saveGState(); ctx.addPath(letter); ctx.clip()
            ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, p.gloss), rgb(0xFFFFFF, 0)]), start: CGPoint(x: 0, y: box.minY),
                                   end: CGPoint(x: 0, y: box.minY + box.height * 0.5), options: [])
            ctx.restoreGState()
        }
    }
    // Inner shading: shadows cast by everything outside the letters, shifted up (underside) and down (top rim).
    let outside = CGMutablePath()
    outside.addRect(full.insetBy(dx: -200, dy: -200)); outside.addPath(both)
    ctx.saveGState(); ctx.addPath(both); ctx.clip()
    for (dy, blur, color) in [(-14.0, 22.0, rgb(0x000000, p.underside)), (6.0, 8.0, rgb(0xFFFFFF, p.rim))]
        as [(CGFloat, CGFloat, CGColor)] where color.alpha > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: dy), blur: blur, color: color)
        ctx.addPath(outside); ctx.setFillColor(rgb(0x000000)); ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }
    ctx.restoreGState()
    return ctx.makeImage()!
}

/// Continuous-corner squircle (superellipse) filling `rect`.
func squircle(_ rect: CGRect) -> CGPath {
    let path = CGMutablePath(), n: CGFloat = 5, steps = 720
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi, c = cos(t), s = sin(t)
        let point = CGPoint(x: rect.midX + rect.width / 2 * copysign(pow(abs(c), 2 / n), c),
                            y: rect.midY + rect.height / 2 * copysign(pow(abs(s), 2 / n), s))
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

/// The artwork masked to a squircle on transparency; `inset` > 0 puts it on the macOS icon grid with a shadow.
func masked(_ art: CGImage, inset: CGFloat) -> CGImage {
    let ctx = context(Int(size), alpha: true)
    let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: inset, dy: inset)
    let shape = squircle(rect)
    if inset > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.32))
        ctx.addPath(shape); ctx.setFillColor(rgb(0x000000)); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.draw(art, in: rect)
    ctx.addPath(shape); ctx.setLineWidth(4); ctx.setStrokeColor(rgb(0xFFFFFF, 0.14)); ctx.strokePath()   // edge sheen
    ctx.restoreGState()
    return ctx.makeImage()!
}

func scaled(_ image: CGImage, to px: Int, alpha: Bool) -> CGImage {
    let ctx = context(px, alpha: alpha)
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: px, height: px))
    return ctx.makeImage()!
}

func write(_ image: CGImage, _ url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "couldn't write \(url.path)")
}

// Primary set.
let primaryArt = render(primary)
let primaryDir = assets.appendingPathComponent("AppIcon.appiconset")
write(primaryArt, primaryDir.appendingPathComponent("AppIcon.png"))
write(render(dark), primaryDir.appendingPathComponent("AppIcon-Dark.png"))
write(render(tinted), primaryDir.appendingPathComponent("AppIcon-Tinted.png"))
let mac = masked(primaryArt, inset: 100)
for px in [16, 32, 64, 128, 256, 512, 1024] {
    write(px == 1024 ? mac : scaled(mac, to: px, alpha: true), primaryDir.appendingPathComponent("mac-\(px).png"))
}
write(scaled(primaryArt, to: 180, alpha: false), previews.appendingPathComponent("AppIcon-Preview.png"))
write(scaled(masked(primaryArt, inset: 0), to: 256, alpha: true), root.appendingPathComponent("docs/assets/icon.png"))

// Alternates.
var sheet: [(String, CGImage)] = [("Default", primaryArt)]
for (name, palette) in alternates {
    let art = render(palette)
    let dir = assets.appendingPathComponent("AppIcon-\(name).appiconset")
    write(art, dir.appendingPathComponent("AppIcon-\(name).png"))
    try! """
    {
      "images" : [
        { "filename" : "AppIcon-\(name).png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }

    """.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    write(scaled(art, to: 180, alpha: false), previews.appendingPathComponent("AppIcon-\(name)-Preview.png"))
    sheet.append((name, art))
}

/// Review sheet: each icon at 1024, then every icon again at 60 px and 29 px on light and dark grounds.
func contactSheet(_ items: [(String, CGImage)], columns: Int, to path: String) {
    let gap: CGFloat = 96, label: CGFloat = 90, stripHeight: CGFloat = 220
    let rows = (items.count + columns - 1) / columns
    let width = CGFloat(columns) * size + CGFloat(columns + 1) * gap
    let height = CGFloat(rows) * (size + label + gap) + gap + 2 * stripHeight
    let ctx = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.setFillColor(rgb(0xE9E9EE)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    for (i, item) in items.enumerated() {
        let x = gap + CGFloat(i % columns) * (size + gap)
        let y = height - gap - CGFloat(i / columns + 1) * (size + label + gap) + label + gap
        ctx.draw(masked(item.1, inset: 0), in: CGRect(x: x, y: y, width: size, height: size))
        (item.0 as NSString).draw(at: CGPoint(x: x + 8, y: y - 72),
                                  withAttributes: [.font: NSFont.systemFont(ofSize: 52, weight: .semibold),
                                                   .foregroundColor: NSColor(white: 0.2, alpha: 1)])
    }
    for (band, ground) in [(0, 0xF5F5F7), (1, 0x1C1C1E)] as [(Int, UInt32)] {
        let y0 = CGFloat(1 - band) * stripHeight
        ctx.setFillColor(rgb(ground)); ctx.fill(CGRect(x: 0, y: y0, width: width, height: stripHeight))
        for (px, y, spacing) in [(60.0, y0 + 120, 36.0), (29.0, y0 + 40, 24.0)] as [(CGFloat, CGFloat, CGFloat)] {
            for (i, item) in items.enumerated() {
                ctx.draw(scaled(masked(item.1, inset: 0), to: Int(px), alpha: true),
                         in: CGRect(x: gap + CGFloat(i) * (px + spacing) + CGFloat(i / columns) * 48, y: y,
                                    width: px, height: px))
            }
        }
    }
    NSGraphicsContext.current = nil
    write(ctx.makeImage()!, root.appendingPathComponent(path))
}

contactSheet(sheet + [("Dark", render(dark))], columns: 5, to: "build/icon-contact-sheet.png")
print("wrote Boaz icons under \(root.path)")
