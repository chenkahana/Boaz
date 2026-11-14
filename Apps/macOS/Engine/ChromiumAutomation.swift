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
            let clock = ContinuousClock()
            var startupDeadline: ContinuousClock.Instant?
            while !Task.isCancelled {
                guard let self else { return }
                let delay: Duration
                do {
                    let value = try ChromiumRuntime.automationStatus()
                    self.status = value
                    self.error = value.error
                    switch value.state {
                    case .disabled, .failed:
                        return
                    case .ready:
                        startupDeadline = nil
                        delay = .seconds(2)
                    case .starting:
                        if startupDeadline == nil {
                            startupDeadline = clock.now.advanced(by: .seconds(15))
                        }
                        if let startupDeadline, clock.now >= startupDeadline {
                            self.status = nil
                            self.error = "Automation startup status is unavailable."
                            return
                        }
                        delay = .milliseconds(250)
                    }
                } catch {
                    self.status = nil
                    self.error = error.localizedDescription
                    return
                }
                do { try await Task.sleep(for: delay) }
                catch { return }
            }
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
