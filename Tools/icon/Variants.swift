import AppKit
import SceneKit

// The icon family. Order matches the pickers (AppIconCatalog.swift); ids are the asset names' suffixes.

/// How strongly a surface point belongs to the warm glow where the strands cross in the middle (the
/// strand that dives under the top crossing).
func crossing(_ s: Surface, centre: Double = 0.685, spread: Double = 0.04) -> Double {
    let f = s.t / (2 * .pi)
    var d = abs(f - centre); d = min(d, 1 - d)
    return exp(-d * d / (spread * spread))
}

/// Lighter on top of the knot, deeper below.
func toned(_ s: Surface, _ top: RGB, _ bottom: RGB) -> RGB { bottom.mix(top, (s.p.y + 2.6) / 5.2) }

func fract(_ x: Double) -> Double { x - floor(x) }

/// Antialiased stripe: 1 inside [0, duty) of each period of x, with soft edges `soft` wide.
func stripe(_ x: Double, duty: Double, soft: Double = 0.04) -> Double {
    let f = fract(x)
    return smoothstep(-soft, soft, f) * (1 - smoothstep(duty - soft, duty + soft, f)) + smoothstep(1 - soft, 1 + soft, f)
}

let blueTop = RGB(0x5668F2), blueBottom = RGB(0x2D3AC2), peach = RGB(0xF9A487)

func classicColor(_ s: Surface) -> RGB { toned(s, blueTop, blueBottom).mix(peach, crossing(s) * 0.92) }

// MARK: Toppings

/// Points on the tube's upper, camera-facing skin.
func skin(_ tube: Tube, _ rng: inout Noise, count: Int, facing: Double = 0.25, up: Double = -0.35) -> [(Vec, Vec)] {
    var out: [(Vec, Vec)] = []
    var tries = 0
    while out.count < count && tries < count * 200 {
        tries += 1
        let i = Int(rng.next() * Double(tube.positions.count)) % tube.positions.count
        let n = tube.normals[i]
        guard n.z > facing, n.y > up else { continue }
        let p = tube.positions[i]
        if out.contains(where: { simd_length($0.0 - p) < 0.17 }) { continue }
        out.append((p, n))
    }
    return out
}

func pbr(_ color: RGB, roughness: Double, metal: Double = 0) -> SCNMaterial {
    let m = SCNMaterial()
    m.lightingModel = .physicallyBased
    m.diffuse.contents = color.ns
    m.roughness.contents = roughness
    m.metalness.contents = metal
    return m
}

/// Coarse pretzel salt: chunky, slightly translucent cubes.
func salt(_ tube: Tube, _ rng: inout Noise) -> [SCNNode] {
    let material = pbr(RGB(0xFBF8F2), roughness: 0.35)
    return skin(tube, &rng, count: 46, facing: 0.35, up: -0.1).map { p, n in
        let a = 0.09 + rng.next() * 0.06
        let box = SCNBox(width: a, height: a * (0.7 + rng.next() * 0.5), length: a * (0.8 + rng.next() * 0.4),
                         chamferRadius: a * 0.18)
        box.materials = [material]
        let node = SCNNode(geometry: box)
        let q = p + n * a * 0.3
        node.simdPosition = SIMD3<Float>(Float(q.x), Float(q.y), Float(q.z))
        node.eulerAngles = SCNVector3(rng.next() * 6, rng.next() * 6, rng.next() * 6)
        return node
    }
}

/// Rainbow sprinkles lying flat on the chocolate.
func sprinkles(_ tube: Tube, _ rng: inout Noise) -> [SCNNode] {
    let palette = [0xFF5C8A, 0xFFD23F, 0x3EC1F3, 0x7BE495, 0xFFFFFF, 0xB78CFF].map { pbr(RGB(UInt32($0)), roughness: 0.3) }
    return skin(tube, &rng, count: 64, facing: 0.3, up: -0.2).map { p, n in
        let capsule = SCNCapsule(capRadius: 0.032, height: 0.2)
        capsule.materials = [palette[Int(rng.next() * Double(palette.count)) % palette.count]]
        let node = SCNNode(geometry: capsule)
        // Lie along a random direction in the surface's tangent plane.
        let seed = simd_normalize(Vec(rng.next() - 0.5, rng.next() - 0.5, rng.next() - 0.5))
        let along = simd_normalize(seed - simd_dot(seed, n) * n)
        let q = p + n * 0.03
        node.simdPosition = SIMD3<Float>(Float(q.x), Float(q.y), Float(q.z))
        node.simdOrientation = simd_quatf(from: SIMD3<Float>(0, 1, 0),
                                          to: SIMD3<Float>(Float(along.x), Float(along.y), Float(along.z)))
        return node
    }
}

