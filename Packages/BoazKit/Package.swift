// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BoazKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BoazKit", targets: ["BoazKit"])],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .target(name: "BoazKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
    ]
)
