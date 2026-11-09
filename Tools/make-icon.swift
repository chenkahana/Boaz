// Renders the Folio app icon mark (a browser window with two mismatched eyes) at 1024×1024.
// Usage: swift Tools/make-icon.swift <output-dir> [palette] [preview-dir]
//   palette: default (primary set: light, dark, tinted) | an alternate from `palettes` below
//            (alternate iOS icon: one PNG + Contents.json). With preview-dir, also writes <name>-Preview.png
//            (180 px) for the Settings picker, e.g. Apps/iOS/Delight/IconPreviews.
// The shipped primary AppIcon set is hand-finished art; `default` redraws it with this geometry instead.
import AppKit
import CoreImage

let size: CGFloat = 1024
let arguments = Array(CommandLine.arguments.dropFirst())
let out = URL(fileURLWithPath: arguments.first ?? ".")

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

enum Variant { case light, dark, tinted }

/// A soft radial light behind the window (top-left origin, 1024 units).
/// `hard` draws a crisp orb instead, which the frosted window then blurs.
struct Blob {
    var color: UInt32; var x: CGFloat; var y: CGFloat; var radius: CGFloat; var alpha: CGFloat = 0.6; var hard = false
}

/// Colors for one icon. The eyes stay mismatched in every palette: that is the mark.
struct Palette {
    var stops: [UInt32]                         // background, top-left → bottom-right
    var blobs: [Blob] = []
    var window: CGColor                         // window body
    var frame: CGColor                          // window outline, toolbar rule and dots
    var lid: UInt32
    var leftIris: (UInt32, UInt32)              // top → bottom
    var rightIris: (UInt32, UInt32)
    var pupil: UInt32
    var sclera: CGColor? = nil                  // eye opening; nil shows the window body
    var sheen: CGFloat = 0                      // glass highlight across the window's top
    var frost: CGFloat = 0                      // blur radius for the background seen through the window
    var shadow: CGFloat = 0.35
}

let palettes: [String: Palette] = [
    "default": Palette(stops: [0x55506A, 0x3A3550, 0x2A2640], window: rgb(0x23202F, 0.55), frame: rgb(0x9C8FC4, 0.85),
                       lid: 0xEDE2D9, leftIris: (0x8E4A26, 0xD48D52), rightIris: (0x2238F0, 0x45B4FF), pupil: 0x221F2C),
    "midnight": Palette(stops: [0x15174A, 0x0A0B26, 0x050614],
                        blobs: [Blob(color: 0x3139FB, x: 512, y: 470, radius: 620, alpha: 0.55)],
                        window: rgb(0x080A24, 0.6), frame: rgb(0x8C93FF, 0.9), lid: 0xEEF0FF,
                        leftIris: (0xE06A7A, 0xFFB1A8), rightIris: (0x3139FB, 0x8FA6FF), pupil: 0x06071A, shadow: 0.5),
    "peach": Palette(stops: [0xFFD98F, 0xFF9C8F, 0xD9527E],
                     window: rgb(0x6E1840, 0.42), frame: rgb(0xFFFFFF, 0.9), lid: 0xFFFFFF,
                     leftIris: (0xE07A1F, 0xFFC56B), rightIris: (0xD92E63, 0xFF8FA6), pupil: 0x3D0D27, shadow: 0.25),
    "electric": Palette(stops: [0x7FE3FF, 0x1B46F5, 0x0A1466],
                        window: rgb(0x050C4A, 0.5), frame: rgb(0xC8F4FF, 0.9), lid: 0xFFFFFF,
                        leftIris: (0xF0A800, 0xFFE15C), rightIris: (0x1FB8E8, 0x9FF0FF), pupil: 0x060B40),
    "violet": Palette(stops: [0xFF9999, 0x8477DF, 0x2B1F70],
                      window: rgb(0x170E48, 0.5), frame: rgb(0xFFFFFF, 0.8), lid: 0xFFF4EF,
                      leftIris: (0xE8546A, 0xFFA98F), rightIris: (0x4B3BD9, 0xA99CFF), pupil: 0x140B3A),
    "graphite": Palette(stops: [0x5A5A60, 0x2E2E33, 0x18181B],
                        window: rgb(0x101012, 0.55), frame: rgb(0xA1A1A8, 0.9), lid: 0xE8E8ED,
                        leftIris: (0x6E6E75, 0xC4C4CA), rightIris: (0x45454B, 0x9A9AA2), pupil: 0x0E0E10, shadow: 0.45),
    "paper": Palette(stops: [0xFBF8F1, 0xF1EBDF, 0xE4DCCB],
                     window: rgb(0xFFFFFF, 0.9), frame: rgb(0x2B2833), lid: 0x2B2833,
                     leftIris: (0xA9531F, 0xE29A5C), rightIris: (0x2238F0, 0x4FA3FF), pupil: 0x16141B, shadow: 0.12),
    "aurora": Palette(stops: [0x0D1636, 0x0A0F2A, 0x070A1E],
                      blobs: [Blob(color: 0x2EE6A6, x: 180, y: 150, radius: 560, alpha: 0.6),
                              Blob(color: 0x8A5CFF, x: 900, y: 330, radius: 560, alpha: 0.6),
                              Blob(color: 0x2A6BFF, x: 520, y: 1000, radius: 520, alpha: 0.45)],
                      window: rgb(0x070B22, 0.5), frame: rgb(0xE6FFF6, 0.7), lid: 0xF2FFFA,
                      leftIris: (0x16C98D, 0x9DFFD5), rightIris: (0x8A5CFF, 0xD3C4FF), pupil: 0x070A1E, shadow: 0.45),
    "noir": Palette(stops: [0x000000, 0x000000], window: rgb(0x000000), frame: rgb(0xFFFFFF), lid: 0xFFFFFF,
                    leftIris: (0xFF7A00, 0xFFB000), rightIris: (0x0A84FF, 0x5AC8FA), pupil: 0x000000, shadow: 0),
    "sorbet": Palette(stops: [0xFFD3DE, 0xE6DBFF, 0xC4F0E3],
                      window: rgb(0xFFFFFF, 0.72), frame: rgb(0xFFFFFF), lid: 0x4B3F7A,
                      leftIris: (0xF2708E, 0xFFB3C4), rightIris: (0x5C86F2, 0xA9C4FF), pupil: 0x2C2252, shadow: 0.12),
    "glass": Palette(stops: [0x1C1846, 0x110F30, 0x09081C],
                     blobs: [Blob(color: 0x3139FB, x: 820, y: 250, radius: 520, alpha: 0.7),
                             Blob(color: 0xFF9999, x: 225, y: 780, radius: 205, alpha: 1, hard: true),
                             Blob(color: 0x5A62FF, x: 805, y: 255, radius: 205, alpha: 1, hard: true)],
                     window: rgb(0xFFFFFF, 0.1), frame: rgb(0xFFFFFF, 0.6), lid: 0xFFFFFF,
                     leftIris: (0xF0606A, 0xFFB8A8), rightIris: (0x3A4BF5, 0x9FB0FF), pupil: 0x0E0C24,
                     sheen: 0.2, frost: 46, shadow: 0.3),
    "sunset": Palette(stops: [0xFFC46B, 0xFF6F61, 0x9A2F6E, 0x3A1655],
                      window: rgb(0x2A0B36, 0.42), frame: rgb(0xFFE6C7, 0.9), lid: 0xFFF2E0,
                      leftIris: (0xF29A1F, 0xFFD77A), rightIris: (0xE8457A, 0xFFA3BE), pupil: 0x260A32),
    "tide": Palette(stops: [0x6EEAD6, 0x0F7C96, 0x0A2C4D],
                    window: rgb(0x032238, 0.48), frame: rgb(0xD5FBFF, 0.9), lid: 0xF0FDFF,
                    leftIris: (0x14B8A6, 0x99F6E4), rightIris: (0x1E9BEA, 0xBAE6FD), pupil: 0x041C2E),
]