// MARK: The family

/// The primary icon: the knot as a flat blue strand on white, like the system's own icons. Its iOS dark and tinted
/// appearances are `classicDark` and `classicTinted`.
let classic = Variant(
    id: "Classic", title: "Classic", caption: "Flat blue knot, light or dark with the system",
    look: Look(color: classicColor), ground: { _, _ in }, flat: flatLight)

let flatDarkVariant = Variant(
    id: "Dark", title: "Dark", caption: "Flat blue knot on black",
    look: Look(color: classicColor), ground: { _, _ in }, flat: flatDark)

let glossy = Variant(
    id: "Glossy", title: "Glossy", caption: "The knot in 3D: glossy blue on cream",
    look: Look(finish: .satin(0.5), color: classicColor, studio: Studio(intensity: 0.85)),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0xFDF9EF), RGB(0xF8F0DF), RGB(0xF0E5CD)])
        pool(ctx, s, at: CGPoint(x: 0.3, y: 0.85), radius: 0.7, RGB(0xFFFFFF), 0.7)
    })

let midnight = Variant(
    id: "Midnight", title: "Midnight Snack", caption: "The classic, up past bedtime",
    look: Look(finish: .satin(0.36), color: { s in
        toned(s, RGB(0x6A7CFF), RGB(0x3140C8)).mix(RGB(0xFFA27E), crossing(s))
    }, studio: Studio(top: RGB(0x6A74C8), horizon: RGB(0x1C2050), floor: RGB(0x0A0B20), key: 1, intensity: 0.8),
       lighting: Lighting(key: 1.5, fill: 0.15, rim: 1.1)),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0x252B78), RGB(0x121546), RGB(0x080924)])
        dots(ctx, s, seed: 3, count: 70, size: 0.0015...0.005, colors: [RGB(0xFFFFFF), RGB(0xC9D2FF)],
             alpha: 0.3...0.95, avoidCentre: 0.36)
        sparkles(ctx, s, [(0.14, 0.84, 0.028), (0.86, 0.16, 0.022), (0.88, 0.86, 0.016)], color: RGB(0xFFF4D8))
    },
    shadow: RGB(0x000000), shadowAlpha: 0.5, glow: RGB(0x5B6CFF), glowAlpha: 0.55)

let noir = Variant(
    id: "Noir", title: "Film Noir", caption: "Black and white, lit through the blinds",
    look: Look(finish: .satin(0.28), color: { s in toned(s, RGB(0xF4F4F4), RGB(0xBDBDBD)) },
               studio: Studio(top: RGB(0x3A3A3A), horizon: RGB(0x0C0C0C), floor: RGB(0x000000), key: 1.0, intensity: 0.9),
               lighting: Lighting(key: 2.6, keyDirection: Vec(-0.75, 0.6, 0.45), fill: 0.0, rim: 1.4,
                                  shadowSoftness: 2, shadow: 0.92),
               occlusion: 1.3),
    ground: { ctx, s in
        fill(ctx, s, RGB(0x050505))
        pool(ctx, s, at: CGPoint(x: 0.36, y: 0.62), radius: 0.62, RGB(0x6A6A6A), 0.9)
    },
    shadow: RGB(0x000000), shadowAlpha: 0.8,
    overlay: { ctx, s, _, _ in
        bands(ctx, s, angle: -0.45, period: 0.1, duty: 0.42, color: RGB(0x000000), alpha: 0.55, blur: 0.004)
        vignette(ctx, s, 0.7)
    })

/// Neon: hot pink through violet to cyan along the tube, white-hot where it faces you.
func neonColor(_ s: Surface) -> RGB {
    let hue = ramp([RGB(0xFF2E9F), RGB(0xB04BFF), RGB(0x27E6FF), RGB(0xB04BFF), RGB(0xFF2E9F)], s.u)
    return hue.mix(RGB(0xFFFFFF), pow(s.facing, 6) * 0.38)
}

