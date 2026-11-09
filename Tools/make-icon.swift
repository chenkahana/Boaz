// Boaz Browser app icons: a "BB" monogram, two chunky rounded capital B's offset on the diagonal with the
// crossing painted as a clear pane, in white on a rich gradient with soft shadows, a top-edge highlight and
// a little underside shading for depth. The other BB candidates live in `options` below.
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
//   build/icon-bb-options.png                                           every BB candidate in four palettes
import AppKit
import CoreImage
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

/// A soft light in the background (top-left origin, 1024 units).
struct Glow {
    var color: UInt32; var x: CGFloat; var y: CGFloat; var radius: CGFloat; var alpha: CGFloat = 0.5
}

struct Palette {
    var stops: [UInt32]                     // background, top-left → bottom-right
    var glows: [Glow] = []
    var ink: (UInt32, UInt32) = (0xFFFFFF, 0xEEEEF4)   // glyph, top → bottom
    var shade: UInt32 = 0x000000            // drop shadow and underside tint
    var shadow: CGFloat = 0.4
    var rim: CGFloat = 0.9                  // white highlight along the glyph's top edges
    var underside: CGFloat = 0.11
    var lift: CGFloat = 0.14                // soft white light from above the icon
    var sink: CGFloat = 0.16                // darkening toward the bottom edge
    var frost: CGFloat = 0                  // > 0: the glyph is frosted glass (blur radius of what's behind it)
}

// Order matches the Settings picker.
let alternates: [(String, Palette)] = [
    ("Midnight", Palette(stops: [0x232A80, 0x0F1246, 0x05061A],
                         glows: [Glow(color: 0x4A63FF, x: 512, y: 430, radius: 640, alpha: 0.55)],
                         ink: (0xFFFFFF, 0xDCE3FF), shade: 0x02031A, shadow: 0.6, lift: 0.08)),
    ("Glass", Palette(stops: [0x2A2C94, 0x18165A, 0x0B0A28],
                      glows: [Glow(color: 0xFF8A8F, x: 150, y: 930, radius: 560, alpha: 0.95),
                              Glow(color: 0x5C6CFF, x: 880, y: 140, radius: 620, alpha: 0.95)],
                      shade: 0x05041A, shadow: 0.45, rim: 0.85, underside: 0.06, lift: 0.08, frost: 38)),
    ("Aurora", Palette(stops: [0x111C40, 0x0A0F2A, 0x070A1E],
                       glows: [Glow(color: 0x2EE6A6, x: 150, y: 130, radius: 620, alpha: 0.62),
                               Glow(color: 0x8A5CFF, x: 930, y: 360, radius: 600, alpha: 0.6),
                               Glow(color: 0x2A6BFF, x: 520, y: 1060, radius: 560, alpha: 0.5)],
                       ink: (0xFFFFFF, 0xE2FFF4), shade: 0x020414, shadow: 0.55, lift: 0.06)),
    ("Electric", Palette(stops: [0x7FE3FF, 0x2F6BFF, 0x1730C8, 0x0C1670],
                         ink: (0xFFFFFF, 0xE3EEFF), shade: 0x061048, shadow: 0.45)),
    ("Tide", Palette(stops: [0x7BF0DA, 0x19A3B4, 0x0D5878, 0x0A2E4D],
                     ink: (0xFFFFFF, 0xE4FAFF), shade: 0x032238, shadow: 0.45)),
    ("Violet", Palette(stops: [0xFFAA9C, 0xB08CF0, 0x6F5BE0, 0x332685],
                       ink: (0xFFFFFF, 0xF0ECFF), shade: 0x1E1260, shadow: 0.42)),
    ("Sunset", Palette(stops: [0xFFC66E, 0xFF7A63, 0xD8457A, 0x5A1C6E],
                       ink: (0xFFFFFF, 0xFFF0E8), shade: 0x3A0D3A, shadow: 0.42)),
    ("Peach", Palette(stops: [0xFFE2A8, 0xFFB094, 0xF47F8E, 0xDC5C8C],
                      ink: (0xFFFFFF, 0xFFF1F0), shade: 0x8A2350, shadow: 0.34, underside: 0.12)),
    ("Sorbet", Palette(stops: [0xFFD3DF, 0xE9DDFF, 0xCDEFE6],
                       glows: [Glow(color: 0xFFFFFF, x: 300, y: 200, radius: 520, alpha: 0.45)],
                       ink: (0x6655C8, 0x40329A), shade: 0x4B3CA8, shadow: 0.2, rim: 0.4, underside: 0.18,
                       lift: 0.1, sink: 0.04)),
    ("Paper", Palette(stops: [0xFDFBF6, 0xF4EEE3, 0xE8E0CF],
                      ink: (0x34303D, 0x16141B), shade: 0x5A4A30, shadow: 0.26, rim: 0.28, underside: 0.25,
                      lift: 0.1, sink: 0.05)),
    ("Graphite", Palette(stops: [0x74747C, 0x404046, 0x1E1E22],
                         ink: (0xFFFFFF, 0xD6D6DC), shade: 0x000000, shadow: 0.5)),
    ("Noir", Palette(stops: [0x1E1E20, 0x000000], ink: (0xFFFFFF, 0xFFFFFF), shadow: 0, rim: 0, underside: 0,
                     lift: 0.05, sink: 0)),
]