/// Tinted appearance: grayscale marks on transparency; iOS supplies the tint.
let tinted = Palette(stops: [], window: rgb(0xFFFFFF, 0.08), frame: rgb(0xFFFFFF, 0.8), lid: 0xFFFFFF,
                     leftIris: (0x9A9A9A, 0xDDDDDD), rightIris: (0x9A9A9A, 0xDDDDDD), pupil: 0x3A3A3A, shadow: 0)

func render(_ v: Variant, name: String, palette base: Palette = palettes["default"]!) throws {
    let p = v == .tinted ? tinted : base
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space,
                        bitmapInfo: (v == .tinted ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
    // Draw in top-left coordinates so the geometry below reads like the artwork.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)

    func gradient(_ colors: [CGColor]) -> CGGradient {
        let locations = (0..<colors.count).map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
        return CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
    }

    // Background.
    if !p.stops.isEmpty {
        ctx.drawLinearGradient(gradient(p.stops.map { rgb($0) }), start: CGPoint(x: size * 0.1, y: 0),
                               end: CGPoint(x: size * 0.9, y: size), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        for b in p.blobs {
            let c = CGPoint(x: b.x, y: b.y)
            if b.hard {
                ctx.setFillColor(rgb(b.color, b.alpha))
                ctx.fillEllipse(in: CGRect(x: b.x - b.radius, y: b.y - b.radius, width: b.radius * 2, height: b.radius * 2))
                continue
            }
            ctx.drawRadialGradient(gradient([rgb(b.color, b.alpha), rgb(b.color, 0)]), startCenter: c, startRadius: 0,
                                   endCenter: c, endRadius: b.radius, options: [])
        }
    }

    // Frosted glass: the window shows a blurred copy of the background.
    var frosted: CGImage?
    if p.frost > 0, let backdrop = ctx.makeImage() {
        let image = CIImage(cgImage: backdrop)
        frosted = CIContext().createCGImage(image.clampedToExtent().applyingGaussianBlur(sigma: p.frost)
            .cropped(to: image.extent), from: image.extent)
    }

    // Window.
    let windowRect = CGRect(x: 96, y: 208, width: 832, height: 612)
    let window = CGPath(roundedRect: windowRect, cornerWidth: 92, cornerHeight: 92, transform: nil)
    ctx.saveGState()
    if p.shadow > 0 { ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 60, color: rgb(0x000000, p.shadow)) }
    ctx.addPath(window); ctx.setFillColor(p.window); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(window); ctx.clip()
    if let frosted {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1)   // CGImage draws in unflipped space
        ctx.draw(frosted, in: CGRect(x: 0, y: 0, width: size, height: size))
        ctx.restoreGState()
        ctx.addPath(window); ctx.setFillColor(p.window); ctx.fillPath()
    }
    if p.sheen > 0 {
        ctx.drawLinearGradient(gradient([rgb(0xFFFFFF, p.sheen), rgb(0xFFFFFF, 0)]), start: CGPoint(x: 0, y: windowRect.minY),
                               end: CGPoint(x: 0, y: windowRect.midY), options: [])
    }
    ctx.setFillColor(p.frame)
    ctx.fill(CGRect(x: windowRect.minX, y: 318, width: windowRect.width, height: 10))   // toolbar rule
    ctx.restoreGState()

    ctx.addPath(window.copy(strokingWithWidth: 12, lineCap: .round, lineJoin: .round, miterLimit: 10))
    ctx.setFillColor(p.frame); ctx.fillPath()
    for x in [196.0, 258.0, 320.0] {
        ctx.fillEllipse(in: CGRect(x: x - 17, y: 268 - 17, width: 34, height: 34))
    }

    // Eyes: an almond opening between two tapered lids, irises glancing up toward the centre.
    func eye(mirrored: Bool) {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: mirrored ? size - x : x, y: y) }
        let outer = pt(128, 548), inner = pt(492, 578), lowerStart = pt(152, 562)

        let opening = CGMutablePath()
        opening.move(to: outer)
        opening.addQuadCurve(to: inner, control: pt(300, 442))
        opening.addQuadCurve(to: lowerStart, control: pt(322, 702))
        opening.closeSubpath()

        ctx.saveGState()
        ctx.addPath(opening); ctx.clip()
        if let sclera = p.sclera { ctx.setFillColor(sclera); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size)) }
        let irisCenter = pt(336, 556), r: CGFloat = 84
        let colors = mirrored ? p.rightIris : p.leftIris
        ctx.saveGState()
        ctx.addEllipse(in: CGRect(x: irisCenter.x - r, y: irisCenter.y - r, width: r * 2, height: r * 2)); ctx.clip()
        ctx.drawLinearGradient(gradient([rgb(colors.0), rgb(colors.1)]), start: CGPoint(x: irisCenter.x, y: irisCenter.y - r),
                               end: CGPoint(x: irisCenter.x, y: irisCenter.y + r), options: [])
        ctx.restoreGState()
        let pupil = pt(340, 532), pr: CGFloat = 36
        ctx.setFillColor(rgb(p.pupil))
        ctx.fillEllipse(in: CGRect(x: pupil.x - pr, y: pupil.y - pr, width: pr * 2, height: pr * 2))
        ctx.restoreGState()

        let upper = CGMutablePath()
        upper.move(to: outer)
        upper.addQuadCurve(to: inner, control: pt(290, 356))
        upper.addQuadCurve(to: outer, control: pt(300, 442))
        let lower = CGMutablePath()
        lower.move(to: lowerStart)
        lower.addQuadCurve(to: pt(488, 584), control: pt(322, 740))
        lower.addQuadCurve(to: lowerStart, control: pt(322, 702))
        ctx.addPath(upper); ctx.addPath(lower)
        ctx.setFillColor(rgb(p.lid)); ctx.fillPath()
    }
    eye(mirrored: false)
    eye(mirrored: true)

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