let neon = Variant(
    id: "Neon", title: "Neon Night", caption: "Open late: pink and cyan glass tubes",
    look: Look(finish: .glow, color: neonColor),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0x1A0838), RGB(0x0C0420), RGB(0x14052A)])
        // A synthwave floor fading toward the horizon.
        ctx.saveGState()
        let horizon = s * 0.3
        ctx.setStrokeColor(RGB(0xFF3FB4).cg(0.45)); ctx.setLineWidth(s * 0.004)
        for i in -8...8 {
            ctx.move(to: CGPoint(x: s / 2 + CGFloat(i) * s * 0.03, y: horizon))
            ctx.addLine(to: CGPoint(x: s / 2 + CGFloat(i) * s * 0.2, y: 0))
        }
        for j in 0..<7 {
            let y = horizon * pow(CGFloat(j) / 7, 1.8)
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: s, y: y))
        }
        ctx.strokePath()
        ctx.restoreGState()
        pool(ctx, s, at: CGPoint(x: 0.5, y: 0.3), radius: 0.55, RGB(0xFF2E9F), 0.35, blend: .screen)
        dots(ctx, s, seed: 11, count: 40, size: 0.0015...0.004, colors: [RGB(0xFFFFFF), RGB(0x9FF4FF)],
             alpha: 0.3...0.9, avoidCentre: 0.38)
    },
    shadowAlpha: 0, glow: RGB(0xC23BFF), glowAlpha: 0.6,
    overlay: { ctx, s, knot, rect in
        let k = Double(rect.width) / Double(knot.width) * 1024 / Double(s)
        for (r, a) in [(8.0, 0.5), (24.0, 0.35)] {
            drawBlurred(ctx, knot, radius: r / k, in: rect, alpha: a, blend: .screen)
        }
    },
    scale: 0.76)

/// Solid wood: rings around an axis running across the knot, wobbled by noise, with fine grain.
func woodColor(_ s: Surface) -> RGB {
    let p = s.p
    let q = Vec(p.x * 0.8 + p.y * 0.6, -p.x * 0.6 + p.y * 0.8, p.z)
    let r = hypot(q.y + 0.9, q.z * 1.3) + turbulence(q * 0.6) * 0.45
    let ring = fract(r * 3.4)
    // Early wood is pale and wide; late wood is a thin dark band.
    let late = smoothstep(0.62, 0.86, ring) * (1 - smoothstep(0.9, 1.0, ring))
    let streak = turbulence(Vec(q.x * 0.35, q.y * 4.5, q.z * 4.5), octaves: 3)
    let light = RGB(0xE8B47A), dark = RGB(0x9A5526)
    return light.mix(dark, late * 0.8 + (streak - 0.5) * 0.45).mix(RGB(0x6E3A16), (1 - s.occlusion) * 0.6)
}

let wood = Variant(
    id: "Wood", title: "Woodshop", caption: "Hand-carved and oiled, grain and all",
    look: Look(finish: .satin(0.5), color: woodColor,
               studio: Studio(top: RGB(0xFFF1DC), horizon: RGB(0xC89A6A), floor: RGB(0x4A3A2A), key: 0.8)),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0x6FA38E), RGB(0x4E8571), RGB(0x376655)])
        pool(ctx, s, at: CGPoint(x: 0.3, y: 0.85), radius: 0.6, RGB(0xFFFFFF), 0.25)
        dots(ctx, s, seed: 5, count: 26, size: 0.003...0.008, colors: [RGB(0xF3D6A8)], alpha: 0.25...0.5,
             avoidCentre: 0.4)
    },
    shadow: RGB(0x0E2A20), shadowAlpha: 0.45)

/// Baked dough: deep mahogany where the oven browned it, golden on the sides, pale in the creases.
func bakedColor(_ s: Surface) -> RGB {
    let top = max(0, s.n.y * 0.55 + s.n.z * 0.6)
    let mottled = turbulence(s.p * 1.6) - 0.5
    return RGB(0xD9944A).mix(RGB(0x8A3F14), smoothstep(0.15, 0.95, top + mottled * 0.35))
        .mix(RGB(0xE9B77A), (1 - s.occlusion) * 0.9)
}

let salted = Variant(
    id: "Salted", title: "Fresh Baked", caption: "Golden, glossy and generously salted",
    look: Look(knot: Knot(belly: 0.22), finish: .satin(0.4), color: bakedColor,
               studio: Studio(top: RGB(0xFFF3DE), horizon: RGB(0xD8A070), floor: RGB(0x5A3A20), key: 0.9),
               occlusion: 0.5, toppings: salt),
    ground: { ctx, s in
        fill(ctx, s, RGB(0xFFF7EE))
        bands(ctx, s, angle: 0, period: 0.125, duty: 0.5, color: RGB(0xE04A3F), alpha: 0.3)
        bands(ctx, s, angle: .pi / 2, period: 0.125, duty: 0.5, color: RGB(0xE04A3F), alpha: 0.3)
        vignette(ctx, s, 0.18, color: RGB(0x6A1A10))
    },
    shadow: RGB(0x4A1A08), shadowAlpha: 0.4)

