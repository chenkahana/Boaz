// Renders the Folio app icon (light, dark, tinted) at 1024×1024.
// Usage: swift Tools/make-icon.swift <output-dir>
import AppKit

let size: CGFloat = 1024
let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

enum Variant { case light, dark, tinted }

func render(_ v: Variant, name: String) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: space,
                        bitmapInfo: (v == .tinted ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
    let full = CGRect(x: 0, y: 0, width: size, height: size)

    // Background: peach → brand blue → deep indigo diagonal (transparent for tinted).
    switch v {
    case .light:
        let g = CGGradient(colorsSpace: space, colors: [rgb(0xFF9999), rgb(0x3139FB), rgb(0x101245)] as CFArray,
                           locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
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
    let panelColor: CGColor = v == .light ? rgb(0xFFFFFF, 0.95) : v == .dark ? rgb(0xEDEEFC, 0.95) : rgb(0xFFFFFF)
    let shadeColor: CGColor = v == .light ? rgb(0xFFFFFF, 0.72) : v == .dark ? rgb(0x8589FF, 0.9) : rgb(0xFFFFFF, 0.7)

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
    ctx.setFillColor(v == .light ? rgb(0xFFD335) : v == .dark ? rgb(0xFF9999) : rgb(0xFFFFFF))
    ctx.fillPath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

try render(.light, name: "AppIcon.png")
try render(.dark, name: "AppIcon-Dark.png")
try render(.tinted, name: "AppIcon-Tinted.png")
print("wrote icons to \(out.path)")
