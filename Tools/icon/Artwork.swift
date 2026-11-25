import AppKit

// Artwork around the icon: the README parade, the social preview, the DMG window and the review sheet.

/// Draws `art` as a macOS-style icon (squircle, soft shadow) centred at `c`, `side` wide, rotated `angle`.
func placeIcon(_ ctx: CGContext, _ art: CGImage, at c: CGPoint, side: CGFloat, angle: CGFloat = 0, shadow: Double = 0.28) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y); ctx.rotate(by: angle)
    let rect = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
    let shape = squircle(rect)
    ctx.setShadow(offset: CGSize(width: 0, height: -side * 0.04), blur: side * 0.12, color: RGB(0x1A1440).cg(shadow))
    ctx.addPath(shape); ctx.setFillColor(RGB(0xFFFFFF).cg()); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    ctx.addPath(shape); ctx.clip()
    ctx.draw(art, in: rect)
    ctx.restoreGState()
}

/// A wavy parade: every icon, bobbing along two rows, on the classic cream.
func parade(_ arts: [(Variant, CGImage)]) -> CGImage {
    let w = 1800, h = 760
    let ctx = canvas(w, h, alpha: false)
    let W = CGFloat(w), H = CGFloat(h)
    ctx.drawLinearGradient(gradient([RGB(0xFDF8EC).cg(), RGB(0xF4EAD6).cg()]), start: CGPoint(x: 0, y: H),
                           end: CGPoint(x: 0, y: 0), options: [])
    pool(ctx, W, at: CGPoint(x: 0.5, y: 0.5), radius: 0.4, RGB(0xFFFFFF), 0.8)
    let perRow = (arts.count + 1) / 2, side: CGFloat = 150
    // Spacing shrinks as the family grows, so every icon stays inside the frame.
    let pitch = min(176, (W - side - 60) / CGFloat(max(perRow - 1, 1)))
    for (i, item) in arts.enumerated() {
        let row = i / perRow, col = i % perRow
        let n = row == 0 ? perRow : arts.count - perRow
        let x = W / 2 + (CGFloat(col) - CGFloat(n - 1) / 2) * pitch
        let y = H * (row == 0 ? 0.66 : 0.3) + sin(CGFloat(col) * 0.9 + CGFloat(row) * 1.7) * 26
        let angle = sin(CGFloat(col) * 1.3 + CGFloat(row)) * 0.08
        placeIcon(ctx, item.1, at: CGPoint(x: x, y: y), side: side, angle: angle)
    }
    return ctx.makeImage()!
}

/// 1280×640 GitHub social card in the family layout shared with Jimmy and Edison: the icon on the left, name and
/// tagline on the right, a footer with the family's icons. A few variants fan out behind the big icon.
func socialPreview(primary: CGImage, fan: [CGImage], family: CGImage?) -> CGImage {
    let w = 1280, h = 640
    let ctx = canvas(w, h, alpha: false)
    // The family's flat off-white, so the sibling icons in the footer sit on the ground they were drawn on.
    ctx.setFillColor(RGB(0xFBFBFC).cg()); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    pool(ctx, 1280, at: CGPoint(x: 0.23, y: 0.36), radius: 0.32, RGB(0xFFE7D2), 0.9)
    let centre = CGPoint(x: 300, y: 330)
    // Cards fanned out behind the icon, like a hand of trading cards.
    for (i, art) in fan.enumerated() {
        let a = (CGFloat(i) - CGFloat(fan.count - 1) / 2) * 0.36
        let offset = CGPoint(x: centre.x + sin(a) * 230, y: centre.y - 40 - (1 - cos(a)) * 200)
        placeIcon(ctx, art, at: offset, side: 190, angle: -a, shadow: 0.2)
    }
    placeIcon(ctx, primary, at: centre, side: 320, shadow: 0.32)
    let ink = RGB(0x141414)
    text(ctx, "Boaz", at: CGPoint(x: 560, y: 364), size: 118, weight: .bold, color: ink, rounded: false, kern: -2)
    text(ctx, "A calm web browser", at: CGPoint(x: 562, y: 290), size: 44, weight: .medium, color: RGB(0x3A3A40),
         rounded: false)
    text(ctx, "for iPhone and Mac.", at: CGPoint(x: 562, y: 234), size: 44, weight: .medium, color: RGB(0x3A3A40),
         rounded: false)
    text(ctx, "iOS · macOS · SwiftUI · \(variants.count) pretzel icons", at: CGPoint(x: 563, y: 170), size: 26, weight: .regular,
         color: RGB(0x7A7A82), rounded: false)
    ctx.setFillColor(RGB(0xDDD8CE).cg()); ctx.fill(CGRect(x: 100, y: 98, width: 1081, height: 2))
    text(ctx, "Open source  ·  chenkahana.com", at: CGPoint(x: 100, y: 42), size: 26, weight: .medium,
         color: RGB(0x7A7A82), rounded: false)
    placeIcon(ctx, primary, at: CGPoint(x: 988, y: 56), side: 54, shadow: 0.18)
    if let family { ctx.draw(family, in: CGRect(x: 1030, y: 20, width: 160, height: 72)) }
    return ctx.makeImage()!
}