/// Dark chocolate with a white-chocolate drizzle across the top.
func chocolateColor(_ s: Surface) -> RGB {
    let p = s.p
    let d = fract((p.x * 0.75 + p.y * 1.1 + 0.25 * sin(p.x * 2.2)) * 0.95)
    let drizzle = s.n.z > 0.05 ? (1 - smoothstep(0.035, 0.075, abs(d - 0.5))) * smoothstep(0.05, 0.3, s.n.z) : 0
    return toned(s, RGB(0x6A3A22), RGB(0x3A1C0E)).mix(RGB(0xF6E8D2), drizzle)
}

let chocolate = Variant(
    id: "Chocolate", title: "Choco Dip", caption: "Dipped, drizzled and sprinkled",
    look: Look(finish: .satin(0.22), color: chocolateColor,
               studio: Studio(top: RGB(0xFFFFFF), horizon: RGB(0xFFC2D4), floor: RGB(0x5A2A30), key: 1.1),
               toppings: sprinkles),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0xFFD0DE), RGB(0xFFAFC6), RGB(0xFF8DB0)])
        pool(ctx, s, at: CGPoint(x: 0.3, y: 0.85), radius: 0.6, RGB(0xFFFFFF), 0.45)
    },
    shadow: RGB(0x8A1E46), shadowAlpha: 0.38)

let glass = Variant(
    id: "Glass", title: "Glassblower", caption: "Clear glass, fresh from the furnace",
    look: Look(finish: .glass, color: { s in RGB(0x0A1418).mix(RGB(0x6ACFE0), pow(1 - s.facing, 3) * 0.6) },
               studio: Studio(top: RGB(0xFFFFFF), horizon: RGB(0x406A80), floor: RGB(0x081420), key: 1.6, bands: 0.7),
               lighting: Lighting(key: 1.0, fill: 0.0, rim: 1.0, shadow: 0.0), occlusion: 0, tint: RGB(0x3F9CC8)),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0x47D6D0), RGB(0x2E8FD6), RGB(0x3A3FB8)], tilt: 0.2)
        dots(ctx, s, seed: 17, count: 14, size: 0.03...0.09, colors: [RGB(0xFFFFFF)], alpha: 0.06...0.16)
        pool(ctx, s, at: CGPoint(x: 0.3, y: 0.85), radius: 0.6, RGB(0xFFFFFF), 0.3)
    },
    shadow: RGB(0x0A2A6A), shadowAlpha: 0.3)

let chrome = Variant(
    id: "Chrome", title: "Chrome", caption: "Polished to a mirror shine",
    look: Look(finish: .metal(0.07), color: { _ in RGB(0xF2F4F8) },
               studio: Studio(top: RGB(0xFFFFFF), horizon: RGB(0x2A2E38), floor: RGB(0x0C0D10), key: 1.2, bands: 1),
               occlusion: 0.7),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0x5A6070), RGB(0x262A33), RGB(0x0D0E12)])
        pool(ctx, s, at: CGPoint(x: 0.5, y: 0.6), radius: 0.5, RGB(0x9AA6C0), 0.25)
    },
    shadow: RGB(0x000000), shadowAlpha: 0.6)

let gold = Variant(
    id: "Gold", title: "24 Karat", caption: "Solid gold on emerald velvet",
    look: Look(finish: .metal(0.2), color: { s in toned(s, RGB(0xFFD978), RGB(0xE6A63A)) },
               studio: Studio(top: RGB(0xFFF6DE), horizon: RGB(0x6A4A1A), floor: RGB(0x1A1206), key: 1.2, bands: 0.5,
                              bandColor: RGB(0xFFF0C8)),
               occlusion: 0.8),
    ground: { ctx, s in
        radial(ctx, s, at: CGPoint(x: 0.5, y: 0.58), radius: 0.8, [RGB(0x1F8A67), RGB(0x0D4F3B), RGB(0x052A1F)])
        sparkles(ctx, s, [(0.13, 0.86, 0.03), (0.87, 0.82, 0.02), (0.84, 0.13, 0.026), (0.16, 0.18, 0.015)],
                 color: RGB(0xFFE7A0))
    },
    shadow: RGB(0x00130C), shadowAlpha: 0.55, glow: RGB(0xFFC24A), glowAlpha: 0.18)

/// White marble with grey veins and a thread of gold.
func marbleColor(_ s: Surface) -> RGB {
    let p = s.p
    let t = turbulence(p * 0.9, octaves: 5)
    let v = abs(sin((p.x * 0.9 + p.y * 0.5 + t * 5) * 1.6))
    let gold = abs(sin((p.x * -0.4 + p.y * 0.9 + t * 4) * 1.1 + 1))
    return RGB(0xFBF9F6).mix(RGB(0x7E8088), pow(1 - v, 9) * 0.85).mix(RGB(0xD9A84A), pow(1 - gold, 30) * 0.9)
        .mix(RGB(0xE6E2DC), (1 - t) * 0.3)
}

