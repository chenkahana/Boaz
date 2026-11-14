#if BOAZ_CHROMIUM
import Foundation

@MainActor
enum ChromiumViewportPresets {
    struct Preset: Codable, Identifiable {
        let id: UUID
        let name: String
        let width: Int
        let height: Int
        let dpr: Double
        let mobile: Bool
        let touch: Bool
        let maxTouchPoints: Int
        let landscape: Bool

        var viewport: ChromiumViewport {
            ChromiumViewport(width: width, height: height, dpr: dpr, mobile: mobile,
                touch: touch, maxTouchPoints: maxTouchPoints, landscape: landscape)
        }
    }
    enum Failure: LocalizedError {
        case invalid, full, unreadable
        var errorDescription: String? {
            switch self {
            case .invalid: "Use a name of 1–80 characters, dimensions of 1–8192, a pixel ratio of 0.5–4, and 1–10 touch points."
            case .full: "You can save up to 20 viewport presets. Remove one to add another."
            case .unreadable: "Saved viewport presets could not be read. They have not been changed."
            }
        }
    }
    private static let key = "boaz.chromium.viewport-presets.v1"

    static func valid(_ viewport: ChromiumViewport) -> Bool {
        (1...8192).contains(viewport.width) && (1...8192).contains(viewport.height) &&
        viewport.dpr.isFinite && (0.5...4).contains(viewport.dpr) && (1...10).contains(viewport.maxTouchPoints)
    }
    static func load() throws -> [Preset] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        guard data.count <= 65536, let items = try? JSONDecoder().decode([Preset].self, from: data),
              items.count <= 20, Set(items.map(\.id)).count == items.count,
              items.allSatisfy({ valid($0.viewport) && !$0.name.isEmpty && $0.name.count <= 80 }) else {
            throw Failure.unreadable
        }
        return items
    }
    static func save(name: String, viewport: ChromiumViewport) throws -> Preset {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80, valid(viewport) else { throw Failure.invalid }
        var items = try load()
        guard items.count < 20 else { throw Failure.full }
        let preset = Preset(id: UUID(), name: name, width: viewport.width, height: viewport.height,
            dpr: viewport.dpr, mobile: viewport.mobile, touch: viewport.touch,
            maxTouchPoints: viewport.maxTouchPoints, landscape: viewport.landscape)
        items.append(preset)
        UserDefaults.standard.set(try JSONEncoder().encode(items), forKey: key)
        return preset
    }
    static func remove(id: UUID) throws {
        let items = try load().filter { $0.id != id }
        UserDefaults.standard.set(try JSONEncoder().encode(items), forKey: key)
    }
}
#endif
