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

@MainActor @Observable
final class ChromiumDownloads {
    private(set) var items: [UInt64: ChromiumDownload] = [:]
    var error: String?
    @ObservationIgnored var perform: ((UInt64, BoazHostDownloadAction) throws -> Void)?
    @ObservationIgnored private var window: NSWindow?

    func update(_ download: ChromiumDownload) {
        if download.removed { items[download.id] = nil }
        else { items[download.id] = download }
    }
    func show(isPrivate: Bool) {
        if let window { window.makeKeyAndOrderFront(nil); return }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = isPrivate ? "Private Downloads" : "Downloads"
        panel.contentView = NSHostingView(rootView: ChromiumDownloadsView(model: self))
        window = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }
    func dispose() {
        window?.close(); window = nil
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

private struct ChromiumDownloadsView: View {
    let model: ChromiumDownloads
    var body: some View {
        VStack(alignment: .leading) {
            if let error = model.error { Text(error).foregroundStyle(.red).padding() }
            if model.items.isEmpty {
                ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle",
                    description: Text("Downloads for this profile appear here."))
            } else {
                List(model.items.values.sorted { $0.id > $1.id }) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.filename).font(.headline).lineLimit(2)
                        if item.dangerous {
                            Label("This download was flagged as unsafe. It cannot be opened or kept here.", systemImage: "exclamationmark.shield")
                                .foregroundStyle(.orange)
                        }
                        Text(status(item)).font(.caption).foregroundStyle(.secondary)
                        if item.state == BOAZ_DOWNLOAD_PROGRESS {
                            if item.total > 0 {
                                ProgressView(value: Double(max(0, item.received)), total: Double(max(item.total, item.received)))
                            } else { ProgressView().controlSize(.small) }
                        }
                        HStack {
                            if !item.dangerous, item.state == BOAZ_DOWNLOAD_PROGRESS, !item.paused {
                                Button("Pause") { model.action(item.id, BOAZ_DOWNLOAD_PAUSE) }
                            }
                            if !item.dangerous, item.canResume {
                                Button("Resume") { model.action(item.id, BOAZ_DOWNLOAD_RESUME) }
                            }
                            if item.state == BOAZ_DOWNLOAD_PROGRESS || item.state == BOAZ_DOWNLOAD_INTERRUPTED {
                                Button("Cancel") { model.action(item.id, BOAZ_DOWNLOAD_CANCEL) }
                            }
                        }.controlSize(.small)
                    }.padding(.vertical, 6)
                }
            }
        }.frame(minWidth: 360, minHeight: 240)
    }
    private func status(_ item: ChromiumDownload) -> String {
        switch item.state {
        case BOAZ_DOWNLOAD_COMPLETE: return "Completed"
        case BOAZ_DOWNLOAD_CANCELLED: return "Cancelled"
        case BOAZ_DOWNLOAD_INTERRUPTED: return "Interrupted (code \(item.interruptReason))"
        default:
            let received = ByteCountFormatter.string(fromByteCount: max(0, item.received), countStyle: .file)
            let total = item.total > 0 ? " of " + ByteCountFormatter.string(fromByteCount: item.total, countStyle: .file) : " — total size unknown"
            return (item.paused ? "Paused · " : "Downloading · ") + received + total
        }
    }
}
#endif