let marble = Variant(
    id: "Marble", title: "Museum Piece", caption: "Carrara marble, veined with gold",
    look: Look(finish: .satin(0.22), color: marbleColor,
               studio: Studio(top: RGB(0xFFFFFF), horizon: RGB(0xE9C0AC), floor: RGB(0x6A4A3E), key: 1)),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0xF2C6B0), RGB(0xE6A88C), RGB(0xD68E72)])
        pool(ctx, s, at: CGPoint(x: 0.3, y: 0.85), radius: 0.6, RGB(0xFFFFFF), 0.4)
    },
    shadow: RGB(0x6A2A18), shadowAlpha: 0.4)

/// Clay: each stretch of the strand a different pastel, softly blended, with thumb-pressed lumps.
func clayColor(_ s: Surface) -> RGB {
    let stops = [RGB(0xC5A8FF), RGB(0xFFB3A1), RGB(0xFFE08A), RGB(0x9EE6C0), RGB(0x8FCBFF), RGB(0xC5A8FF)]
    let lumps = valueNoise(s.p * 3.5) - 0.5
    return ramp(stops, fract(s.u + 0.08)).scaled(1 + lumps * 0.08)
}

let clay = Variant(
    id: "Clay", title: "Claymation", caption: "Squished by hand, one pastel at a time",
    look: Look(finish: .matte, color: clayColor,
               studio: Studio(top: RGB(0xFFFFFF), horizon: RGB(0xD6E2FF), floor: RGB(0x7A84A8), key: 0.7),
               lighting: Lighting(key: 1.6, fill: 0.35, rim: 0.4, shadowSoftness: 18, shadow: 0.4)),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0xDCE8FF), RGB(0xC9D7FF), RGB(0xB7C5F8)])
        dots(ctx, s, seed: 23, count: 22, size: 0.012...0.03, colors: [RGB(0xFFFFFF)], alpha: 0.45...0.7,
             avoidCentre: 0.42)
    },
    shadow: RGB(0x3A4A8A), shadowAlpha: 0.3)

let sunset = Variant(
    id: "Sunset", title: "Golden Hour", caption: "Warm light over a lilac sea",
    look: Look(finish: .satin(0.3), color: { s in
        ramp([RGB(0xFFDA7A), RGB(0xFF8A5B), RGB(0xE84B7E), RGB(0x9A3FB0)], (2.6 - s.p.y) / 5.2)
    }, studio: Studio(top: RGB(0xFFE6C0), horizon: RGB(0xFF8A6A), floor: RGB(0x3A2060), key: 1, warmth: 0.5)),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0x4B2E93), RGB(0xC2508E), RGB(0xFF8E5E), RGB(0xFFC772)])
        radial(ctx, s, at: CGPoint(x: 0.5, y: 0.36), radius: 0.3, [RGB(0xFFF4C8), RGB(0xFFD27A), RGB(0xFFB060)],
               alpha: [1, 0.8, 0])
        let sea = CGRect(x: 0, y: 0, width: s, height: s * 0.3)
        ctx.saveGState(); ctx.clip(to: sea)
        linear(ctx, s * 0.3, [RGB(0x7A3E9A), RGB(0x3A2470)])
        for i in 0..<6 {
            let y = s * 0.3 * (1 - pow(CGFloat(i + 1) / 7, 1.4)), w = s * (0.34 - CGFloat(i) * 0.04)
            ctx.setFillColor(RGB(0xFFD27A).cg(0.55 - Double(i) * 0.07))
            ctx.fill(CGRect(x: s / 2 - w / 2, y: y, width: w, height: s * 0.012))
        }
        ctx.restoreGState()
    },
    shadow: RGB(0x3A1050), shadowAlpha: 0.35, glow: RGB(0xFFB070), glowAlpha: 0.2)

/// Glossy aqua with dancing caustics.
func oceanColor(_ s: Surface) -> RGB {
    let p = s.p
    let c = sin(p.x * 4 + 1.6 * sin(p.y * 3.1)) * sin(p.y * 4.3 + 1.4 * sin(p.x * 2.7))
    return toned(s, RGB(0x4FF0DA), RGB(0x1A7FC0)).mix(RGB(0xE6FFFB), pow(max(0, c), 3) * 0.55 * smoothstep(-0.2, 0.6, s.n.y))
}

