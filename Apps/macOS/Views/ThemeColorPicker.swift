import BoazKit
import SwiftUI

/// Arc's Edit Theme Color, in Customize Space: up to three colors picked on a field of hues (one paints the
/// background, more make a gradient), the appearance, a texture and how much of the desktop shows through.
struct ThemeColorPicker: View {
    typealias RGBA = WindowTheme.RGBA
    @Binding var options: SpaceThemeOptions
    /// The handle a click on the field or a swatch moves.
    @State private var selected = 0
    @State private var page = 0

    private static let hues: [(name: String, hue: Double)] = [("Red", 0), ("Orange", 0.07), ("Yellow", 0.13),
                                                               ("Green", 0.3), ("Teal", 0.47), ("Blue", 0.58),
                                                               ("Indigo", 0.7), ("Pink", 0.86)]
    /// The swatch pages: rows of the field from pale to deep.
    private static let pages: [(name: String, depth: Double)] = [("Pale", 0.15), ("Soft", 0.45), ("Deep", 0.85)]

    /// The background color, then the gradient's others.
    private var colors: [RGBA] { [options.light] + options.gradient }

    var body: some View {
        VStack(spacing: 12) {
            appearance
            field
            HStack {
                Text("Tap to pick a color for this space").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { removeColor() } label: { Image(systemName: "minus") }
                    .disabled(colors.count < 2)
                    .accessibilityLabel("Remove Color")
                Button { addColor() } label: { Image(systemName: "plus") }
                    .disabled(colors.count > 2)
                    .accessibilityLabel("Add Color")
            }
            swatches
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Texture", selection: $options.texture) {
                        ForEach(WindowTheme.Texture.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    // Labeled, a Form lays the menu out across its row, wider than the sheet.
                    .labelsHidden()
                    .fixedSize()
                    WavySlider(value: $options.textureIntensity)
                        .disabled(options.texture == .none)
                        .opacity(options.texture == .none ? 0.4 : 1)
                }
                TranslucencyDial(value: $options.translucency)
            }
            Toggle("Light Streak", isOn: $options.lightStreak).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Appearance

    private var appearance: some View {
        HStack(spacing: 8) {
            ForEach([(SpaceThemeOptions.Appearance.system, "sparkles", "Automatic"), (.light, "sun.max", "Light"),
                     (.dark, "moon", "Dark")], id: \.0) { mode, symbol, name in
                let on = options.appearance == mode
                Button { options.appearance = mode } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 30, height: 30)
                        .background(on ? Color.primary.opacity(0.12) : .clear, in: .circle)
                        .overlay { if on { Circle().strokeBorder(Color.accentColor, lineWidth: 1.5) } }
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help(mode == .system ? "Follow the system's appearance" : "Keep this space \(name.lowercased()), whatever the system's")
                .accessibilityLabel(name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Appearance")
    }

    // MARK: Field

    private var field: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Image(decorative: Self.fieldImage, scale: 1).resizable().interpolation(.high)
                TextureOverlay(texture: options.texture, amount: options.textureIntensity)
                ForEach(colors.indices, id: \.self) { index in
                    let point = Self.point(of: colors[index])
                    Circle()
                        .fill(colors[index].color)
                        .frame(width: index == selected ? 24 : 18, height: index == selected ? 24 : 18)
                        .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .position(x: point.x * size.width, y: point.y * size.height)
                        .accessibilityRepresentation {
                            Slider(value: Binding(get: { point.x }, set: { setColor(index, Self.color(x: $0, y: point.y)) }),
                                   in: 0...1, step: 1.0 / 24) { Text("Color \(index + 1)") }
                        }
                        .accessibilityValue(Self.describe(colors[index]))
                }
            }
            .contentShape(.rect)
            // A click near a handle picks it up; anywhere else it brings the selected one there.
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                if drag.translation == .zero, let near = colors.indices.min(by: {
                    distance(from: drag.startLocation, to: $0, in: size) < distance(from: drag.startLocation, to: $1, in: size)
                }), distance(from: drag.startLocation, to: near, in: size) < 16 { selected = near }
                setColor(min(selected, colors.count - 1),
                         Self.color(x: min(max(drag.location.x / size.width, 0), 1), y: min(max(drag.location.y / size.height, 0), 1)))
            })
        }
        .frame(height: 150)
        .clipShape(.rect(cornerRadius: Radius.panel, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: Radius.panel, style: .continuous).strokeBorder(.primary.opacity(0.1)) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme colors")
    }

    private func distance(from location: CGPoint, to index: Int, in size: CGSize) -> CGFloat {
        let point = Self.point(of: colors[index])
        return hypot(point.x * size.width - location.x, point.y * size.height - location.y)
    }

    // MARK: Swatches

    private var swatches: some View {
        HStack(spacing: 6) {
            Button { page -= 1 } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.borderless)
                .disabled(page == 0)
                .accessibilityLabel("Previous Colors")
            HStack(spacing: 0) {
                ForEach(Self.hues, id: \.name) { hue in
                    let color = Self.color(x: hue.hue, y: Self.pages[page].depth)
                    Button { setColor(min(selected, colors.count - 1), color) } label: {
                        Circle().fill(color.color)
                            .overlay { Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
                            .frame(width: 24, height: 24)
                            .frame(maxWidth: .infinity)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(Self.pages[page].name) \(hue.name)")
                }
            }
            Button { page += 1 } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.borderless)
                .disabled(page == Self.pages.count - 1)
                .accessibilityLabel("More Colors")
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Colors")
    }

    // MARK: Colors

    /// Sets one of the colors. The first is the light background, and the dark background and accent follow its hue.
    private func setColor(_ index: Int, _ color: RGBA) {
        guard index > 0 else {
            let hsb = color.hsb
            options.light = color
            options.dark = Self.rgb(hue: hsb.hue, saturation: min(1, 0.4 + 0.5 * hsb.saturation), brightness: 0.2)
            options.accent = Self.rgb(hue: hsb.hue, saturation: 0.65, brightness: 0.8)
            return
        }
        options.gradient[index - 1] = color
    }

    private func addColor() {
        let last = Self.point(of: colors[colors.count - 1])
        options.gradient.append(Self.color(x: (last.x + 0.12).truncatingRemainder(dividingBy: 1), y: last.y))
        selected = colors.count - 1
    }

    private func removeColor() {
        options.gradient.removeLast()
        selected = min(selected, colors.count - 1)
    }

    /// The field's color at a point (0…1 each way): hues across, from pale at the top to deep at the bottom.
    static func color(x: Double, y: Double) -> RGBA { rgb(hue: x, saturation: 0.06 + 0.8 * y, brightness: 1 - 0.3 * y) }

    /// Where a color sits on the field; one from elsewhere (an Arc theme) goes to the nearest point in its hue.
    static func point(of color: RGBA) -> CGPoint {
        let hsb = color.hsb
        return CGPoint(x: hsb.hue, y: min(max((hsb.saturation - 0.06) / 0.8, 0), 1))
    }

    private static func describe(_ color: RGBA) -> String {
        let point = point(of: color)
        let hue = hues.min { abs($0.hue - point.x) < abs($1.hue - point.x) }?.name ?? ""
        return "\(pages.min { abs($0.depth - point.y) < abs($1.depth - point.y) }?.name ?? "") \(hue)"
    }

    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> RGBA {
        let h = (hue - hue.rounded(.down)) * 6, f = h - h.rounded(.down), v = brightness
        let p = v * (1 - saturation), q = v * (1 - f * saturation), t = v * (1 - (1 - f) * saturation)
        let (r, g, b) = switch Int(h) % 6 {
        case 0: (v, t, p)
        case 1: (q, v, p)
        case 2: (p, v, t)
        case 3: (p, q, v)
        case 4: (t, p, v)
        default: (v, p, q)
        }
        return RGBA(red: r, green: g, blue: b)
    }

    private static let fieldImage: CGImage = {
        let width = 360, height = 100
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let c = color(x: Double(x) / Double(width - 1), y: Double(y) / Double(height - 1))
                let i = (y * width + x) * 4
                pixels[i] = UInt8(c.red * 255); pixels[i + 1] = UInt8(c.green * 255); pixels[i + 2] = UInt8(c.blue * 255)
            }
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: CGDataProvider(data: Data(pixels) as CFData)!, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)!
    }()
}

