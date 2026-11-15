#if BOAZ_CHROMIUM
import AppKit
import Observation
import SwiftUI

struct ChromiumDownload: Identifiable {
    let id: UInt64
    let filename: String
    let received: Int64
    let total: Int64
    let state: BoazHostDownloadState
    let interruptReason: Int32
    let dangerType: Int32
    let paused: Bool
    let canResume: Bool
    let dangerous: Bool
    let removed: Bool
    init(_ value: BoazHostDownload) {
        id = value.id
        filename = value.filename.map { String(cString: $0) } ?? "Download"
        received = value.received; total = value.total; state = value.state
        interruptReason = value.interrupt_reason; dangerType = value.danger_type
        paused = value.paused != 0; canResume = value.can_resume != 0
        dangerous = value.dangerous != 0; removed = value.removed != 0
    }
}

@MainActor
final class ChromiumDownloadSnapshotCollector {
    var items: [ChromiumDownload] = []
}

/// One profile's live Chromium downloads: progress updates arrive via `download_changed` (`ChromiumRuntime`)
/// and are shown in the Library panel's Downloads pane (`ActiveChromiumDownloadsSection`) instead of a
/// separate window.
@MainActor @Observable
final class ChromiumDownloads {
    private(set) var items: [UInt64: ChromiumDownload] = [:]
    var error: String?
    @ObservationIgnored var perform: ((UInt64, BoazHostDownloadAction) throws -> Void)?

    func update(_ download: ChromiumDownload) {
        if download.removed { items[download.id] = nil }
        else { items[download.id] = download }
    }
    func dispose() {
        perform = nil; items.removeAll(); error = nil
    }
    func action(_ id: UInt64, _ action: BoazHostDownloadAction) {
        error = nil
        do {
            guard let perform else { throw EnginePageError.unavailable }
            try perform(id, action)
        } catch { self.error = "The download action could not be completed. Its current status is shown below." }
    }
}
#endif