let ocean = Variant(
    id: "Ocean", title: "Deep Sea", caption: "Aqua, caustics and a few bubbles",
    look: Look(finish: .satin(0.18), color: oceanColor,
               studio: Studio(top: RGB(0xE0FFFF), horizon: RGB(0x2A8AC0), floor: RGB(0x062040), key: 1)),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0x1A7FC8), RGB(0x0D4C92), RGB(0x06234F)])
        bands(ctx, s, angle: 0.35, period: 0.14, duty: 0.32, color: RGB(0xFFFFFF), alpha: 0.07, blur: 0.02,
              blend: .screen)
        dots(ctx, s, seed: 29, count: 16, size: 0.008...0.024, colors: [RGB(0xD8FAFF)], alpha: 0.4...0.75,
             avoidCentre: 0.42, ring: true)
    },
    shadow: RGB(0x001A3A), shadowAlpha: 0.5)

/// Matcha: dusty green, with a powdering of lighter tea.
func matchaColor(_ s: Surface) -> RGB {
    let dust = smoothstep(0.55, 0.75, valueNoise(s.p * 6))
    return toned(s, RGB(0xA3BD6E), RGB(0x6A8840)).mix(RGB(0xD8E6B4), dust * 0.5 * smoothstep(0, 0.6, s.n.y))
}

let matcha = Variant(
    id: "Matcha", title: "Matcha Latte", caption: "Whisked green tea on oat-milk foam",
    look: Look(finish: .matte, color: matchaColor,
               studio: Studio(top: RGB(0xFFFFFF), horizon: RGB(0xF0E4CC), floor: RGB(0x6A5A40), key: 0.7),
               lighting: Lighting(key: 1.6, fill: 0.35, rim: 0.5, shadowSoftness: 16, shadow: 0.4)),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0xFBF3E4), RGB(0xF3E6CF), RGB(0xE8D6B8)])
        dots(ctx, s, seed: 31, count: 90, size: 0.0015...0.005, colors: [RGB(0x8DB04A)], alpha: 0.25...0.55,
             avoidCentre: 0.4)
    },
    shadow: RGB(0x5A4A20), shadowAlpha: 0.3)

/// Holographic foil: hue shifts with the viewing angle and along the strand.
func holoColor(_ s: Surface) -> RGB {
    let hue = fract(0.55 + (1 - s.facing) * 0.9 + s.p.y * 0.07 + s.u * 1.5)
    return RGB.hsv(hue, 0.42, 1).mix(RGB(0xFFFFFF), pow(s.facing, 6) * 0.3)
}

let holo = Variant(
    id: "Holo", title: "Holo Foil", caption: "A rare trading card, shimmering every color",
    look: Look(finish: .satin(0.16), color: holoColor,
               studio: Studio(top: RGB(0xFFFFFF), horizon: RGB(0xE0D8FF), floor: RGB(0x8A80B0), key: 1, bands: 0.3)),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0xEBE4FF), RGB(0xDCF5F2), RGB(0xFFE3F1)], tilt: 0.35)
        sparkles(ctx, s, [(0.14, 0.84, 0.032), (0.85, 0.85, 0.02), (0.86, 0.15, 0.026), (0.13, 0.16, 0.016)],
                 color: RGB(0xFFFFFF))
    },
    shadow: RGB(0x6A4AA8), shadowAlpha: 0.3)

/// Peppermint: a red helix with a thin second stripe.
func candyColor(_ s: Surface) -> RGB {
    let x = s.u * 34 + s.v
    let red = stripe(x, duty: 0.36, soft: 0.05), thin = stripe(x - 0.55, duty: 0.08, soft: 0.04)
    return RGB(0xFFFBF7).mix(RGB(0xE8283C), red).mix(RGB(0x2FB872), thin)
}

let candy = Variant(
    id: "Candy", title: "Candy Cane", caption: "Peppermint stripes, all twisted up",
    look: Look(finish: .satin(0.2), color: candyColor,
               studio: Studio(top: RGB(0xFFFFFF), horizon: RGB(0xD8F4E6), floor: RGB(0x5A8A70), key: 1.1)),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0xD9F7E8), RGB(0xBDEFD8), RGB(0xA2E3C5)])
        dots(ctx, s, seed: 37, count: 40, size: 0.004...0.011, colors: [RGB(0xFFFFFF)], alpha: 0.6...0.95,
             avoidCentre: 0.4)
    },
    shadow: RGB(0x1E5A3E), shadowAlpha: 0.32)

let graphite = Variant(
    id: "Graphite", title: "Graphite", caption: "Quiet charcoal on brushed silver",
    look: Look(finish: .satin(0.32), color: { s in toned(s, RGB(0x5A5E6A), RGB(0x2C2F36)) },
               studio: Studio(top: RGB(0xFFFFFF), horizon: RGB(0xB8BCC6), floor: RGB(0x3A3C42), key: 1)),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0xF4F5F8), RGB(0xE1E3E8), RGB(0xC9CCD4)])
        pool(ctx, s, at: CGPoint(x: 0.3, y: 0.85), radius: 0.6, RGB(0xFFFFFF), 0.6)
    },
    shadow: RGB(0x1A1C22), shadowAlpha: 0.35)