/// The Boaz default: confident violet-indigo, a warm pink light top-right and a cool blue one bottom-left.
let primary = Palette(stops: [0x9A86FF, 0x6A4FF0, 0x3A26B0, 0x22186E],
                      glows: [Glow(color: 0xFF8FC4, x: 940, y: 60, radius: 660, alpha: 0.65),
                              Glow(color: 0x38B6FF, x: 40, y: 1040, radius: 620, alpha: 0.4)],
                      ink: (0xFFFFFF, 0xEDE8FF), shade: 0x160C55, shadow: 0.45)
/// iOS dark appearance: the glyph carries the brand colors on a near-black background.
let dark = Palette(stops: [0x221C40, 0x110E22, 0x08070F],
                   glows: [Glow(color: 0x6A4FF0, x: 900, y: 80, radius: 620, alpha: 0.3)],
                   ink: (0xD8CCFF, 0x9479FF), shade: 0x000000, shadow: 0.6, rim: 0.6, underside: 0.2, lift: 0.05)
/// iOS tinted appearance: a grayscale glyph on transparency; the system supplies the tint.
let tinted = Palette(stops: [], ink: (0xFFFFFF, 0xC4C4C4), shadow: 0, rim: 0, underside: 0.12, lift: 0, sink: 0)

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

