#if BOAZ_CHROMIUM
import Foundation
import Observation
import SwiftUI

struct ChromiumAutomationStatus {
    enum State { case disabled, starting, ready, failed }
    let state: State
    let requestedAtStartup: Bool
    let error: String?
}

@MainActor @Observable
final class ChromiumAutomation {
    static let shared = ChromiumAutomation()
    static let enabledKey = "boaz.chromium.automation.enabled"
    var configured: Bool {
        didSet { UserDefaults.standard.set(configured, forKey: Self.enabledKey) }
    }
    private(set) var status: ChromiumAutomationStatus?
    private(set) var error: String?
    private var polling: Task<Void, Never>?
    private init() { configured = UserDefaults.standard.bool(forKey: Self.enabledKey) }

    func start() {
        stop()
        polling = Task { @MainActor [weak self] in
            // Leave the startup callback stack before querying the host.
            await Task.yield()
            for _ in 0..<60 {
                guard !Task.isCancelled, let self else { return }
                do {
                    let value = try ChromiumRuntime.automationStatus()
                    self.status = value
                    self.error = value.error
                    if value.state != .starting { return }
                } catch {
                    self.error = error.localizedDescription
                    return
                }
                do { try await Task.sleep(for: .milliseconds(250)) }
                catch { return }
            }
            self?.error = "Automation startup status is unavailable."
        }
    }
    func stop() {
        polling?.cancel()
        polling = nil
        status = nil
        error = nil
    }
    var runningDescription: String {
        switch status?.state {
        case .ready: "Running"
        case .starting: "Starting…"
        case .failed: "Could not start"
        case .disabled: "Off"
        case nil: "Unavailable"
        }
    }
}

struct ChromiumAutomationSettings: View {
    var body: some View {
        @Bindable var automation = ChromiumAutomation.shared
        Section("Local Automation") {
            Toggle("Enable local automation after restarting Boaz", isOn: $automation.configured)
            LabeledContent("Current session", value: automation.runningDescription)
            Text("Changes require quitting and reopening Boaz. Automation can access all open profiles, including private windows. Local native clients connect using a private connection file.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = automation.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
#endif
