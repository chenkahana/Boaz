#!/usr/bin/env swift
// Tools/perf/window-wait.swift — "window drawn" timing for perf.py's launch row (docs/qa.md §4).
//
// Polls the window server for an on-screen, layer-0 window owned by `pid` every 10 ms and prints the elapsed
// seconds since this process started once one appears. Needs no Screen Recording or Accessibility permission:
// `CGWindowListCopyWindowInfo` only reports window existence/geometry, not window contents.
//
// Usage: swift Tools/perf/window-wait.swift <pid> [timeoutSeconds]
// Exit 0 and a float on stdout when a window appears; exit 1 on timeout; exit 2 on bad arguments.

import CoreGraphics
import Foundation

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    exit(code)
}

let arguments = CommandLine.arguments
guard arguments.count >= 2, let targetPID = Int32(arguments[1]) else {
    fail("usage: window-wait.swift <pid> [timeoutSeconds]", code: 2)
}
let timeout: Double = arguments.count >= 3 ? (Double(arguments[2]) ?? 30) : 30

func hasOnScreenWindow(forPID pid: Int32) -> Bool {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: AnyObject]] else {
        return false
    }
    for window in list {
        guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32, ownerPID == pid else { continue }
        guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
        return true
    }
    return false
}

let start = Date()
while Date().timeIntervalSince(start) < timeout {
    if hasOnScreenWindow(forPID: targetPID) {
        print(Date().timeIntervalSince(start))
        exit(0)
    }
    usleep(10_000)
}
fail("window-wait: timed out after \(timeout)s waiting for pid \(targetPID)", code: 1)
