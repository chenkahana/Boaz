import AppKit
import Metal
import SceneKit

/// One point on the tube's surface, for computing its color. `view` points at the camera.
struct Surface {
    let p: Vec, n: Vec, u: Double, v: Double, t: Double, occlusion: Double
    var view: Vec { simd_normalize(Vec(0, 0, 40) - p) }
    /// 1 where the surface faces the camera, 0 at the silhouette.
    var facing: Double { max(0, simd_dot(n, view)) }
}

enum Finish {
    /// Glossy plastic or glaze: roughness 0 (mirror) … 1 (chalk).
    case satin(Double)
    case metal(Double)
    case matte
    /// Clear glass: the background shows through, bent (see `Look.refraction`).
    case glass
    /// Lit from inside; no shading.
    case glow
}

/// The studio around the knot: what glossy and metal surfaces reflect.
struct Studio {
    var top = RGB(0xFFFFFF), horizon = RGB(0xE8E4F0), floor = RGB(0x8A8070)
    /// Large soft box up and to the left of the camera.
    var key = 1.0
    var keyColor = RGB(0xFFFFFF)
    /// Hard-edged white bands, for chrome.
    var bands = 0.0
    var bandColor = RGB(0xFFFFFF)
    var warm = RGB(0xFFB48A), warmth = 0.0
    var intensity = 1.0
}

struct Lighting {
    var key = 1.4
    var keyDirection = Vec(-0.55, 0.75, 0.62)
    var fill = 0.25
    var rim = 0.6
    var shadowSoftness = 12.0
    var shadow = 0.55
}

/// Everything that makes one icon's pretzel look the way it does.
struct Look {
    var knot = Knot()
    var finish = Finish.satin(0.38)
    var color: (Surface) -> RGB
    var studio = Studio()
    var lighting = Lighting()
    var occlusion = 1.0
    /// Little things stuck to the pretzel: salt, sprinkles.
    var toppings: ((Tube, inout Noise) -> [SCNNode])?
    /// Glass only: how much the background behind it is magnified, and the glass's own color.
    var refraction = 1.12
    var tint: RGB? = nil
}

let device = MTLCreateSystemDefaultDevice()!

/// The equirectangular environment the knot reflects: sky, horizon, floor, a key soft box and optional bands.
func environment(_ s: Studio) -> CGImage {
    let w = 1024, h = 512
    let ctx = canvas(w, h, alpha: false)
    let data = ctx.data!.bindMemory(to: UInt8.self, capacity: ctx.bytesPerRow * h)
    for y in 0..<h {
        // Row 0 of the bitmap is the bottom of the image in CG; SceneKit reads the image top = up.
        let lat = (Double(y) / Double(h - 1) - 0.5) * .pi   // -π/2 bottom … π/2 top
        for x in 0..<w {
            let lon = (Double(x) / Double(w) - 0.5) * 2 * .pi
            let d = Vec(sin(lon) * cos(lat), sin(lat), -cos(lon) * cos(lat))
            var c = lat > 0 ? s.horizon.mix(s.top, pow(sin(lat), 0.7)) : s.horizon.mix(s.floor, pow(-sin(lat), 0.5))
            // Key soft box: behind the camera (+z), up and to the left.
            let keyDir = simd_normalize(Vec(-0.5, 0.65, 0.6))
            let k = simd_dot(d, keyDir)
            let box = smoothstep(0.86, 0.95, k)
            c = c.mix(s.keyColor.scaled(1.0), box * s.key)
            // A warm bounce from the lower right.
            let warmDir = simd_normalize(Vec(0.7, -0.2, 0.5))
            c = c.mix(s.warm, smoothstep(0.6, 1.0, simd_dot(d, warmDir)) * s.warmth)
            if s.bands > 0 {
                let band = smoothstep(0.02, 0.0, abs(sin(lat * 5.0 + 0.4)) - 0.12)
                c = c.mix(s.bandColor, band * s.bands * (lat > -0.1 ? 1 : 0.35))
            }
            let i = y * ctx.bytesPerRow + x * 4
            data[i] = UInt8(min(255, c.r * 255 * s.intensity)); data[i + 1] = UInt8(min(255, c.g * 255 * s.intensity))
            data[i + 2] = UInt8(min(255, c.b * 255 * s.intensity)); data[i + 3] = 255
        }
    }
    return ctx.makeImage()!
}

func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = min(max((x - a) / (b - a), 0), 1)
    return t * t * (3 - 2 * t)
}

private var tubeCache: [String: (Tube, [Double])] = [:]

func tube(for knot: Knot) -> (Tube, [Double]) {
    let key = "\(knot.narrow) \(knot.raise) \(knot.squash) \(knot.widen) \(knot.lobe) \(knot.depth) \(knot.radius) \(knot.belly)"
    if let hit = tubeCache[key] { return hit }
    let t = Tube(knot)
    let value = (t, t.occlusion())
    tubeCache[key] = value
    return value
}

