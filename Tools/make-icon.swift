// Boaz Browser app icons: a soft 3D tube tied in a pretzel knot (a trefoil with two upper loops and one lower
// loop), in a family of finishes from the classic glossy blue on cream to neon, wood, salted dough and holo foil.
//
// The knot is real geometry: Tools/icon/Knot.swift sweeps a circular cross-section along the closed curve with
// rotation-minimizing frames and bakes ambient occlusion where strands pass close; Render.swift renders it with
// SceneKit (physically based materials, a procedural studio environment, soft shadows); Compose.swift puts it on
// each variant's ground (Grounds.swift) with Core Graphics. Variants.swift is the family; Artwork.swift draws the
// README parade, social card, DMG background and review sheet.
//
// Regenerate everything (from anywhere; paths resolve from this file's location):
//   swift Tools/make-icon.swift [repo-root]
//
// Writes:
//   Apps/Shared/Resources/Assets.xcassets/AppIcon.appiconset/          AppIcon.png, AppIcon-Dark.png,
//       AppIcon-Tinted.png (iOS 1024) and mac-16 … mac-1024.png (macOS squircle on the Apple grid)
//   Apps/Shared/Resources/Assets.xcassets/AppIcon-<Name>.appiconset/   one 1024 PNG per iOS alternate
//   Apps/iOS/Delight/IconPreviews/AppIcon[-<Name>]-Preview.png         180 px previews for the pickers
//   Apps/macOS/Resources/AppIcons/AppIcon-<Name>.icns                  Mac alternates (256, 512, 1024 px PNGs)
//   docs/assets/icon.png, icon-parade.png, social-preview.png           README icon, parade, GitHub social card
//   Tools/chromium/dmg-background[@2x].png                              the DMG window (package-candidate.py)
//   build/icon-contact-sheet.png                                        review sheet: every icon, large and small
//
// Names, titles and captions shown in the apps live in Apps/Shared/AppIcons/AppIconCatalog.swift; keep its order
// and ids in step with `variants` here, and the iOS alternate names in project.yml.
import Foundation

let root = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0) }
    ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sources = root.appendingPathComponent("Tools/icon")
let binary = root.appendingPathComponent("build/make-icon")
let files = try! FileManager.default.contentsOfDirectory(atPath: sources.path).filter { $0.hasSuffix(".swift") }.sorted()
try! FileManager.default.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)

func run(_ tool: String, _ arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    try! process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { fatalError("\(tool) failed (\(process.terminationStatus))") }
}

run("/usr/bin/xcrun", ["swiftc", "-O", "-o", binary.path] + files.map { sources.appendingPathComponent($0).path })
run(binary.path, [root.path])