let bubblegum = Variant(
    id: "Bubblegum", title: "Bubblegum", caption: "Pink, chewy and about to pop",
    look: Look(finish: .satin(0.3), color: { s in toned(s, RGB(0xFF9CCB), RGB(0xF2559C)).mix(RGB(0xFFE08A), crossing(s) * 0.6) },
               studio: Studio(top: RGB(0xFFFFFF), horizon: RGB(0xF0D8FF), floor: RGB(0x8A5AA8), key: 1)),
    ground: { ctx, s in
        linear(ctx, s, [RGB(0xEADCFF), RGB(0xD8C2FF), RGB(0xC2A6FA)])
        dots(ctx, s, seed: 41, count: 9, size: 0.02...0.055, colors: [RGB(0xFFFFFF)], alpha: 0.5...0.8,
             avoidCentre: 0.44, ring: true)
    },
    shadow: RGB(0x6A2A8A), shadowAlpha: 0.32)

// MARK: Sunset Drive (special edition)

/// A palm silhouette: a trunk leaning from `base` to `crown` (fractions of the icon) and a burst of fronds.
func palm(_ ctx: CGContext, _ s: CGFloat, base: CGPoint, crown: CGPoint, lean: CGFloat, size: CGFloat, color: RGB) {
    let b = CGPoint(x: base.x * s, y: base.y * s), c = CGPoint(x: crown.x * s, y: crown.y * s), r = size * s
    let bend = CGPoint(x: (b.x + c.x) / 2 + lean * s, y: (b.y + c.y) / 2)
    ctx.setFillColor(color.cg())
    // Trunk: a tapered curve, wide at the foot.
    let foot = r * 0.13, top = r * 0.05
    let trunk = CGMutablePath()
    trunk.move(to: CGPoint(x: b.x - foot, y: b.y))
    trunk.addQuadCurve(to: CGPoint(x: c.x - top, y: c.y), control: CGPoint(x: bend.x - (foot + top) / 2, y: bend.y))
    trunk.addLine(to: CGPoint(x: c.x + top, y: c.y))
    trunk.addQuadCurve(to: CGPoint(x: b.x + foot, y: b.y), control: CGPoint(x: bend.x + (foot + top) / 2, y: bend.y))
    trunk.closeSubpath()
    ctx.addPath(trunk); ctx.fillPath()
    // Fronds: long drooping leaves, each a crescent from the crown out to its tip.
    for (angle, length, droop) in [(0.25, 1.0, 0.55), (0.95, 0.9, 0.4), (1.6, 0.7, 0.15), (2.25, 0.92, -0.4),
                                   (2.95, 1.0, -0.55), (-0.35, 0.75, 0.7), (3.5, 0.72, -0.7)] as [(CGFloat, CGFloat, CGFloat)] {
        let tip = CGPoint(x: c.x + cos(angle) * r * length, y: c.y + sin(angle) * r * length - r * 0.35 * abs(cos(angle)))
        let mid = CGPoint(x: (c.x + tip.x) / 2, y: (c.y + tip.y) / 2)
        let normal = CGPoint(x: -sin(angle), y: cos(angle))
        let lift = r * 0.32 * (droop >= 0 ? 1 : -1) * (0.6 + abs(droop) * 0.4), width = r * 0.16
        let leaf = CGMutablePath()
        leaf.move(to: c)
        leaf.addQuadCurve(to: tip, control: CGPoint(x: mid.x + normal.x * (lift + width), y: mid.y + normal.y * (lift + width) + r * 0.12))
        leaf.addQuadCurve(to: c, control: CGPoint(x: mid.x + normal.x * (lift - width), y: mid.y + normal.y * (lift - width) - r * 0.02))
        ctx.addPath(leaf); ctx.fillPath()
    }
}

/// Glossy Miami teal, blushing hot pink where the strands cross; the sunset studio puts a pink rim on it.
func driveColor(_ s: Surface) -> RGB {
    toned(s, RGB(0x5CF5E6), RGB(0x0B8FB0)).mix(RGB(0xFF4FA8), crossing(s) * 0.9)
}

