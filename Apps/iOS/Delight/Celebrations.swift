import SwiftUI

/// App-wide celebration requests. RootView hosts the confetti layer; anything can ask for a burst.
@Observable
final class Celebration {
    static let shared = Celebration()
    private(set) var bursts = 0

    func confetti() { bursts += 1 }
}

extension View {
    /// Confetti cannons fire from both bottom corners each time `trigger` changes. Haptic only under Reduce Motion.
    func confetti(trigger: Int) -> some View { modifier(BurstModifier(trigger: trigger, duration: ConfettiCanvas.duration,
                                                                     feedback: .success) { ConfettiCanvas(start: $0, seed: trigger) }) }

    /// A few four-point stars pop out of the view each time `trigger` changes.
    func sparkle(trigger: Int) -> some View { modifier(BurstModifier(trigger: trigger, duration: SparkleCanvas.duration,
                                                                    feedback: nil) { SparkleCanvas(start: $0, seed: trigger) }) }
}

/// Shows a short-lived, non-interactive overlay that starts on each trigger change.
private struct BurstModifier<Overlay: View>: ViewModifier {
    let trigger: Int
    let duration: Double
    let feedback: SensoryFeedback?
    @ViewBuilder let overlay: (Date) -> Overlay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?

    func body(content: Content) -> some View {
        content
            .overlay {
                if let start {
                    overlay(start)
                        .allowsHitTesting(false)
                        .task(id: start) {
                            try? await Task.sleep(for: .seconds(duration))
                            if self.start == start { self.start = nil }
                        }
                }
            }
            .onChange(of: trigger) { if !reduceMotion { start = .now } }
            .sensoryFeedback(trigger: trigger) { _, _ in feedback }
    }
}

/// Small deterministic RNG so a burst's particles are stable across frames.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: Int) { state = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Arc-palette confetti: paper bits with drag, gravity, spin and a 3D-ish flip.
struct ConfettiCanvas: View {
    static let duration = 2.8
    static let colors = [Theme.brand, Theme.peach, Theme.electric, Theme.violet, Theme.yellow]

    private struct Piece {
        var fromLeft: Bool
        var velocity: CGVector
        var size: CGSize
        var spin: Double
        var flip: Double
        var phase: Double
        var color: Int
        var round: Bool
    }

    let start: Date
    private let pieces: [Piece]

    init(start: Date, seed: Int) {
        self.start = start
        var rng = SplitMix(seed: seed)
        pieces = (0..<110).map { i in
            let fromLeft = i.isMultiple(of: 2)
            let angle = Double.random(in: 52...80, using: &rng) * .pi / 180
            let speed = Double.random(in: 900...1600, using: &rng)
            return Piece(fromLeft: fromLeft,
                         velocity: CGVector(dx: cos(angle) * speed * (fromLeft ? 1 : -1), dy: -sin(angle) * speed),
                         size: CGSize(width: .random(in: 6...10, using: &rng), height: .random(in: 9...15, using: &rng)),
                         spin: .random(in: -9...9, using: &rng), flip: .random(in: 6...14, using: &rng),
                         phase: .random(in: 0...(2 * .pi), using: &rng), color: .random(in: 0..<Self.colors.count, using: &rng),
                         round: Int.random(in: 0..<5, using: &rng) == 0)
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                let drag = 2.2, gravity = 700.0
                let decay = (1 - exp(-drag * t)) / drag
                context.opacity = min(1, max(0, (Self.duration - t) / 0.7))
                for piece in pieces {
                    let x = (piece.fromLeft ? -8 : size.width + 8) + piece.velocity.dx * decay
                    let y = size.height * 0.92 + gravity / drag * t + (piece.velocity.dy - gravity / drag) * decay
                    var bit = context
                    bit.translateBy(x: x, y: y)
                    bit.rotate(by: .radians(piece.phase + piece.spin * t))
                    let w = piece.size.width, h = piece.size.height * abs(cos(piece.phase + piece.flip * t))
                    let rect = CGRect(x: -w / 2, y: -h / 2, width: w, height: max(h, 1.5))
                    let path = piece.round ? Path(ellipseIn: CGRect(x: -w / 2, y: -w / 2, width: w, height: w * abs(cos(piece.flip * t)) + 1))
                                           : Path(roundedRect: rect, cornerRadius: 1.5)
                    bit.fill(path, with: .color(Self.colors[piece.color]))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Four-point stars that pop outward and fade — used on favorite taps.
struct SparkleCanvas: View {
    static let duration = 0.7

    private struct Star { var angle: Double; var distance: Double; var size: Double; var color: Color }

    let start: Date
    private let stars: [Star]

    init(start: Date, seed: Int) {
        self.start = start
        var rng = SplitMix(seed: seed)
        let colors = [Theme.yellow, Theme.peach, Color.white]
        stars = (0..<7).map { i in
            Star(angle: Double(i) / 7 * 2 * .pi + .random(in: -0.3...0.3, using: &rng),
                 distance: .random(in: 26...44, using: &rng), size: .random(in: 6...11, using: &rng),
                 color: colors[i % colors.count])
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let p = min(1, timeline.date.timeIntervalSince(start) / Self.duration)
            let ease = 1 - pow(1 - p, 3)
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for star in stars {
                    let point = CGPoint(x: center.x + cos(star.angle) * star.distance * ease,
                                        y: center.y + sin(star.angle) * star.distance * ease)
                    let scale = sin(p * .pi) * star.size
                    var ctx = context
                    ctx.opacity = 1 - p * p
                    ctx.fill(Self.star(at: point, arm: scale), with: .color(star.color))
                }
            }
        }
        .padding(-50)
    }

    static func star(at c: CGPoint, arm: Double) -> Path {
        let waist = arm * 0.22
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - arm))
        path.addQuadCurve(to: CGPoint(x: c.x + arm, y: c.y), control: CGPoint(x: c.x + waist, y: c.y - waist))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + arm), control: CGPoint(x: c.x + waist, y: c.y + waist))
        path.addQuadCurve(to: CGPoint(x: c.x - arm, y: c.y), control: CGPoint(x: c.x - waist, y: c.y + waist))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - arm), control: CGPoint(x: c.x - waist, y: c.y - waist))
        return path
    }
}
