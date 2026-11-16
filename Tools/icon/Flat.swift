import AppKit

// The flat icons: the pretzel knot drawn as one flat strand, the way the system's own icons are glyphs on a plain
// ground. Where the strand crosses itself, the strand underneath stops short of the one on top.

struct FlatStyle {
    /// nil leaves the ground transparent (the tinted icon).
    var ground: [RGB]?
    var strand: [RGB]
}

let flatLight = FlatStyle(ground: [RGB(0xFFFFFF), RGB(0xF1F1F6)], strand: [RGB(0x5C6CFF), RGB(0x3443D8)])
let flatDark = FlatStyle(ground: [RGB(0x2A2A2E), RGB(0x050506)], strand: [RGB(0x7584FF), RGB(0x4655F0)])
let flatTinted = FlatStyle(ground: nil, strand: [RGB(0xFFFFFF), RGB(0xD6D6D6)])

/// The knot's centre line in icon points (y up), with each point's depth.
private func flatCurve(_ s: CGFloat, samples n: Int = 1800) -> (points: [CGPoint], depth: [Double], width: CGFloat) {
    let knot = Knot()
    let raw = (0..<n).map { knot.point(Double($0) / Double(n) * 2 * .pi) }
    let minX = raw.map(\.x).min()!, maxX = raw.map(\.x).max()!
    let minY = raw.map(\.y).min()!, maxY = raw.map(\.y).max()!
    // The strand's outer edge spans 64% of the icon, centred.
    let width = s * 0.072
    let k = (s * 0.64 - width) / CGFloat(max(maxX - minX, maxY - minY))
    let cx = CGFloat(minX + maxX) / 2, cy = CGFloat(minY + maxY) / 2
    let points = raw.map { CGPoint(x: s / 2 + (CGFloat($0.x) - cx) * k, y: s / 2 + (CGFloat($0.y) - cy) * k) }
    return (points, raw.map(\.z), width)
}

/// Where the curve crosses itself: the index of the sample on top at each crossing.
private func overCrossings(_ points: [CGPoint], _ depth: [Double]) -> [Int] {
    let n = points.count
    var over: [Int] = []
    func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> Bool {
        func side(_ p: CGPoint, _ q: CGPoint, _ r: CGPoint) -> CGFloat { (q.x - p.x) * (r.y - p.y) - (q.y - p.y) * (r.x - p.x) }
        return side(a, b, c) * side(a, b, d) < 0 && side(c, d, a) * side(c, d, b) < 0
    }
    for i in 0..<n where i + n / 20 < n {
        for j in (i + n / 20)..<n where n - (j - i) > n / 20 {
            if cross(points[i], points[(i + 1) % n], points[j], points[(j + 1) % n]) {
                over.append(depth[i] > depth[j] ? i : j)
            }
        }
    }
    return over
}

private func strandPath(_ points: [CGPoint], from a: Int, to b: Int) -> CGPath {
    let n = points.count, path = CGMutablePath()
    path.move(to: points[(a % n + n) % n])
    for i in (a + 1)...b { path.addLine(to: points[(i % n + n) % n]) }
    return path
}

/// One flat icon, `px` square, full bleed.
func flatIcon(_ style: FlatStyle, px: Int = 1024) -> CGImage {
    let s = CGFloat(px)
    let ctx = canvas(px)
    if let ground = style.ground { linear(ctx, s, ground) }

    // The knot in its own layer, so the gaps at the crossings are cut out of the strand, not painted over it.
    let layer = canvas(px)
    let (points, depth, width) = flatCurve(s)
    let n = points.count
    let gap = width * 0.42
    func paint(_ path: CGPath, width w: CGFloat, cap: CGLineCap) {
        layer.saveGState()
        layer.addPath(path); layer.setLineWidth(w); layer.setLineCap(cap); layer.setLineJoin(.round)
        layer.replacePathWithStrokedPath(); layer.clip()
        layer.drawLinearGradient(gradient(style.strand.map { $0.cg() }),
                                 start: CGPoint(x: 0, y: s * 0.8), end: CGPoint(x: 0, y: s * 0.2),
                                 options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        layer.restoreGState()
    }
    let closed = strandPath(points, from: 0, to: n)
    paint(closed, width: width, cap: .round)
    // At each crossing, clear a band around the strand on top (taking the one below with it), then lay the top
    // strand back down.
    let reach = Int(Double(n) * 0.035)
    for i in overCrossings(points, depth) {
        let band = strandPath(points, from: i - reach, to: i + reach)
        layer.saveGState()
        layer.setBlendMode(.clear)
        layer.addPath(band); layer.setLineWidth(width + gap * 2); layer.setLineCap(.butt); layer.setLineJoin(.round)
        layer.strokePath()
        layer.restoreGState()
        paint(strandPath(points, from: i - reach - 4, to: i + reach + 4), width: width, cap: .butt)
    }
    ctx.draw(layer.makeImage()!, in: CGRect(x: 0, y: 0, width: s, height: s))
    return ctx.makeImage()!
}
