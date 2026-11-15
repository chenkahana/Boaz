import AppKit
import CoreImage
import UniformTypeIdentifiers

let space = CGColorSpace(name: CGColorSpace.sRGB)!

/// An sRGB color with components 0…1.
struct RGB {
    var r, g, b: Double

    init(_ hex: UInt32) {
        r = Double(hex >> 16 & 0xFF) / 255; g = Double(hex >> 8 & 0xFF) / 255; b = Double(hex & 0xFF) / 255
    }
    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    func mix(_ o: RGB, _ t: Double) -> RGB {
        let t = min(max(t, 0), 1)
        return RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t)
    }
    func scaled(_ k: Double) -> RGB { RGB(r: r * k, g: g * k, b: b * k) }
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
    func cg(_ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var ns: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: 1) }

    /// Hue 0…1, saturation and value 0…1.
    static func hsv(_ h: Double, _ s: Double, _ v: Double) -> RGB {
        let h = (h - floor(h)) * 6, i = Int(h) % 6, f = h - floor(h)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: return RGB(r: v, g: t, b: p)
        case 1: return RGB(r: q, g: v, b: p)
        case 2: return RGB(r: p, g: v, b: t)
        case 3: return RGB(r: p, g: q, b: v)
        case 4: return RGB(r: t, g: p, b: v)
        default: return RGB(r: v, g: p, b: q)
        }
    }
}

/// Samples a multi-stop gradient at t (stops evenly spaced).
func ramp(_ stops: [RGB], _ t: Double) -> RGB {
    guard stops.count > 1 else { return stops[0] }
    let x = min(max(t, 0), 1) * Double(stops.count - 1), i = min(Int(x), stops.count - 2)
    return stops[i].mix(stops[i + 1], x - Double(i))
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    let locations = locations ?? (0..<colors.count).map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
    return CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

func canvas(_ w: Int, _ h: Int? = nil, alpha: Bool = true) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h ?? w, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue)!
    ctx.interpolationQuality = .high
    return ctx
}

func scaled(_ image: CGImage, to w: Int, _ h: Int? = nil, alpha: Bool = true) -> CGImage {
    let ctx = canvas(w, h, alpha: alpha)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h ?? w))
    return ctx.makeImage()!
}

/// Deterministic noise so every run writes the same pixels.
struct Noise {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> Double {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return Double(state % 1_000_000) / 1_000_000
    }
}

/// Smooth 3D value noise and fractal turbulence for solid textures (wood, marble, clay).
func hash3(_ x: Int, _ y: Int, _ z: Int) -> Double {
    var h = UInt64(bitPattern: Int64(x &* 374761393 &+ y &* 668265263 &+ z &* 2147483647))
    h = (h ^ (h >> 13)) &* 1274126177
    h ^= h >> 16
    return Double(h & 0xFFFF) / 65535
}

