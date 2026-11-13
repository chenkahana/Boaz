// Boaz Browser app icons: "BB" in orbit. Two heavy italic B's form one ligature (the first B's lower bowl lands
// on the raised second B's stem, and where they cross the colors mix as overlapping inks would). A crescent
// ring, thick at the lower right and tapering to a point at the upper left, circles them like a planet's
// orbit: it passes in front of the first B's foot and behind the second B, so the letters sit inside it.
//
// Regenerate every icon (run from anywhere; paths resolve from this file's location):
//   swift Tools/make-icon.swift [repo-root]
//
// Writes:
//   Apps/Shared/Resources/Assets.xcassets/AppIcon.appiconset/          AppIcon.png, AppIcon-Dark.png,
//       AppIcon-Tinted.png (iOS 1024) and mac-16 … mac-1024.png (macOS squircle on the Apple grid)
//   Apps/Shared/Resources/Assets.xcassets/AppIcon-<Name>.appiconset/   one 1024 PNG + Contents.json per alternate
//   Apps/iOS/Delight/IconPreviews/AppIcon[-<Name>]-Preview.png         180 px previews for Settings › App Icon
//   docs/assets/icon.png                                                256 px README icon (the macOS grid version)
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
    var ring: [UInt32]                       // the orbit, tail → thick end
    var glow: CGFloat = 0                    // light each B spills into the background
    var shade: UInt32 = 0x1A2050             // drop shadow color
    var shadow: CGFloat = 0.3
    var underside: CGFloat = 0.2             // inner shading along lower edges
    var rim: CGFloat = 0.32                  // inner highlight along upper edges
    var gloss: CGFloat = 0.12                // sheen over the letters' upper half
    var lift: CGFloat = 0.1                  // soft white light from above the icon
    var knockout: CGFloat = 0                // flat palettes: a background-colored cut where ring and letters meet
}

let paper: [UInt32] = [0xFFFFFF, 0xF2F3F8, 0xE6E8F0]
let night: [UInt32] = [0x1E1B44, 0x0E0C22, 0x06050E]
let cobalt: [UInt32] = [0x6FB0FF, 0x4870FF, 0x3A2FDA]
let coral: [UInt32] = [0xFFB547, 0xFF6C4A, 0xFF3A7E]
let plum: [UInt32] = [0xF0489C, 0xC236B6, 0x8E2BD0]
let sky: [UInt32] = [0x9BE4FF, 0x3FA0FF, 0x2448E8]

/// Boaz: cobalt and coral letters in a sky-blue orbit, on white.
let primary = Palette(background: paper, first: cobalt, second: coral, mix: plum, ring: sky)
/// iOS dark appearance: the same mark on night, with the letters' light spilling around them.
let dark = Palette(background: night, first: cobalt, second: coral, mix: plum, ring: sky, glow: 0.3,
                   shade: 0x000000, shadow: 0.55)
/// iOS tinted appearance: grayscale on transparency; the system supplies the tint.
let tinted = Palette(background: [], first: [0xFFFFFF, 0xE6E6E6], second: [0xCFCFCF, 0xB4B4B4],
                     mix: [0x8E8E8E, 0x7A7A7A], ring: [0xF2F2F2, 0xDADADA], shadow: 0, underside: 0, rim: 0,
                     gloss: 0, lift: 0)

