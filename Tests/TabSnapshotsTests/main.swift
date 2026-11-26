// `make tab-snapshots-test`: a tab's saved page shows once (Apps/macOS/Model/TabSnapshots.swift), compiled without
// the app.
import Foundation

var failures = 0
@MainActor func check(_ condition: Bool, _ name: String, line: Int = #line) {
    if !condition { failures += 1; print("FAIL line \(line): \(name)") }
}
let manager = FileManager.default
let directory = manager.temporaryDirectory.appendingPathComponent("tab-snapshots-\(UUID().uuidString)")
try! manager.createDirectory(at: directory, withIntermediateDirectories: true)
defer { try? manager.removeItem(at: directory) }
let archive = directory.appendingPathComponent("T1.mhtml"), page = directory.appendingPathComponent("T1.archive-url")
let url = URL(string: "https://example.com/a")!
@MainActor func save(_ shows: String, body: String = "saved") {
    try! Data(body.utf8).write(to: archive)
    try! Data(shows.utf8).write(to: page)
}

// Taken once: it moves to a name of its own, and nothing is left to find again.
save(url.absoluteString)
let claimed = TabSnapshots.claim(archive: archive, archivePage: page, for: url)
check(claimed != nil && manager.fileExists(atPath: claimed!.path), "claimed page exists")
check(claimed?.pathExtension == "mhtml" && claimed?.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path, "claimed beside, as mhtml")
check(!manager.fileExists(atPath: archive.path) && !manager.fileExists(atPath: page.path), "nothing left to find")
check(TabSnapshots.claim(archive: archive, archivePage: page, for: url) == nil, "a second claim finds nothing")

// A page saved again after the claim is its own file: dropping the claimed one leaves it.
save(url.absoluteString, body: "newer")
try? manager.removeItem(at: claimed!)
check(String(data: try! Data(contentsOf: archive), encoding: .utf8) == "newer", "a newer save survives the drop")
let second = TabSnapshots.claim(archive: archive, archivePage: page, for: url)
check(second != nil && second != claimed, "each claim has its own name")
if let second { try? manager.removeItem(at: second) }

// One that shows another page is out of date: it goes, unclaimed.
save("https://example.com/other")
check(TabSnapshots.claim(archive: archive, archivePage: page, for: url) == nil, "another page isn't claimed")
check(!manager.fileExists(atPath: archive.path) && !manager.fileExists(atPath: page.path), "and it goes")

// A page with no address beside it goes too.
try! Data("saved".utf8).write(to: archive)
check(TabSnapshots.claim(archive: archive, archivePage: page, for: url) == nil, "no address, no claim")
check(!manager.fileExists(atPath: archive.path), "and it goes")

print(failures == 0 ? "TabSnapshots: all checks passed" : "TabSnapshots: \(failures) failed")
exit(failures == 0 ? 0 : 1)
