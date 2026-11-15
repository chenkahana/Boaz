import AppKit
import SceneKit

/// Draws one variant's ground (full bleed, y up) into a `px`-square context.
typealias Painter = (CGContext, CGFloat) -> Void
/// Draws on top of the finished icon; gets the knot render and where it was placed.
typealias Overlay = (CGContext, CGFloat, CGImage, CGRect) -> Void

/// One app icon: the knot's look, the ground it sits on, and what the pickers call it.
struct Variant {
    /// Asset name suffix: AppIcon-<id>. The primary icon is "Classic".
    let id: String
    let title: String
    let caption: String
    var look: Look
    var ground: Painter
    /// Under the knot: a soft drop shadow and a tight contact shadow.
    var shadow = RGB(0x2A2350)
    var shadowAlpha = 0.32
    var glow: RGB? = nil
    var glowAlpha = 0.0
    var overlay: Overlay? = nil
    /// The knot's width as a fraction of the icon.
    var scale = 0.8

    var assetName: String { id == "Classic" ? "AppIcon" : "AppIcon-\(id)" }
}

private var knotCache: [String: CGImage] = [:]

/// The knot render for a variant (or a variant's extra pass), at a size suited to `px`.
func knotImage(_ v: Variant, px: Int, pass: String = "", look: Look? = nil) -> CGImage {
    let size = px > 600 ? 2048 : px > 256 ? 1024 : 512
    let key = "\(v.id) \(pass) \(size)"
    if let hit = knotCache[key] { return hit }
    let image = renderKnot(look ?? v.look, px: size)
    knotCache[key] = image
    return image
}

/// The knot's visible bounds inside its render, as fractions (measured once from the alpha).
let knotBounds: CGRect = {
    let image = renderKnot(Look(color: { _ in RGB(0xFFFFFF) }), px: 512)
    let w = image.width, h = image.height
    let ctx = canvas(w, h)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let data = ctx.data!.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * h)
    var minX = w, maxX = 0, minY = h, maxY = 0
    for y in 0..<h { for x in 0..<w where data[y * ctx.bytesPerRow + x * 4 + 3] > 8 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    // Bitmap rows run top to bottom; CG rects run bottom to top.
    return CGRect(x: Double(minX) / Double(w), y: Double(h - 1 - maxY) / Double(h),
                  width: Double(maxX - minX + 1) / Double(w), height: Double(maxY - minY + 1) / Double(h))
}()

/// Where the knot render goes so the knot itself is `scale` of the icon wide and centred (a touch high, so its
/// shadow balances it).
func knotRect(_ px: CGFloat, scale: Double, center: CGPoint? = nil) -> CGRect {
    let side = px * scale / knotBounds.width
    let c = center ?? CGPoint(x: px / 2, y: px / 2 + px * 0.012)
    let x = c.x - side * (knotBounds.midX), y = c.y - side * (knotBounds.midY)
    return CGRect(x: x, y: y, width: side, height: side)
}

/// The knot with its shadows and glow, drawn into `ctx` at `rect`.
func drawKnot(_ ctx: CGContext, _ v: Variant, _ knot: CGImage, in rect: CGRect, px: CGFloat,
              blend: CGBlendMode = .normal) {
    let k = rect.width / CGFloat(knot.width)
    if v.shadowAlpha > 0 {
        let shade = silhouette(knot, v.shadow.cg(1))
        drawBlurred(ctx, shade, radius: Double(28 / k * px / 1024), in: rect.offsetBy(dx: px * 0.006, dy: -px * 0.035),
                    alpha: v.shadowAlpha)
        drawBlurred(ctx, shade, radius: Double(7 / k * px / 1024), in: rect.offsetBy(dx: 0, dy: -px * 0.01),
                    alpha: v.shadowAlpha * 0.9)
    }
    if let glow = v.glow, v.glowAlpha > 0 {
        let light = silhouette(knot, glow.cg(1))
        for (radius, alpha) in [(70.0, 0.9), (26.0, 0.8)] {
            drawBlurred(ctx, light, radius: radius / Double(k) * Double(px) / 1024, in: rect,
                        alpha: v.glowAlpha * alpha, blend: .screen)
        }
    }
    ctx.saveGState(); ctx.setBlendMode(blend); ctx.draw(knot, in: rect); ctx.restoreGState()
}

/// One icon, full bleed and square (iOS masks the corners). `ground: false` leaves the background transparent.
func icon(_ v: Variant, px: Int = 1024, ground: Bool = true) -> CGImage {
    let ctx = canvas(px)
    let s = CGFloat(px)
    if ground { v.ground(ctx, s) }
    let knot = knotImage(v, px: px)
    let rect = knotRect(s, scale: v.scale)
    if case .glass = v.look.finish, ground {
        // The ground seen through the glass: magnified about the knot, as a thick lens would.
        let behind = canvas(px)
        v.ground(behind, s)
        ctx.saveGState()
        ctx.clip(to: rect, mask: alphaMask(knot))
        let m = CGFloat(v.look.refraction), c = CGPoint(x: rect.midX, y: rect.midY)
        ctx.translateBy(x: c.x, y: c.y); ctx.scaleBy(x: m, y: -m); ctx.translateBy(x: -c.x, y: -c.y)
        ctx.draw(behind.makeImage()!, in: CGRect(x: 0, y: 0, width: s, height: s))
        ctx.restoreGState()
    }
    if let tint = v.look.tint {
        // Glass: the body tints what's behind it (more at the edges, where the light travels through more glass),
        // and its reflections add on top.
        let body = knotImage(v, px: px, pass: "tint", look: Look(knot: v.look.knot, finish: .glow, color: { s in
            RGB(0xFFFFFF).mix(tint, 0.15 + 0.85 * pow(1 - s.facing, 1.8))
        }))
        drawKnot(ctx, v, body, in: rect, px: s, blend: .multiply)
        ctx.saveGState(); ctx.setBlendMode(.screen); ctx.draw(knot, in: rect); ctx.restoreGState()
    } else {
        drawKnot(ctx, v, knot, in: rect, px: s)
    }
    v.overlay?(ctx, s, knot, rect)
    return ctx.makeImage()!
}

/// The artwork masked to a squircle on transparency; `inset` > 0 puts it on the macOS icon grid with a shadow.
func masked(_ art: CGImage, inset: CGFloat) -> CGImage {
    let size = CGFloat(art.width)
    let ctx = canvas(art.width)
    let rect = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: inset, dy: inset)
    let shape = squircle(rect)
    if inset > 0 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.012), blur: size * 0.028, color: RGB(0).cg(0.3))
        ctx.addPath(shape); ctx.setFillColor(RGB(0).cg()); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    ctx.draw(art, in: rect)
    ctx.addPath(shape); ctx.setLineWidth(size * 0.004); ctx.setStrokeColor(RGB(0xFFFFFF).cg(0.16)); ctx.strokePath()
    ctx.restoreGState()
    return ctx.makeImage()!
}

/// The macOS version: the square artwork on the 1024 grid (824 px squircle, 100 px margins).
func macIcon(_ art: CGImage) -> CGImage { masked(art, inset: CGFloat(art.width) * 100 / 1024) }