// Order matches the Settings picker (AppIconPicker.swift).
let alternates: [(String, Palette)] = [
    ("Midnight", Palette(background: [0x13204E, 0x0A1030, 0x04071A], first: [0x8CE8FF, 0x45B0FF, 0x2F74FF],
                         second: [0xC4ACFF, 0x9474FF, 0x6A4BF0], mix: [0x6C8CFF, 0x5662F4, 0x4440DA],
                         ring: [0xFFFFFF, 0xD6E4FF, 0x9EB6FF], glow: 0.3, shade: 0x000000, shadow: 0.55)),
    ("Glass", Palette(background: [0x3B3FD0, 0x23208A, 0x100D3C], first: [0xFFFFFF, 0xE6EBFF],
                      second: [0xFFE9F1, 0xFFC9DC], mix: [0xC9C2FF, 0xA9A0F6], ring: [0x9CF0FF, 0x6FC4FF, 0x8A8CFF],
                      shade: 0x07052A, shadow: 0.45, underside: 0.14, rim: 0.5, gloss: 0.2)),
    ("Aurora", Palette(background: [0x0F1E3A, 0x08102A, 0x04061A], first: [0x7DFFD0, 0x2EE6A6, 0x12B58A],
                       second: [0xC8A4FF, 0x8F62FF, 0x6A3CF0], mix: [0x46B4FF, 0x3F84FF, 0x3A5CF0],
                       ring: [0xB8FFF0, 0x5CF0D0, 0x2EC8E8], glow: 0.3, shade: 0x000000, shadow: 0.55)),
    ("Electric", Palette(background: [0x4F8BFF, 0x2D4FE6, 0x1A2AA8], first: [0xFFFFFF, 0xE8EEFF],
                         second: [0xFFFFFF, 0xE8EEFF], mix: [0xC9D6FF, 0xAFC0FF], ring: [0xFFE27A, 0xFFAE3A, 0xFF6A4A],
                         shade: 0x0A1460, shadow: 0.45)),
    ("Tide", Palette(background: [0x0F5E72, 0x093A4C, 0x05202E], first: [0x9AFBE6, 0x42E2C8, 0x14B6AE],
                     second: [0x86D4FF, 0x429EFF, 0x2F6BFF], mix: [0x3ECDEA, 0x28A4E0, 0x1E80D0],
                     ring: [0xFFFFFF, 0xD8FAFF, 0xA6E8F4], glow: 0.25, shade: 0x00141C, shadow: 0.5)),
    ("Violet", Palette(background: [0x2C1666, 0x170B3A, 0x0A0520], first: [0xD2B2FF, 0x9E70FF, 0x7646EE],
                       second: [0xFFA6DA, 0xFF62B4, 0xE6409A], mix: [0xDA6CEA, 0xB64CDC, 0x9234C8],
                       ring: [0xFFD36A, 0xFF8A4A, 0xFF3A7E], glow: 0.3, shade: 0x000000, shadow: 0.55)),
    ("Sunset", Palette(background: night, first: cobalt, second: [0xC49CFF, 0x8F62FF, 0x6A3CF0],
                       mix: [0x7A7CFF, 0x5A55F0], ring: [0xFFD36A, 0xFF8A4A, 0xFF3A7E], glow: 0.3,
                       shade: 0x000000, shadow: 0.55)),
    ("Peach", Palette(background: [0xFFF3EA, 0xFFE2D4, 0xFFD2C2], first: [0xFFBE86, 0xFF945E, 0xFF7A4E],
                      second: [0xFF9AB6, 0xFF6694, 0xF0487A], mix: [0xFF6E6C, 0xF2525E, 0xE03E50],
                      ring: [0xFFD8A8, 0xFFA06A, 0xF06A5A], shade: 0x8A2A30, shadow: 0.24, underside: 0.16, lift: 0)),
    ("Sorbet", Palette(background: [0xFDF0F7, 0xF2ECFF, 0xE6F6F1], first: [0xA2EACF, 0x6CD8B4, 0x3EC29A],
                       second: [0xFFBAD6, 0xFF8EBC, 0xF56AA2], mix: [0xC2A6F4, 0xA488EA, 0x8A6CDC],
                       ring: [0xD6C8FF, 0xB09CF4, 0x8E78E8], shade: 0x5A3A8A, shadow: 0.2, underside: 0.14, lift: 0)),
    ("Paper", Palette(background: [0xFFF9EC, 0xFAEED8, 0xF1E2C6], first: [0x45414F, 0x2A2732, 0x18161D],
                      second: [0x45414F, 0x2A2732, 0x18161D], mix: [0x6A6676, 0x54505E],
                      ring: [0xFFA070, 0xF2582E, 0xD8431E], shade: 0x5A4220, shadow: 0.24, rim: 0.18, lift: 0)),
    ("Graphite", Palette(background: [0x56565E, 0x2C2C32, 0x141418], first: [0xFFFFFF, 0xDCDCE2, 0xC2C2CA],
                         second: [0xB4B4BE, 0x8E8E9A, 0x74747E], mix: [0x6A6A74, 0x56565F, 0x46464E],
                         ring: [0xF4F4F8, 0xC8C8D0, 0x9A9AA4], shade: 0x000000, shadow: 0.5, lift: 0.08)),
    ("Noir", Palette(background: [0x18181A, 0x050505, 0x000000], first: [0xFFFFFF, 0xFFFFFF],
                     second: [0xFFFFFF, 0xFFFFFF], mix: [0x1C1C1E, 0x0A0A0A], ring: [0xFFFFFF, 0xFFFFFF],
                     shadow: 0, underside: 0, rim: 0, gloss: 0, lift: 0.04, knockout: 14)),
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

/// The two letters, slanted and fitted to the icon centre: the second B's stem sits on the first B's lower bowl,
/// raised a step.
let letters: (first: CGPath, second: CGPath) = {
    let (line, reach) = bCentreline(h: 500)
    let slant = CGAffineTransform(a: 1, b: 0, c: -0.16, d: 1, tx: 0, ty: 0)
    let first = moved(smooth(stroked(line, 116), 16), slant)
    let second = moved(first, CGAffineTransform(translationX: reach, y: -56))
    let box = first.union(second).boundingBoxOfPath, k = 660 / max(box.width, box.height)
    let t = CGAffineTransform(translationX: -box.midX, y: -box.midY).concatenating(CGAffineTransform(scaleX: k, y: k))
        .concatenating(CGAffineTransform(translationX: size / 2, y: size / 2))
    return (moved(first, t), moved(second, t))
}()

/// The orbit: an outer circle minus an inner one touching it at the tail, so the ring tapers to a point there.
/// `front` is the wedge where the ring passes in front of the letters (angles y-down, clockwise from 3 o'clock).
/// Its edges fall where the ring crosses no letter, so the switch from behind to in front never shows.
let orbit: (ring: CGPath, front: CGPath, tail: CGPoint, head: CGPoint) = {
    let c = CGPoint(x: size / 2, y: size / 2 + 6), R: CGFloat = 440, thick: CGFloat = 120, tail: CGFloat = 3.95
    let r = R - thick / 2, u = CGPoint(x: cos(tail), y: sin(tail))
    let ic = CGPoint(x: c.x + u.x * (R - r), y: c.y + u.y * (R - r))
    let ring = CGPath(ellipseIn: CGRect(x: c.x - R, y: c.y - R, width: 2 * R, height: 2 * R), transform: nil)
        .subtracting(CGPath(ellipseIn: CGRect(x: ic.x - r, y: ic.y - r, width: 2 * r, height: 2 * r), transform: nil))
    let front = CGMutablePath()
    front.move(to: c)
    front.addArc(center: c, radius: 2000, startAngle: 85 * .pi / 180, endAngle: 230 * .pi / 180, clockwise: false)
    front.closeSubpath()
    return (ring, front, CGPoint(x: c.x + u.x * R, y: c.y + u.y * R), CGPoint(x: c.x - u.x * R, y: c.y - u.y * R))
}()

/// Renders one 1024 icon, full bleed (iOS masks the corners).
func render(_ p: Palette) -> CGImage {
    let ctx = context(Int(size), alpha: p.background.isEmpty)
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    let (first, second) = letters
    let both = first.union(second), overlap = first.intersection(second)

    /// Fills `path` with a gradient, by default diagonally across its own bounds.
    func paint(_ g: CGContext, _ path: CGPath, _ colors: [UInt32], from: CGPoint? = nil, to: CGPoint? = nil) {
        let box = path.boundingBoxOfPath
        g.saveGState(); g.addPath(path); g.clip()
        g.drawLinearGradient(gradient(colors.map { rgb($0) }),
                             start: from ?? CGPoint(x: box.minX + box.width * 0.15, y: box.minY),
                             end: to ?? CGPoint(x: box.maxX - box.width * 0.15, y: box.maxY),
                             options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        g.restoreGState()
    }
    /// Inner shading: shadows cast by everything outside `path`, shifted up (underside) and down (top rim).
    func shade(_ g: CGContext, _ path: CGPath, underside: CGFloat, rim: CGFloat) {
        let outside = CGMutablePath()
        outside.addRect(full.insetBy(dx: -200, dy: -200)); outside.addPath(path)
        g.saveGState(); g.addPath(path); g.clip()
        for (dy, blur, color) in [(-14.0, 22.0, rgb(0x000000, underside)), (6.0, 8.0, rgb(0xFFFFFF, rim))]
            as [(CGFloat, CGFloat, CGColor)] where color.alpha > 0 {
            g.saveGState()
            g.setShadow(offset: CGSize(width: 0, height: dy), blur: blur, color: color)
            g.addPath(outside); g.setFillColor(rgb(0x000000)); g.fillPath(using: .evenOdd)
            g.restoreGState()
        }
        g.restoreGState()
    }
    /// A drop shadow of `path` alone (offsets are in unflipped device space, so negative is down): the shape is
    /// drawn off-canvas and only its shadow lands here. `within` limits where it falls.
    func dropShadow(_ path: CGPath, _ alpha: CGFloat, dy: CGFloat, blur: CGFloat, within: CGPath? = nil) {
        guard alpha > 0 else { return }
        let away: CGFloat = 4000
        ctx.saveGState()
        if let within { ctx.addPath(within); ctx.clip(using: .evenOdd) }
        ctx.setShadow(offset: CGSize(width: -away, height: dy), blur: blur, color: rgb(p.shade, alpha))
        ctx.addPath(moved(path, CGAffineTransform(translationX: away, y: 0))); ctx.setFillColor(rgb(0x000000))
        ctx.fillPath()
        ctx.restoreGState()
    }

    if !p.background.isEmpty {
        ctx.drawLinearGradient(gradient(p.background.map { rgb($0) }), start: CGPoint(x: size * 0.25, y: 0),
                               end: CGPoint(x: size * 0.75, y: size),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let top = CGPoint(x: size / 2, y: -size * 0.3)
        ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, p.lift), rgb(0xFFFFFF, 0)]), startCenter: top, startRadius: 0,
                               endCenter: top, endRadius: size, options: [])
        if p.glow > 0 {
            for (letter, colors) in [(first, p.first), (second, p.second)] {
                let box = letter.boundingBoxOfPath, c = CGPoint(x: box.midX, y: box.midY), color = colors[colors.count / 2]
                ctx.drawRadialGradient(gradient([rgb(color, p.glow), rgb(color, p.glow * 0.35), rgb(color, 0)]),
                                       startCenter: c, startRadius: 0, endCenter: c, endRadius: 440, options: [])
            }
        }
    }

    // The ring is drawn once into a layer: all of it behind the letters, then its front wedge again on top.
    let ring = CGLayer(ctx, size: full.size, auxiliaryInfo: nil)!
    paint(ring.context!, orbit.ring, p.ring, from: orbit.tail, to: orbit.head)
    shade(ring.context!, orbit.ring, underside: p.underside, rim: p.rim + 0.1)
    dropShadow(orbit.ring, p.shadow * 0.6, dy: -16, blur: 30)
    ctx.draw(ring, at: .zero)

    // The letters' soft shadow stays off the ring, so the ring reads the same in front and behind.
    let offRing = CGMutablePath()
    offRing.addRect(full); offRing.addPath(orbit.ring)
    dropShadow(both, p.shadow, dy: -30, blur: 70, within: offRing)
    dropShadow(both, p.shadow * 0.5, dy: -6, blur: 12)
    let cut = rgb(p.background.last ?? 0x000000)
    if p.knockout > 0 {
        ctx.saveGState(); ctx.addPath(orbit.ring); ctx.clip()
        ctx.addPath(stroked(both, 2 * p.knockout)); ctx.setFillColor(cut); ctx.fillPath()
        ctx.restoreGState()
    }
    paint(ctx, first, p.first)
    paint(ctx, second, p.second)
    paint(ctx, overlap, p.mix)
    if p.gloss > 0 {
        for letter in [first, second] {
            let box = letter.boundingBoxOfPath
            ctx.saveGState(); ctx.addPath(letter); ctx.clip()
            ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, p.gloss), rgb(0xFFFFFF, 0)]), start: CGPoint(x: 0, y: box.minY),
                                   end: CGPoint(x: 0, y: box.midY), options: [])
            ctx.restoreGState()
        }
    }
    shade(ctx, both, underside: p.underside, rim: p.rim)

    // Where the ring passes in front, it casts a shadow on the letters.
    dropShadow(orbit.ring.intersection(orbit.front), p.shadow > 0 ? 0.35 : 0, dy: -12, blur: 22, within: both)
    ctx.saveGState(); ctx.addPath(orbit.front); ctx.clip()
    if p.knockout > 0 {
        ctx.saveGState(); ctx.addPath(both); ctx.clip(using: .evenOdd)
        ctx.addPath(stroked(orbit.ring, 2 * p.knockout)); ctx.setFillColor(cut); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.draw(ring, at: .zero); ctx.restoreGState()
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
write(scaled(mac, to: 256, alpha: true), root.appendingPathComponent("docs/assets/icon.png"))

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