/// Small copy for the Settings picker (app icon sets can't be loaded with UIImage(named:)).
func writePreview(of name: String) throws {
    guard let previewDir = arguments.dropFirst(2).first else { return }
    let icon = NSImage(contentsOf: out.appendingPathComponent("\(name).png"))!
    let preview = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 180, pixelsHigh: 180, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: preview)
    NSGraphicsContext.current?.imageInterpolation = .high
    icon.draw(in: NSRect(x: 0, y: 0, width: 180, height: 180))
    NSGraphicsContext.current = nil
    try preview.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: previewDir).appendingPathComponent("\(name)-Preview.png"))
}

let key = arguments.dropFirst().first ?? "default"
if key != "default" {
    guard let palette = palettes[key] else { fatalError("unknown palette \(key); use \(palettes.keys.sorted())") }
    let name = "AppIcon-\(key.prefix(1).uppercased() + key.dropFirst())"
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    try render(.light, name: "\(name).png", palette: palette)
    let contents = """
    {
      "images" : [
        { "filename" : "\(name).png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
    try contents.write(to: out.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    try writePreview(of: name)
} else {
    try render(.light, name: "AppIcon.png")
    try render(.dark, name: "AppIcon-Dark.png")
    try render(.tinted, name: "AppIcon-Tinted.png")
    try writePreview(of: "AppIcon")
}
print("wrote icons to \(out.path)")
