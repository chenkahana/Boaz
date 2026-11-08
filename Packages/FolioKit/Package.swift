// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FolioKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "FolioKit", targets: ["FolioKit"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "FolioKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
                // Not shipped: reading another browser's saved passwords stays out of the apps.
                exclude: ["Import/ArcPasswordImporter.swift"]),
    ]
)