let drive = Variant(
    id: "Drive", title: "Sunset Drive", caption: "Special edition: palms, a neon sun and the top down",
    look: Look(finish: .satin(0.24), color: driveColor,
               studio: Studio(top: RGB(0xFFF0F8), horizon: RGB(0xFF5FA0), floor: RGB(0x2A0A4A), key: 1.1,
                              warm: RGB(0xFF8A3D), warmth: 0.6)),
    ground: { ctx, s in
        // Sky: violet overhead, magenta, then orange at the horizon.
        let horizon: CGFloat = 0.3
        linear(ctx, s, [RGB(0x1E0B4A), RGB(0x5A1A8C), RGB(0xD8337F), RGB(0xFF7A45), RGB(0xFFB45A)])
        dots(ctx, s, seed: 43, count: 26, size: 0.0015...0.004, colors: [RGB(0xFFFFFF), RGB(0xFFD2EC)],
             alpha: 0.4...0.9, avoidCentre: 0.42)
        // A banded retro sun sitting on the horizon.
        let sun = canvas(Int(s)), c = CGPoint(x: 0.5 * s, y: 0.52 * s), r = 0.36 * s
        sun.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)); sun.clip()
        sun.drawLinearGradient(gradient([RGB(0xFFF27A).cg(), RGB(0xFFB13B).cg(), RGB(0xFF3E8A).cg()]),
                               start: CGPoint(x: 0, y: c.y + r), end: CGPoint(x: 0, y: c.y - r), options: [])
        sun.setBlendMode(.clear)
        for i in 0..<6 {
            let t = CGFloat(i) / 6, y = c.y - r * 0.05 - t * r * 0.9, h = r * (0.025 + t * 0.07)
            sun.fill(CGRect(x: 0, y: y - h, width: s, height: h))
        }
        let disc = sun.makeImage()!
        pool(ctx, s, at: CGPoint(x: 0.5, y: 0.45), radius: 0.55, RGB(0xFF5FA0), 0.55, blend: .screen)
        ctx.saveGState(); ctx.clip(to: CGRect(x: 0, y: horizon * s, width: s, height: s))
        ctx.setShadow(offset: .zero, blur: s * 0.06, color: RGB(0xFF6A9A).cg(0.9))
        ctx.draw(disc, in: CGRect(x: 0, y: 0, width: s, height: s))
        ctx.restoreGState()
        // The sea: deep violet, with the sun's light breaking up on the swell.
        let sea = CGRect(x: 0, y: 0, width: s, height: s * horizon)
        ctx.saveGState(); ctx.clip(to: sea)
        ctx.drawLinearGradient(gradient([RGB(0x6A1F8A).cg(), RGB(0x2A0D52).cg(), RGB(0x14072E).cg()]),
                               start: CGPoint(x: 0, y: s * horizon), end: .zero, options: [])
        for i in 0..<7 {
            let f = CGFloat(i + 1) / 8, y = s * horizon * (1 - pow(f, 1.3)), w = s * (0.42 - CGFloat(i) * 0.045)
            ctx.setFillColor(RGB(0xFFB45A).mix(RGB(0xFF3E8A), Double(f)).cg(0.75 - Double(i) * 0.08))
            ctx.fill(CGRect(x: s / 2 - w / 2, y: y, width: w, height: s * 0.011))
        }
        ctx.restoreGState()
        // A neon line along the horizon.
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.02, color: RGB(0xFF4FB0).cg(1))
        ctx.setFillColor(RGB(0xFFD0EA).cg()); ctx.fill(CGRect(x: 0, y: s * horizon - s * 0.003, width: s, height: s * 0.006))
        ctx.restoreGState()
        // Palms framing the scene, rimmed in pink by the sunset.
        let shade = RGB(0x160631)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: s * 0.012, color: RGB(0xFF4FB0).cg(0.8))
        palm(ctx, s, base: CGPoint(x: 0.1, y: -0.02), crown: CGPoint(x: 0.13, y: 0.78), lean: -0.05, size: 0.19, color: shade)
        palm(ctx, s, base: CGPoint(x: 0.95, y: -0.02), crown: CGPoint(x: 0.89, y: 0.64), lean: 0.04, size: 0.15, color: shade)
        ctx.restoreGState()
    },
    shadow: RGB(0x1A0533), shadowAlpha: 0.5, glow: RGB(0xFF3FA4), glowAlpha: 0.45,
    scale: 0.66)

/// The whole family, in picker order. The first is the primary icon.
let variants: [Variant] = [classic, flatDarkVariant, glossy, midnight, noir, neon, wood, salted, chocolate, glass, chrome, gold, marble, clay,
                           sunset, ocean, matcha, holo, candy, graphite, bubblegum, drive]

/// iOS dark appearance of the primary icon: the same flat knot on black.
let classicDark = flatDarkVariant
/// iOS tinted appearance: the flat knot in grayscale on transparency; the system supplies the tint.
let classicTinted = Variant(id: "Tinted", title: "Tinted", caption: "", look: Look(color: classicColor),
                            ground: { _, _ in }, shadowAlpha: 0, flat: flatTinted)