/// Arc's squiggle: a slider drawn as a wave that grows with its value.
private struct WavySlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, middle = geometry.size.height / 2
            let wave = Path { path in
                path.move(to: CGPoint(x: 0, y: middle))
                for x in stride(from: 1, through: width, by: 1) {
                    path.addLine(to: CGPoint(x: x, y: middle + sin(x / 3) * (1 + 6 * value)))
                }
            }
            ZStack {
                wave.stroke(.quaternary, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                wave.trim(from: 0, to: value).stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                Circle().fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .frame(width: 14, height: 14)
                    .position(x: 7 + (width - 14) * value, y: middle)
            }
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = min(max((drag.location.x - 7) / (width - 14), 0), 1)
            })
        }
        .frame(height: 26)
        .accessibilityRepresentation { Slider(value: $value, in: 0...1, step: 0.1) { Text("Texture Intensity") } }
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

/// How much of the desktop shows through the window: a ring of dots lit up to the value, turned by dragging round.
private struct TranslucencyDial: View {
    @Binding var value: Double
    private let dots = 24

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) / 2 - 4
            ZStack {
                ForEach(0..<dots, id: \.self) { dot in
                    let fraction = Double(dot) / Double(dots)
                    Circle()
                        .fill(fraction < value ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary))
                        .frame(width: 4, height: 4)
                        .position(point(fraction, around: center, radius: radius))
                }
                Circle().fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 0.5)
                    .frame(width: 10, height: 10)
                    .position(point(value, around: center, radius: radius - 10))
                Image(systemName: "circle.dotted").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .contentShape(.circle)
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                let angle = atan2(drag.location.x - center.x, center.y - drag.location.y)
                let turned = (angle < 0 ? angle + 2 * .pi : angle) / (2 * .pi)
                // Past the top it stops at either end instead of wrapping round.
                value = value > 0.75 && turned < 0.25 ? 1 : value < 0.25 && turned > 0.75 ? 0 : turned
            })
        }
        .frame(width: 64, height: 64)
        .help("Transparency: how much of the desktop shows through the window")
        .accessibilityRepresentation { Slider(value: $value, in: 0...1, step: 0.1) { Text("Transparency") } }
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }

    /// A fraction of the way round from the top, clockwise.
    private func point(_ fraction: Double, around center: CGPoint, radius: CGFloat) -> CGPoint {
        CGPoint(x: center.x + sin(fraction * 2 * .pi) * radius, y: center.y - cos(fraction * 2 * .pi) * radius)
    }
}
