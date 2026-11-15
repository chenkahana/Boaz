import AppKit

// Background helpers. Every painter works in a `s`-point square, y up, and is deterministic.

func fill(_ ctx: CGContext, _ s: CGFloat, _ c: RGB) {
    ctx.setFillColor(c.cg()); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
}

/// Top-to-bottom gradient (first stop at the top), optionally tilted.
func linear(_ ctx: CGContext, _ s: CGFloat, _ stops: [RGB], tilt: CGFloat = 0) {
    ctx.drawLinearGradient(gradient(stops.map { $0.cg() }), start: CGPoint(x: s / 2 - tilt * s, y: s),
                           end: CGPoint(x: s / 2 + tilt * s, y: 0),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ s: CGFloat, at c: CGPoint, radius: CGFloat, _ stops: [RGB], alpha: [Double]? = nil) {
    let colors = stops.enumerated().map { $0.element.cg(alpha?[$0.offset] ?? 1) }
    let p = CGPoint(x: c.x * s, y: c.y * s)
    ctx.drawRadialGradient(gradient(colors), startCenter: p, startRadius: 0, endCenter: p, endRadius: radius * s,
                           options: alpha == nil ? [.drawsAfterEndLocation] : [])
}

/// A soft pool of light (or shade) at `c` (fractions of the icon).
func pool(_ ctx: CGContext, _ s: CGFloat, at c: CGPoint, radius: CGFloat, _ color: RGB, _ alpha: Double,
          blend: CGBlendMode = .normal) {
    ctx.saveGState(); ctx.setBlendMode(blend)
    radial(ctx, s, at: c, radius: radius, [color, color, color], alpha: [alpha, alpha * 0.4, 0])
    ctx.restoreGState()
}

func vignette(_ ctx: CGContext, _ s: CGFloat, _ alpha: Double, color: RGB = RGB(0)) {
    let c = CGPoint(x: s / 2, y: s / 2)
    ctx.drawRadialGradient(gradient([color.cg(0), color.cg(0), color.cg(alpha)], [0, 0.55, 1]), startCenter: c,
                           startRadius: 0, endCenter: c, endRadius: s * 0.75, options: [.drawsAfterEndLocation])
}

/// Scattered round dots: confetti, bubbles, stars, sugar.
func dots(_ ctx: CGContext, _ s: CGFloat, seed: UInt64, count: Int, size: ClosedRange<Double>, colors: [RGB],
          alpha: ClosedRange<Double> = 1...1, avoidCentre: Double = 0, ring: Bool = false) {
    var rng = Noise(seed)
    var placed = 0, tries = 0
    while placed < count && tries < count * 20 {
        tries += 1
        let x = rng.next(), y = rng.next(), r = size.lowerBound + (size.upperBound - size.lowerBound) * rng.next()
        let a = alpha.lowerBound + (alpha.upperBound - alpha.lowerBound) * rng.next()
        let c = colors[Int(rng.next() * Double(colors.count)) % colors.count]
        if avoidCentre > 0, hypot(x - 0.5, (y - 0.5) * 1.15) < avoidCentre { continue }
        placed += 1
        let rect = CGRect(x: x * s - r * s, y: y * s - r * s, width: 2 * r * s, height: 2 * r * s)
        if ring {
            ctx.setStrokeColor(c.cg(a)); ctx.setLineWidth(r * s * 0.22); ctx.strokeEllipse(in: rect)
            ctx.setFillColor(c.cg(a * 0.18)); ctx.fillEllipse(in: rect)
        } else {
            ctx.setFillColor(c.cg(a)); ctx.fillEllipse(in: rect)
        }
    }
}

/// Four-pointed twinkles.
func sparkles(_ ctx: CGContext, _ s: CGFloat, _ points: [(Double, Double, Double)], color: RGB, alpha: Double = 1) {
    for (x, y, r) in points {
        let c = CGPoint(x: x * s, y: y * s), R = r * s, w = R * 0.18
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x, y: c.y + R))
        p.addQuadCurve(to: CGPoint(x: c.x + R, y: c.y), control: CGPoint(x: c.x + w, y: c.y + w))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - R), control: CGPoint(x: c.x + w, y: c.y - w))
        p.addQuadCurve(to: CGPoint(x: c.x - R, y: c.y), control: CGPoint(x: c.x - w, y: c.y - w))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + R), control: CGPoint(x: c.x - w, y: c.y + w))
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: R * 0.8, color: color.cg(alpha * 0.8))
        ctx.addPath(p); ctx.setFillColor(color.cg(alpha)); ctx.fillPath()
        ctx.restoreGState()
    }
}

/// Parallel bands across the icon at `angle` (radians), `period` and `duty` as fractions.
func bands(_ ctx: CGContext, _ s: CGFloat, angle: CGFloat, period: CGFloat, duty: CGFloat, color: RGB, alpha: Double,
           blur: CGFloat = 0, blend: CGBlendMode = .normal) {
    let layer = canvas(Int(s))
    layer.translateBy(x: s / 2, y: s / 2); layer.rotate(by: angle); layer.translateBy(x: -s, y: -s)
    var y: CGFloat = 0
    while y < 2 * s { layer.addRect(CGRect(x: 0, y: y, width: 2 * s, height: period * s * duty)); y += period * s }
    layer.setFillColor(color.cg(alpha)); layer.fillPath()
    var image = layer.makeImage()!
    if blur > 0 { image = blurred(image, Double(blur * s)) }
    ctx.saveGState(); ctx.setBlendMode(blend)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: s, height: s))
    ctx.restoreGState()
}

/// Fine film grain: keeps big gradients from banding.
func grain(_ ctx: CGContext, _ s: CGFloat, seed: UInt64, alpha: Double) {
    let n = 160
    var rng = Noise(seed)
    let cell = s / CGFloat(n)
    for y in 0..<n { for x in 0..<n {
        let v = rng.next()
        ctx.setFillColor(RGB(r: v, g: v, b: v).cg(alpha))
        ctx.fill(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: cell, height: cell))
    } }
}