/// The DMG window's background, `scale` 1 or 2 (660×400 points): drag the pretzel to Applications.
/// Finder puts Boaz.app at (165, 190) and Applications at (495, 190), points from the top left.
func dmgBackground(scale: Int, confetti: [CGImage]) -> CGImage {
    let k = CGFloat(scale), w = Int(660 * k), h = Int(400 * k)
    let ctx = canvas(w, h, alpha: false)
    ctx.scaleBy(x: k, y: k)
    ctx.drawLinearGradient(gradient([RGB(0xFDF9EF).cg(), RGB(0xF3E8D2).cg()]), start: CGPoint(x: 0, y: 400),
                           end: CGPoint(x: 0, y: 0), options: [])
    pool(ctx, 660, at: CGPoint(x: 0.5, y: 0.35), radius: 0.5, RGB(0xFFFFFF), 0.7)
    // Little pretzels drifting around the edges.
    let spots: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(48, 340, 40, 0.2), (612, 352, 34, -0.25), (590, 52, 44, 0.15),
                                                       (70, 60, 30, -0.1), (330, 372, 26, 0.3), (250, 40, 22, -0.3),
                                                       (420, 36, 28, 0.2)]
    for (i, spot) in spots.enumerated() where !confetti.isEmpty {
        placeIcon(ctx, confetti[i % confetti.count], at: CGPoint(x: spot.0, y: spot.1), side: spot.2, angle: spot.3,
                  shadow: 0.16)
    }
    // A dotted, slightly bouncy arrow from the app to Applications (y up: icon centres sit at 400 - 190).
    let y: CGFloat = 400 - 194
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 258, y: y))
    arrow.addCurve(to: CGPoint(x: 398, y: y), control1: CGPoint(x: 300, y: y + 34), control2: CGPoint(x: 356, y: y + 34))
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [0.1, 12])
    ctx.setLineWidth(6); ctx.setStrokeColor(RGB(0x4A5AE6).cg(0.85))
    ctx.addPath(arrow); ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    let head = CGMutablePath()
    head.move(to: CGPoint(x: 386, y: y + 16)); head.addLine(to: CGPoint(x: 402, y: y - 1)); head.addLine(to: CGPoint(x: 380, y: y - 6))
    ctx.setLineWidth(5); ctx.setLineJoin(.round); ctx.addPath(head); ctx.strokePath()
    text(ctx, "Drag Boaz to Applications", at: CGPoint(x: 330, y: 92), size: 17, weight: .semibold,
         color: RGB(0x3A3550), center: true)
    text(ctx, "then pick your favorite pretzel in Settings › App Icon", at: CGPoint(x: 330, y: 68), size: 12.5,
         weight: .medium, color: RGB(0x8A8292), center: true)
    return ctx.makeImage()!
}

/// Review sheet: every icon large with its name, then rows at 60 and 29 px (iOS) and 32 and 16 px (macOS) on
/// light and dark grounds.
func contactSheet(_ items: [(String, CGImage)]) -> CGImage {
    let columns = 5, tile: CGFloat = 400, gap: CGFloat = 48, label: CGFloat = 56, strip: CGFloat = 230
    let rows = (items.count + columns - 1) / columns
    let width = CGFloat(columns) * tile + CGFloat(columns + 1) * gap
    let height = CGFloat(rows) * (tile + label + gap) + gap + 2 * strip
    let ctx = canvas(Int(width), Int(height), alpha: false)
    ctx.setFillColor(RGB(0xE9E9EE).cg()); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    for (i, item) in items.enumerated() {
        let x = gap + CGFloat(i % columns) * (tile + gap)
        let y = height - gap - CGFloat(i / columns + 1) * (tile + label + gap) + label + gap
        ctx.draw(masked(item.1, inset: 0), in: CGRect(x: x, y: y, width: tile, height: tile))
        text(ctx, item.0, at: CGPoint(x: x + 6, y: y - 42), size: 28, weight: .semibold, color: RGB(0x333333))
    }
    for (band, ground) in [(0, 0xF5F5F7), (1, 0x1C1C1E)] as [(Int, UInt32)] {
        let y0 = CGFloat(1 - band) * strip
        ctx.setFillColor(RGB(ground).cg()); ctx.fill(CGRect(x: 0, y: y0, width: width, height: strip))
        for (px, y, mac) in [(60.0, y0 + 140, false), (29.0, y0 + 96, false), (32.0, y0 + 50, true), (16.0, y0 + 20, true)]
            as [(CGFloat, CGFloat, Bool)] {
            for (i, item) in items.enumerated() {
                let small = mac ? scaled(macIcon(item.1), to: Int(px)) : scaled(masked(item.1, inset: 0), to: Int(px))
                ctx.draw(small, in: CGRect(x: gap + CGFloat(i) * 92, y: y, width: px, height: px))
            }
        }
    }
    return ctx.makeImage()!
}
