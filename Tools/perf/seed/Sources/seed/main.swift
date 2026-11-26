import BoazKit
import Foundation
import GRDB

// Fixture loader for Tools/perf/perf.py (PLAN-04, docs/qa.md §4). Opens the exact store path the production app
// resolves in a fresh HOME (`BoazStore.onDisk(applicationSupportDirectory:)`), then writes through BoazKit's public
// API only — never the schema directly — so seeded data looks like anything a real device could have written.
//
// Usage: seed --home <dir> [--visits N] [--today-tabs N] [--space-title TITLE] [--verify]
//   --home        Required. A throwaway HOME; the store lands at <home>/Library/Application Support/Boaz.
//   --visits      History rows to write via `recordVisit`, Zipf-weighted over ~8,000 hosts, spread over 90 days.
//   --today-tabs  Tabs to add to the Personal space's Today (unpinned) container.
//   --space-title Renames the Personal space (public `updateSpace`), so perf.py's UI automation can find a known
//                 sidebar row by name instead of guessing "Personal" in a locale- or future-default-dependent way.
//   --verify      Print `{"spaces":N,"todayTabs":N,"visits":N}` after seeding (or against an existing store if the
//                 other flags are 0), for perf.py's and this tool's own self-test to check without opening SQLite.
struct Options {
    var home: String?
    var visits = 0
    var todayTabs = 0
    var spaceTitle: String?
    var verify = false
}

func parseArguments(_ arguments: [String]) -> Options {
    var options = Options()
    var iterator = arguments.makeIterator()
    while let flag = iterator.next() {
        switch flag {
        case "--home": options.home = iterator.next()
        case "--visits": options.visits = iterator.next().flatMap(Int.init) ?? 0
        case "--today-tabs": options.todayTabs = iterator.next().flatMap(Int.init) ?? 0
        case "--space-title": options.spaceTitle = iterator.next()
        case "--verify": options.verify = true
        default:
            FileHandle.standardError.write("seed: unknown argument '\(flag)'\n".data(using: .utf8)!)
            exit(64)
        }
    }
    return options
}

/// A reproducible Zipf-weighted pick over `hostCount` synthetic hosts: popular hosts repeat the way a real
/// browsing history does, without depending on the network.
struct ZipfHosts {
    let hosts: [String]
    private let cumulativeWeights: [Double]
    private let total: Double

    init(count: Int, exponent: Double = 1.0, seed: UInt64) {
        hosts = (0..<count).map { "site\($0).perf.test" }
        var running = 0.0
        var cumulative: [Double] = []
        cumulative.reserveCapacity(count)
        for rank in 1...count {
            running += 1.0 / pow(Double(rank), exponent)
            cumulative.append(running)
        }
        cumulativeWeights = cumulative
        total = running
        self.generator = SplitMix64(seed: seed)
    }

    private var generator: SplitMix64

    mutating func next() -> String {
        let target = Double(generator.next() >> 11) * (1.0 / Double(1 << 53)) * total
        var low = 0, high = cumulativeWeights.count - 1
        while low < high {
            let mid = (low + high) / 2
            if cumulativeWeights[mid] < target { low = mid + 1 } else { high = mid }
        }
        return hosts[low]
    }
}

/// Deterministic, dependency-free PRNG (splitmix64) so repeated seed runs produce the same fixture.
struct SplitMix64 {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("seed: \(message)\n".data(using: .utf8)!)
    exit(1)
}

@main
struct Seed {
    static func main() async throws {
        let options = parseArguments(Array(CommandLine.arguments.dropFirst()))
        guard let home = options.home else { fail("--home is required") }
        let homeURL = URL(fileURLWithPath: home, isDirectory: true)
        let appSupport = homeURL.appendingPathComponent("Library/Application Support", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let store = try BoazStore.onDisk(applicationSupportDirectory: appSupport)
        try StarterLibrary.seedIfEmpty(store)

        var sidebar = try store.sidebar()
        guard let profile = sidebar.profiles.first(where: \.isDefault) ?? sidebar.profiles.first else {
            fail("no profile after StarterLibrary.seedIfEmpty — BoazKit's starter library shape changed")
        }
        guard let space = sidebar.spaces.first else {
            fail("no space after StarterLibrary.seedIfEmpty — BoazKit's starter library shape changed")
        }
        guard let today = sidebar.items.first(where: {
            $0.spaceID == space.id && $0.kind == .container && $0.containerKind == .unpinned
        }) else {
            fail("no Today container on the Personal space — BoazKit's starter library shape changed")
        }

        if let spaceTitle = options.spaceTitle, spaceTitle != space.title {
            try store.updateSpace(space.id, title: spaceTitle, icon: space.icon, themeJSON: nil)
        }

        if options.visits > 0 {
            var hosts = ZipfHosts(count: min(8000, max(1, options.visits / 6)), seed: 0xB0A2)
            let start = Date().addingTimeInterval(-90 * 86400)
            var rng = SplitMix64(seed: 0x51717)
            // Sorted ascending before writing: `recordVisit` only coalesces into the single most-recently-written
            // visit, so writing in time order makes that check mean what it means in production (repeat loads of
            // the same page close together), instead of racing against whichever random date landed last.
            var dates = (0..<options.visits).map { _ in
                start.addingTimeInterval(Double(rng.next() % UInt64(90 * 86400)))
            }
            dates.sort()
            for (index, date) in dates.enumerated() {
                let host = hosts.next()
                let url = URL(string: "https://\(host)/p/\(index)")!
                store.recordVisit(profileID: profile.id, url: url, title: "Visit \(index) on \(host)", at: date)
            }
            await store.waitForQueuedWrites()
        }

        if options.todayTabs > 0 {
            let now = Date()
            let tabs = (0..<options.todayTabs).map { index -> SidebarItem in
                let url = URL(string: "http://127.0.0.1:0/\(index).html")!
                return SidebarItem(id: "perf-today-\(index)", spaceID: space.id, profileID: profile.id,
                                   parentID: today.id, kind: .tab, title: "Perf tab \(index)", url: url,
                                   position: Double(index), createdAt: now, lastActiveAt: now, modifiedAt: now)
            }
            try store.save(tabs)
        }

        if options.verify {
            sidebar = try store.sidebar()
            let todayTabCount = sidebar.items.filter { $0.kind == .tab && $0.parentID == today.id }.count
            let visitCount = try await store.writer.read { db in try HistoryVisit.fetchCount(db) }
            let report: [String: Int] = ["spaces": sidebar.spaces.count, "todayTabs": todayTabCount, "visits": visitCount]
            let json = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            print(String(data: json, encoding: .utf8)!)
        }
    }
}
