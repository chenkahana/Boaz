// swift-tools-version: 6.0
import PackageDescription

// Fixture loader for Tools/perf/perf.py. Depends on BoazKit's public API only (no app target), so it builds and
// runs standalone: `swift run --package-path Tools/perf/seed seed --home <dir> ...`. Never touches the production
// App Group container: callers always pass --home pointed at a throwaway HOME (see perf.py's isolation).
let package = Package(
    name: "boaz-perf-seed",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../../Packages/BoazKit"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(name: "seed", dependencies: [
            "BoazKit",
            .product(name: "GRDB", package: "GRDB.swift"),
        ]),
    ]
)
