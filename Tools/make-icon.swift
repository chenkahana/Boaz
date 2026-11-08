// Renders the Folio app icon (light, dark, tinted) at 1024×1024.
// Usage: swift Tools/make-icon.swift <output-dir> [palette] [preview-dir]
//   palette: default (primary set: light, dark, tinted) | peach | electric | violet | midnight
//            (alternate iOS icon: one PNG + Contents.json). With preview-dir, also writes <name>-Preview.png
//            (180 px) for the Settings picker, e.g. Apps/iOS/Delight/IconPreviews.
import AppKit

let size: CGFloat = 1024
let arguments = Array(CommandLine.arguments.dropFirst())
let out = URL(fileURLWithPath: arguments.first ?? ".")

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

enum Variant { case light, dark, tinted }

/// Colors for one icon. `glow` switches the background to a dark radial style like the dark variant.
struct Palette {
    var stops: [UInt32]
    var glow: UInt32? = nil
    var panel: CGColor = rgb(0xFFFFFF, 0.95)
    var shade: CGColor = rgb(0xFFFFFF, 0.72)
    var sparkle: UInt32 = 0xFFD335
}

let palettes: [String: Palette] = [
    "default": Palette(stops: [0xFF9999, 0x3139FB, 0x101245]),
    "peach": Palette(stops: [0xFFE08A, 0xFF9999, 0xC94F7C], sparkle: 0xFFFFFF),
    "electric": Palette(stops: [0x7FE3FF, 0x1B46F5, 0x0A1466]),
    "violet": Palette(stops: [0xFF9999, 0x8477DF, 0x2B1F70]),
    "midnight": Palette(stops: [0x1C1F5E, 0x06061A], glow: 0x8477DF,
                        panel: rgb(0xEDEEFC, 0.95), shade: rgb(0x8589FF, 0.9), sparkle: 0xFF9999),
]

func render(_ v: Variant, name: String, palette p: Palette = palettes["default"]!) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space,
                        bitmapInfo: (v == .tinted ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
    let full = CGRect(x: 0, y: 0, width: size, height: size)

    // Background: peach → brand blue → deep indigo diagonal (transparent for tinted).
    switch v {
    case .light:
        let locations: [CGFloat] = p.stops.count == 3 ? [0, 0.55, 1] : [0, 1]
        let g = CGGradient(colorsSpace: space, colors: p.stops.map { rgb($0) } as CFArray, locations: locations)!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
        if let glowColor = p.glow {
            let glow = CGGradient(colorsSpace: space, colors: [rgb(glowColor, 0.6), rgb(glowColor, 0)] as CFArray,
                                  locations: [0, 1])!
            ctx.drawRadialGradient(glow, startCenter: CGPoint(x: size / 2, y: size * 0.45), startRadius: 0,
                                   endCenter: CGPoint(x: size / 2, y: size * 0.45), endRadius: size * 0.55, options: [])
        }
    case .dark:
        ctx.setFillColor(rgb(0x141421)); ctx.fill(full)
        let glow = CGGradient(colorsSpace: space, colors: [rgb(0x3239FA, 0.55), rgb(0x3239FA, 0)] as CFArray,
                              locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: size / 2, y: size * 0.45), startRadius: 0,
                               endCenter: CGPoint(x: size / 2, y: size * 0.45), endRadius: size * 0.55, options: [])
    case .tinted:
        break
    }

    // Mark: an open book — two panels hinged at the centre, tilted toward the viewer.
    let panelW = size * 0.27, panelH = size * 0.44, gap = size * 0.018, radius = size * 0.06
    let baseY = size * 0.26, cx = size / 2
    let panelColor: CGColor = v == .light ? p.panel : v == .dark ? rgb(0xEDEEFC, 0.95) : rgb(0xFFFFFF)
    let shadeColor: CGColor = v == .light ? p.shade : v == .dark ? rgb(0x8589FF, 0.9) : rgb(0xFFFFFF, 0.7)

    func panel(left: Bool) {
        ctx.saveGState()
        let x = left ? cx - gap - panelW : cx + gap
        // Shear about the hinge edge so the inner edges stay level and the outer edges lift.
        let hinge = left ? cx - gap : cx + gap
        let t = CGAffineTransform(translationX: -hinge, y: -baseY)
            .concatenating(CGAffineTransform(a: 1, b: left ? -0.10 : 0.10, c: 0, d: 1, tx: 0, ty: 0))
            .concatenating(CGAffineTransform(translationX: hinge, y: baseY))
        ctx.concatenate(t)
        let r = CGRect(x: x, y: baseY, width: panelW, height: panelH)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setFillColor(left ? shadeColor : panelColor)
        ctx.fillPath()
        ctx.restoreGState()
    }
    panel(left: true)
    panel(left: false)

    // Four-point sparkle above the hinge.
    let s = CGPoint(x: cx, y: baseY + panelH + size * 0.13), arm = size * 0.085, waist = size * 0.018
    let star = CGMutablePath()
    star.move(to: CGPoint(x: s.x, y: s.y + arm))
    star.addQuadCurve(to: CGPoint(x: s.x + arm, y: s.y), control: CGPoint(x: s.x + waist, y: s.y + waist))
    star.addQuadCurve(to: CGPoint(x: s.x, y: s.y - arm), control: CGPoint(x: s.x + waist, y: s.y - waist))
    star.addQuadCurve(to: CGPoint(x: s.x - arm, y: s.y), control: CGPoint(x: s.x - waist, y: s.y - waist))
    star.addQuadCurve(to: CGPoint(x: s.x, y: s.y + arm), control: CGPoint(x: s.x - waist, y: s.y + waist))
    ctx.addPath(star)
    ctx.setFillColor(v == .light ? rgb(p.sparkle) : v == .dark ? rgb(0xFF9999) : rgb(0xFFFFFF))
    ctx.fillPath()

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