/// A chunky capital B drawn as one thick rounded stroke, stem centreline at x = 0, top at y = 0.
/// The upper bowl is a little shorter and narrower than the lower one, as in a well-drawn B.
/// `filled` closes the counters (the B's silhouette).
func letterB(height: CGFloat = 600, weight w: CGFloat = 120, filled: Bool = false) -> CGPath {
    let h = height - w, waist = (h * 0.47).rounded()
    let r1 = waist / 2, r2 = (h - waist) / 2
    let a1: CGFloat = 132, a2 = a1 + r1 - r2 + 26
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: .zero); p.addLine(to: CGPoint(x: a1, y: 0))
    p.addArc(center: CGPoint(x: a1, y: r1), radius: r1, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
    p.addLine(to: CGPoint(x: 0, y: waist)); p.addLine(to: CGPoint(x: a2, y: waist))
    p.addArc(center: CGPoint(x: a2, y: waist + r2), radius: r2, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
    p.closeSubpath()
    let shape = filled ? stroked(p, w).union(p) : stroked(p, w)
    return moved(smooth(shape, 24), CGAffineTransform(translationX: w / 2, y: w / 2))   // origin at top-left
}

/// How a layer of the mark is filled. `tint` is the glyph at reduced opacity; `glass` frosts what's behind it.
enum Fill { case solid, tint(CGFloat), glass }
struct Layer { var path: CGPath; var fill: Fill = .solid }

/// A mark is drawn back to front; `overlap` (optional) is painted as a clear pane where the layers cross.
struct Mark { var layers: [Layer]; var overlap: CGPath? = nil }

/// Scales the layers together to fit `box` and centres them (a hair high: the drop shadow adds weight below).
func fitted(_ mark: Mark, width: CGFloat, height: CGFloat) -> Mark {
    let all = mark.layers.map(\.path).reduce(CGMutablePath()) { $0.addPath($1); return $0 }
    let box = all.boundingBoxOfPath, k = min(width / box.width, height / box.height)
    let t = CGAffineTransform(translationX: -box.midX, y: -box.midY).concatenating(CGAffineTransform(scaleX: k, y: k))
        .concatenating(CGAffineTransform(translationX: size / 2, y: size / 2 - 8))
    return Mark(layers: mark.layers.map { Layer(path: moved($0.path, t), fill: $0.fill) },
                overlap: mark.overlap.map { moved($0, t) })
}

/// The BB candidates. `chosen` is the one the icon sets use; all of them go on build/icon-bb-options.png.
let b = letterB()
let bWidth = b.boundingBoxOfPath.width
let options: [(String, Mark)] = [
    // (a) A translucent echo of the B stacked up and to the right behind it, cut clear around the front B.
    ("a  echo", {
        let back = moved(b, CGAffineTransform(translationX: bWidth * 0.24, y: -80))
        let solid = letterB(filled: true)   // cut around the silhouette, so the counters show background, not the echo
        return fitted(Mark(layers: [Layer(path: back.subtracting(solid.union(stroked(solid, 40))), fill: .tint(0.45)),
                                    Layer(path: b)]), width: 620, height: 620)
    }()),
    // (b) Back-to-back ligature: a mirrored B and a B sharing one stem.
    ("b  mirrored", {
        let w = b.boundingBoxOfPath.minX + 64   // stem centre
        let right = moved(b, CGAffineTransform(translationX: -w, y: 0))
        let left = moved(right, CGAffineTransform(scaleX: -1, y: 1))
        return fitted(Mark(layers: [Layer(path: smooth(left.union(right), 30))]), width: 660, height: 600)
    }()),
    // (c) Two B's offset on the diagonal; where they cross reads as a pane of glass.
    ("c  diagonal", {
        let back = moved(b, CGAffineTransform(translationX: -bWidth * 0.33, y: -80))
        let front = moved(b, CGAffineTransform(translationX: bWidth * 0.33, y: 80))
        return fitted(Mark(layers: [Layer(path: back), Layer(path: front)], overlap: back.intersection(front)),
                      width: 660, height: 640)
    }()),
]
let chosen = options[2].1

/// Renders one 1024 icon, full bleed (iOS masks the corners).
func render(_ p: Palette, _ mark: Mark = chosen, transparent: Bool = false) -> CGImage {
    let ctx = context(Int(size), alpha: transparent)
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    let full = CGRect(x: 0, y: 0, width: size, height: size)
    func fill(_ path: CGPath, _ colors: [CGColor]) {
        let box = path.boundingBoxOfPath
        ctx.drawLinearGradient(gradient(colors), start: CGPoint(x: 0, y: box.minY), end: CGPoint(x: 0, y: box.maxY), options: [])
    }

    if !p.stops.isEmpty {
        ctx.drawLinearGradient(gradient(p.stops.map { rgb($0) }), start: CGPoint(x: size * 0.18, y: 0),
                               end: CGPoint(x: size * 0.82, y: size),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        for g in p.glows {
            let c = CGPoint(x: g.x, y: g.y)
            ctx.drawRadialGradient(gradient([rgb(g.color, g.alpha), rgb(g.color, g.alpha * 0.4), rgb(g.color, 0)]),
                                   startCenter: c, startRadius: 0, endCenter: c, endRadius: g.radius, options: [])
        }
        let top = CGPoint(x: size / 2, y: -size * 0.25)
        ctx.drawRadialGradient(gradient([rgb(0xFFFFFF, p.lift), rgb(0xFFFFFF, 0)]), startCenter: top, startRadius: 0,
                               endCenter: top, endRadius: size * 0.95, options: [])
        ctx.drawLinearGradient(gradient([rgb(0x000000, 0), rgb(0x000000, p.sink)]), start: CGPoint(x: 0, y: size * 0.55),
                               end: CGPoint(x: 0, y: size), options: [])
    }

    for layer in mark.layers {
        let glyph = layer.path
        var fillKind = layer.fill
        if p.frost > 0 { fillKind = .glass }
        let opacity: CGFloat = if case .tint(let a) = fillKind { a } else { 1 }

        // What the layer sees through itself when it is glass.
        var backdrop: CGImage?
        if case .glass = fillKind, let image = ctx.makeImage() {
            let ci = CIImage(cgImage: image)
            let frosted = ci.clampedToExtent().applyingGaussianBlur(sigma: max(p.frost, 30))
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.6, kCIInputBrightnessKey: 0.08])
            backdrop = CIContext().createCGImage(frosted.cropped(to: ci.extent), from: ci.extent)
        }

        // Drop shadows (offsets are in unflipped device space, so negative is down): a wide soft one and a contact one.
        // The glyph is drawn off-canvas and only its shadow lands here, so translucent layers stay translucent.
        if p.shadow > 0 {
            let away: CGFloat = 4000
            for (dy, blur, k) in [(-34.0, 70.0, 1.0), (-8.0, 16.0, 0.5)] as [(CGFloat, CGFloat, CGFloat)] {
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: -away, height: dy), blur: blur, color: rgb(p.shade, p.shadow * k * opacity))
                ctx.addPath(moved(glyph, CGAffineTransform(translationX: away, y: 0))); ctx.setFillColor(rgb(0x000000))
                ctx.fillPath()
                ctx.restoreGState()
            }
        }

        ctx.saveGState()
        ctx.setAlpha(opacity)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.addPath(glyph); ctx.clip()
        if let backdrop {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)   // CGImage draws in unflipped space
            ctx.draw(backdrop, in: full)
            ctx.restoreGState()
            fill(glyph, [rgb(0xFFFFFF, 0.62), rgb(0xFFFFFF, 0.34)])
            let box = glyph.boundingBoxOfPath
            ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.3), rgb(0xFFFFFF, 0)]), start: CGPoint(x: 0, y: box.minY),
                                   end: CGPoint(x: 0, y: box.minY + box.height * 0.5), options: [])   // sheen
        } else {
            fill(glyph, [rgb(p.ink.0), rgb(p.ink.1)])
        }
        // Inner shading: shadows cast by everything outside the layer, shifted up (underside) and down (top rim).
        let outside = CGMutablePath()
        outside.addRect(full.insetBy(dx: -200, dy: -200)); outside.addPath(glyph)
        for (dy, blur, color) in [(14.0, 26.0, rgb(p.shade, p.underside)), (-7.0, 8.0, rgb(0xFFFFFF, p.rim))]
            as [(CGFloat, CGFloat, CGColor)] where color.alpha > 0 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: dy), blur: blur, color: color)
            ctx.addPath(outside); ctx.setFillColor(rgb(0x000000)); ctx.fillPath(using: .evenOdd)
            ctx.restoreGState()
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()
        if backdrop != nil {   // glass edge
            ctx.addPath(stroked(glyph, 5)); ctx.setFillColor(rgb(0xFFFFFF, 0.45)); ctx.fillPath()
        }
    }

    if let overlap = mark.overlap, p.frost == 0 {   // a clear pane: the background seen faintly through the crossing
        // (glass layers already show each other)
        ctx.saveGState()
        ctx.addPath(overlap); ctx.clip()
        fill(overlap, [rgb(p.stops.first ?? 0x808080, 0.5), rgb(p.stops.last ?? 0x808080, 0.5)])
        ctx.restoreGState()
        ctx.addPath(stroked(overlap, 4)); ctx.setFillColor(rgb(0xFFFFFF, 0.5)); ctx.fillPath()
    }
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
write(render(tinted, transparent: true), primaryDir.appendingPathComponent("AppIcon-Tinted.png"))
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

contactSheet(sheet, columns: 5, to: "build/icon-contact-sheet.png")
let samples = [("Default", primary)] + alternates.filter { ["Midnight", "Paper", "Sunset"].contains($0.0) }
contactSheet(options.flatMap { option in samples.map { ("\(option.0) · \($0.0)", render($0.1, option.1)) } },
             columns: samples.count, to: "build/icon-bb-options.png")
print("wrote Boaz icons under \(root.path)")