/// The knot's framing: the camera fits the whole tube with this much margin, the same for every look.
struct Frame {
    static let fov: CGFloat = 10
    /// The render leaves this much room around the knot for antialiasing and toppings.
    static let margin = 1.08
    static var distance: Double = {
        let (t, _) = tube(for: Knot())
        let extent = t.positions.reduce(0.0) { max($0, max(abs($1.x), abs($1.y))) }
        return extent * margin / tan(Double(fov) / 2 * .pi / 180)
    }()
}

/// Renders the knot alone on transparency, `px` square, centered.
func renderKnot(_ look: Look, px: Int) -> CGImage {
    let (tube, occlusion) = tube(for: look.knot)
    var colors: [Float] = []
    colors.reserveCapacity(tube.positions.count * 4)
    for i in tube.positions.indices {
        let ao = 1 - (1 - occlusion[i]) * look.occlusion
        let s = Surface(p: tube.positions[i], n: tube.normals[i], u: tube.uv[i].x, v: tube.uv[i].y, t: tube.param[i],
                        occlusion: ao)
        var c = look.color(s)
        if case .glow = look.finish {} else { c = c.scaled(ao) }
        // SceneKit treats vertex colors as linear.
        colors += [Float(pow(c.r, 2.2)), Float(pow(c.g, 2.2)), Float(pow(c.b, 2.2)), 1]
    }
    let vertices = tube.positions.map { SCNVector3($0.x, $0.y, $0.z) }
    let normals = tube.normals.map { SCNVector3($0.x, $0.y, $0.z) }
    let uvs = tube.uv.map { CGPoint(x: $0.x, y: $0.y) }
    let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
    let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: tube.positions.count,
                                        usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4,
                                        dataOffset: 0, dataStride: 16)
    let element = SCNGeometryElement(indices: tube.indices, primitiveType: .triangles)
    let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                                         SCNGeometrySource(textureCoordinates: uvs), colorSource],
                               elements: [element])
    let material = SCNMaterial()
    material.lightingModel = .physicallyBased
    material.diffuse.contents = NSColor.white
    switch look.finish {
    case .satin(let r): material.roughness.contents = r; material.metalness.contents = 0.0
    case .metal(let r): material.roughness.contents = r; material.metalness.contents = 1.0
    case .matte: material.roughness.contents = 0.92; material.metalness.contents = 0.0
    case .glass:
        // Only the reflections: a black, mirror-smooth body that the compositor screens over what's behind.
        material.roughness.contents = 0.04; material.metalness.contents = 0.0
    case .glow:
        material.lightingModel = .constant
    }
    geometry.materials = [material]

    let scene = SCNScene()
    scene.background.contents = NSColor.clear
    scene.lightingEnvironment.contents = environment(look.studio)
    scene.lightingEnvironment.intensity = look.studio.intensity * 1.2
    let node = SCNNode(geometry: geometry)
    scene.rootNode.addChildNode(node)
    var noise = Noise(7)
    for topping in look.toppings?(tube, &noise) ?? [] { node.addChildNode(topping) }

    let camera = SCNCamera()
    camera.fieldOfView = Frame.fov
    camera.zNear = 1; camera.zFar = 200
    let cameraNode = SCNNode()
    cameraNode.camera = camera
    cameraNode.position = SCNVector3(0, 0, Frame.distance)
    scene.rootNode.addChildNode(cameraNode)

    func light(_ type: SCNLight.LightType, _ intensity: Double, _ dir: Vec, shadow: Bool = false) {
        let l = SCNLight()
        l.type = type
        l.intensity = intensity * 1000
        l.color = NSColor.white
        if shadow {
            l.castsShadow = true
            l.shadowMode = .forward
            l.shadowMapSize = CGSize(width: 4096, height: 4096)
            l.shadowRadius = look.lighting.shadowSoftness
            l.shadowSampleCount = 32
            l.shadowColor = NSColor(white: 0, alpha: look.lighting.shadow)
            l.orthographicScale = 6
            l.automaticallyAdjustsShadowProjection = true
        }
        let n = SCNNode()
        n.light = l
        n.position = SCNVector3(dir.x * 20, dir.y * 20, dir.z * 20)
        n.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(n)
    }
    if case .glow = look.finish {} else {
        light(.directional, look.lighting.key, look.lighting.keyDirection, shadow: true)
        light(.directional, look.lighting.rim, Vec(0.6, 0.5, -0.6))
        light(.directional, look.lighting.fill, Vec(0.5, -0.3, 0.8))
    }

    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = scene
    renderer.pointOfView = cameraNode
    let image = renderer.snapshot(atTime: 0, with: CGSize(width: px, height: px), antialiasingMode: .multisampling4X)
    return cgImage(image)
}
