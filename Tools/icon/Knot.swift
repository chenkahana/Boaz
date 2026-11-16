import Foundation
import simd

typealias Vec = SIMD3<Double>

/// The pretzel: a trefoil knot laid out with two upper loops and one lower loop. Following the curve, each
/// crossing goes over, then under, then over, so the tube reads as one strand tied in a knot. `depth` lifts the
/// strands apart where they cross; `belly` fattens the lower loop the way a baked pretzel's belly rises.
struct Knot {
    var lobe = 1.75
    var depth = 0.7
    var radius = 0.6
    var belly = 0.0
    var squash = 0.15
    var widen = 0.5
    var lean = 0.0
    var narrow = 0.1
    var raise = 0.15

    /// y up, z toward the viewer.
    func point(_ t: Double) -> Vec {
        var p = Vec(-sin(t) - lobe * sin(2 * t), cos(t) - lobe * cos(2 * t), -depth * sin(3 * t))
        // Pull the lower loop in toward the middle and widen it, so it reads as the pretzel's belly.
        let low = smoothstep(0.2, -2.2, p.y)
        p.y *= 1 - squash * low
        p.x *= 1 + widen * low
        // Upper loops a little taller than wide.
        let high = smoothstep(-0.3, 1.5, p.y)
        p.x *= 1 - narrow * high
        p.y *= 1 + raise * high
        p.y += 0.3
        // The lower loop leans toward the viewer: it sits in front of both upper loops.
        p.z += lean * p.y
        return p
    }

    func radius(at t: Double) -> Double {
        guard belly != 0 else { return radius }
        // t = π is the bottom of the lower loop.
        let d = atan2(sin(t - .pi), cos(t - .pi))
        return radius * (1 + belly * exp(-d * d / 0.5) - belly * 0.35 * exp(-pow(abs(d) - 2.1, 2) / 0.3))
    }
}

/// A closed tube swept along the knot, with rotation-minimizing frames so stripes and grain don't twist.
struct Tube {
    var positions: [Vec] = []
    var normals: [Vec] = []
    /// u along the strand (0…1), v around it (0…1, 0 = facing outward from the knot's centre plane).
    var uv: [SIMD2<Double>] = []
    var param: [Double] = []
    var indices: [UInt32] = []
    var centres: [Vec] = []
    var radii: [Double] = []
    let segments: Int
    let sides: Int

    init(_ knot: Knot, segments: Int = 900, sides: Int = 72) {
        self.segments = segments
        self.sides = sides
        let n = segments
        let ts = (0..<n).map { Double($0) / Double(n) * 2 * .pi }
        let xs = ts.map(knot.point)
        let tangents = (0..<n).map { i in simd_normalize(xs[(i + 1) % n] - xs[(i + n - 1) % n]) }
        // Double-reflection rotation-minimizing frames (Wang et al. 2008).
        var r = [Vec](repeating: .zero, count: n + 1)
        let seed = abs(tangents[0].z) < 0.9 ? Vec(0, 0, 1) : Vec(1, 0, 0)
        r[0] = simd_normalize(seed - simd_dot(seed, tangents[0]) * tangents[0])
        for i in 0..<n {
            let j = (i + 1) % n
            let v1 = xs[j] - xs[i], c1 = simd_dot(v1, v1)
            let rL = r[i] - (2 / c1) * simd_dot(v1, r[i]) * v1
            let tL = tangents[i] - (2 / c1) * simd_dot(v1, tangents[i]) * v1
            let v2 = tangents[j] - tL, c2 = simd_dot(v2, v2)
            r[i + 1] = c2 < 1e-12 ? rL : rL - (2 / c2) * simd_dot(v2, rL) * v2
        }
        // Spread the closing twist evenly so the seam disappears.
        let t0 = tangents[0]
        let twist = atan2(simd_dot(simd_cross(r[n], r[0]), t0), simd_dot(r[n], r[0]))
        centres = xs
        radii = ts.map(knot.radius(at:))
        for i in 0...n {
            let k = i % n, t = tangents[k]
            let angle = twist * Double(i) / Double(n)
            var normal = r[i]
            let binormal0 = simd_cross(t, normal)
            normal = cos(angle) * normal + sin(angle) * binormal0
            let binormal = simd_cross(t, normal)
            for s in 0...sides {
                let theta = Double(s) / Double(sides) * 2 * .pi
                let dir = cos(theta) * normal + sin(theta) * binormal
                positions.append(xs[k] + radii[k] * dir)
                normals.append(dir)
                uv.append(SIMD2(Double(i) / Double(n), Double(s) / Double(sides)))
                param.append(ts[k])
            }
        }
        let row = UInt32(sides + 1)
        for i in 0..<UInt32(n) {
            for s in 0..<UInt32(sides) {
                let a = i * row + s, b = (i + 1) * row + s
                indices += [a, a + 1, b, a + 1, b + 1, b]
            }
        }
    }

    /// Ambient occlusion from the other strands: where one strand passes close over another, both darken.
    func occlusion(strength: Double = 1) -> [Double] {
        let n = centres.count, step = max(1, n / 300)
        let samples = stride(from: 0, to: n, by: step).map { ($0, centres[$0], radii[$0]) }
        let ds = 2 * Double.pi / Double(samples.count)
        return positions.indices.map { i in
            let p = positions[i], nrm = normals[i], own = Int(param[i] / (2 * .pi) * Double(n))
            var occ = 0.0
            for (k, c, rad) in samples {
                var gap = abs(k - own); gap = min(gap, n - gap)
                if gap < n / 14 { continue }
                let d = c - p, len = simd_length(d)
                let facing = max(0, simd_dot(nrm, d / len))
                let surface = max(0, len - rad)
                occ += facing * exp(-surface / (rad * 0.9)) * ds
            }
            return max(0, 1 - strength * occ * 1.6)
        }
    }
}