func valueNoise(_ p: Vec) -> Double {
    let i = (Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
    let f = Vec(p.x - floor(p.x), p.y - floor(p.y), p.z - floor(p.z))
    let u = f * f * (3 - 2 * f)
    func c(_ dx: Int, _ dy: Int, _ dz: Int) -> Double { hash3(i.0 + dx, i.1 + dy, i.2 + dz) }
    let x00 = c(0, 0, 0) + (c(1, 0, 0) - c(0, 0, 0)) * u.x, x10 = c(0, 1, 0) + (c(1, 1, 0) - c(0, 1, 0)) * u.x
    let x01 = c(0, 0, 1) + (c(1, 0, 1) - c(0, 0, 1)) * u.x, x11 = c(0, 1, 1) + (c(1, 1, 1) - c(0, 1, 1)) * u.x
    let y0 = x00 + (x10 - x00) * u.y, y1 = x01 + (x11 - x01) * u.y
    return y0 + (y1 - y0) * u.z
}

func turbulence(_ p: Vec, octaves: Int = 4) -> Double {
    var sum = 0.0, amp = 0.5, q = p
    for _ in 0..<octaves { sum += amp * valueNoise(q); q *= 2.03; amp *= 0.5 }
    return sum
}

let ci = CIContext(options: [.workingColorSpace: space, .outputColorSpace: space])

/// Gaussian blur that keeps the canvas size (edges clamp to transparent).
func blurred(_ image: CGImage, _ radius: Double) -> CGImage {
    let input = CIImage(cgImage: image)
    let out = input.applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
    return ci.createCGImage(out, from: input.extent, format: .RGBA8, colorSpace: space)!
}

/// Draws a blurred copy of `image` into `rect`, padding first so the blur isn't clipped at the image's edges.
/// `radius` is in the image's own pixels.
func drawBlurred(_ ctx: CGContext, _ image: CGImage, radius: Double, in rect: CGRect, alpha: Double = 1,
                 blend: CGBlendMode = .normal) {
    let pad = Int(radius * 3), w = image.width + 2 * pad, h = image.height + 2 * pad
    let padded = canvas(w, h)
    padded.draw(image, in: CGRect(x: pad, y: pad, width: image.width, height: image.height))
    let soft = blurred(padded.makeImage()!, radius)
    let k = rect.width / CGFloat(image.width), p = CGFloat(pad) * k
    ctx.saveGState(); ctx.setAlpha(alpha); ctx.setBlendMode(blend)
    ctx.draw(soft, in: rect.insetBy(dx: -p, dy: -p))
    ctx.restoreGState()
}

/// The image's alpha filled with one color.
func silhouette(_ image: CGImage, _ color: CGColor) -> CGImage {
    let ctx = canvas(image.width, image.height)
    let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    ctx.clip(to: rect, mask: alphaMask(image))
    ctx.setFillColor(color); ctx.fill(rect)
    return ctx.makeImage()!
}

/// Grayscale mask from an image's alpha channel.
func alphaMask(_ image: CGImage) -> CGImage {
    let w = image.width, h = image.height
    let rgba = canvas(w, h)
    rgba.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    let src = rgba.data!.bindMemory(to: UInt8.self, capacity: rgba.bytesPerRow * h)
    let gray = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    let dst = gray.data!.bindMemory(to: UInt8.self, capacity: w * h)
    for y in 0..<h { for x in 0..<w { dst[y * w + x] = src[y * rgba.bytesPerRow + x * 4 + 3] } }
    return gray.makeImage()!
}

/// Continuous-corner squircle (superellipse) filling `rect`.
func squircle(_ rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath(), steps = 720
    for i in 0..<steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi, c = cos(t), s = sin(t)
        let point = CGPoint(x: rect.midX + rect.width / 2 * copysign(pow(abs(c), 2 / n), c),
                            y: rect.midY + rect.height / 2 * copysign(pow(abs(s), 2 / n), s))
        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

func pngData(_ image: CGImage) -> Data {
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest))
    return data as Data
}

/// Writes a PNG, dropping the alpha channel when every pixel is opaque (smaller files, and iOS rejects
/// alpha in its primary icon).
func write(_ image: CGImage, _ url: URL, opaque: Bool = false) {
    let out = opaque ? scaled(image, to: image.width, image.height, alpha: false) : image
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! pngData(out).write(to: url)
}

/// An .icns holding 256, 512 and 1024 px PNGs (types ic08, ic09, ic10).
func writeIcns(_ image: CGImage, _ url: URL) {
    func be(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
    var body = Data()
    for (type, px) in [("ic08", 256), ("ic09", 512), ("ic10", 1024)] {
        let png = pngData(px == image.width ? image : scaled(image, to: px))
        body += type.data(using: .ascii)! + be(UInt32(png.count + 8)) + png
    }
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! ("icns".data(using: .ascii)! + be(UInt32(body.count + 8)) + body).write(to: url)
}

func cgImage(_ ns: NSImage) -> CGImage {
    var rect = CGRect(origin: .zero, size: ns.size)
    return ns.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
}

/// Draws text with AppKit into a CG context (y up).
func text(_ ctx: CGContext, _ string: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight = .bold,
          color: RGB, alpha: Double = 1, rounded: Bool = true, center: Bool = false, kern: CGFloat = 0) {
    var font = NSFont.systemFont(ofSize: size, weight: weight)
    if rounded, let d = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: d, size: size) ?? font }
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .kern: kern,
        .foregroundColor: NSColor(srgbRed: color.r, green: color.g, blue: color.b, alpha: alpha)]
    let s = NSAttributedString(string: string, attributes: attributes)
    let w = s.size().width
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    s.draw(at: CGPoint(x: center ? point.x - w / 2 : point.x, y: point.y))
    NSGraphicsContext.restoreGraphicsState()
}
