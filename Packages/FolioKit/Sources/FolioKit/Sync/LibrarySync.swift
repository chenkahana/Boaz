import Foundation
import Observation
import os

/// The one sync object the apps use. iCloud (`CloudKitSync`) is the transport whenever this build is entitled and
/// an iCloud account is signed in; a user-picked folder (`FolioSync`) is the fallback only while it isn't.
/// Both drain the same pending queue, so at most one runs at a time.
@MainActor @Observable
public final class LibrarySync {
    public enum Status: Equatable, Sendable {
        case starting
        case syncing
        case upToDate(Date)
        case signedOut
        case unavailable(String)
        case error(String)
    }

    @ObservationIgnored private let store: FolioStore
    private let cloud: CloudKitSync
    /// The folder transport, only while iCloud can't sync here and a folder was picked.
    private var folder: FolioSync?
    @ObservationIgnored private var started = false
    /// Bumped whenever the folder is retired, so a `setFolder` that was waiting gives up.
    @ObservationIgnored private var folderGeneration = 0

    private static let log = Logger(subsystem: "com.chenkahana.folio", category: "sync")

    public init(store: FolioStore) {
        self.store = store
        cloud = CloudKitSync(store: store)
        cloud.willStartEngine = { [weak self] in await self?.retireFolder() }
    }

    public var status: Status {
        if let folder, folder.folderURL != nil {
            switch folder.status {
            case .idle, .noFolder, .syncing: return .syncing
            case .upToDate(let date): return .upToDate(date)
            case .error(let message): return .error(message)
            }
        }
        switch cloud.status {
        case .idle: return .starting
        case .syncing: return .syncing
        case .upToDate(let date): return .upToDate(date)
        case .noAccount: return .signedOut
        case .unavailable(let reason): return .unavailable(reason)
        case .error(let message): return .error(message)
        }
    }

    /// iCloud can't sync on this device, so a folder may be picked instead.
    public var offersFolder: Bool {
        switch cloud.status {
        case .noAccount, .unavailable: true
        default: false
        }
    }

    /// The fallback folder in use, if any.
    public var folderURL: URL? { folder?.folderURL }

    /// Whether this device's library is connected to other devices (it may still be waiting for their data).
    public var isConnected: Bool { cloud.isRunning || folderURL != nil }

    /// Starts iCloud sync, or the fallback folder when iCloud can't run and one was picked before. On a device with
    /// iCloud it waits (up to a few seconds) for the first fetch, so an empty device receives the library before
    /// anything is seeded. Later calls return at once.
    public func start() async {
        guard !started else { return }
        started = true
        await cloud.start()
        if cloud.isRunning {
            await waitAtMost(.seconds(10)) { await self.cloud.syncNow() }
        } else if store.syncSetting(FolioSync.bookmarkKey) != nil {
            await folderTransport().start()
        }
    }

    /// Re-checks iCloud (switching to it if it became available), then fetches and sends right away.
    /// `userInitiated` (the Sync Now button) also turns sync back on after the user deleted Folio's iCloud data.
    public func syncNow(userInitiated: Bool = false) async {
        if userInitiated { await cloud.resumeAfterPurge() }
        await cloud.start()
        if cloud.isRunning { await cloud.syncNow() } else { await folder?.syncNow() }
    }

    /// Syncs through `url` while iCloud is unavailable.
    public func setFolder(_ url: URL) async throws {
        guard offersFolder else { return }
        let generation = folderGeneration
        let folder = folderTransport()
        await folder.start()
        // iCloud may have come up meanwhile and retired this folder transport.
        guard generation == folderGeneration, self.folder === folder, offersFolder else { return }
        try await folder.setFolder(url)
    }

    // MARK: Private

    private func folderTransport() -> FolioSync {
        if let folder { return folder }
        let folder = FolioSync(store: store)
        self.folder = folder
        return folder
    }

    /// Before iCloud takes over: one last folder pass (other devices' edits in, this device's unsent edits out),
    /// then the folder is stopped and forgotten. `CloudKitSync` then uploads every local record.
    private func retireFolder() async {
        guard folder != nil || store.syncSetting(FolioSync.bookmarkKey) != nil else { return }
        Self.log.notice("Moving from folder sync to iCloud")
        folderGeneration += 1
        let folder = folderTransport()
        await folder.start()
        folder.stop()
        self.folder = nil
        do { try store.resetSyncState(reuploadAll: true) } catch {
            Self.log.error("Couldn't reset sync state: \(error, privacy: .public)")
        }
    }

    /// Waits for `work`, but no longer than `limit`; past that it carries on in the background.
    private func waitAtMost(_ limit: Duration, for work: @escaping @MainActor () async -> Void) async {
        let (done, signal) = AsyncStream<Never>.makeStream()
        Task { await work(); signal.finish() }
        Task { try? await Task.sleep(for: limit); signal.finish() }
        for await _ in done {}
    }
}

extension LibrarySync.Status {
    /// One line for Settings and setup.
    public var summary: String {
        switch self {
        case .starting: "Checking iCloud…"
        case .syncing: "Syncing…"
        case .upToDate(let date): "Up to date · \(date.formatted(date: .omitted, time: .shortened))"
        case .signedOut:
            #if os(macOS)
            "Sign in to iCloud in System Settings to sync."
            #else
            "Sign in to iCloud in Settings to sync."
            #endif
        case .unavailable(let reason): reason
        case .error(let message): "Couldn't sync: \(message)"
        }
    }

    public var systemImage: String {
        switch self {
        case .starting, .syncing: "arrow.triangle.2.circlepath.icloud"
        case .upToDate: "checkmark.icloud.fill"
        case .signedOut, .unavailable: "icloud.slash"
        case .error: "exclamationmark.icloud"
        }
    }

    public var isUpToDate: Bool {
        if case .upToDate = self { true } else { false }
    }
}
