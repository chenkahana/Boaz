import CoreTelephony
import Network
import SwiftUI

/// What the status indicators show: the battery, Low Power Mode and the network the phone is on, kept current from
/// the system's own notifications. One instance for the app, so the bar and the pill never disagree.
@Observable
final class DeviceStatus {
    static let shared = DeviceStatus()

    enum Network: Equatable {
        case offline
        case wifi
        case cellular
        case other
    }

    /// 0...1, or nil while iOS doesn't report it (the simulator).
    private(set) var batteryLevel: Float?
    private(set) var batteryState = UIDevice.BatteryState.unknown
    private(set) var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    private(set) var network = Network.other
    /// The cellular data technology ("5G", "LTE", …), or nil without cellular service.
    private(set) var radio: String?

    private let telephony = CTTelephonyNetworkInfo()

    private init() {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        readBattery()
        readRadio()
        let center = NotificationCenter.default
        Task { for await _ in center.notifications(named: UIDevice.batteryLevelDidChangeNotification) { readBattery() } }
        Task { for await _ in center.notifications(named: UIDevice.batteryStateDidChangeNotification) { readBattery() } }
        Task {
            for await _ in center.notifications(named: .NSProcessInfoPowerStateDidChange) {
                lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
        Task { for await _ in center.notifications(named: .CTServiceRadioAccessTechnologyDidChange) { readRadio() } }
        Task {
            for await path in NWPathMonitor() {
                network = if path.status != .satisfied { .offline }
                    else if path.usesInterfaceType(.wifi) { .wifi }
                    else if path.usesInterfaceType(.cellular) { .cellular }
                    else { .other }
                readRadio()
            }
        }
    }

    private func readBattery() {
        let device = UIDevice.current
        batteryLevel = device.batteryLevel >= 0 ? device.batteryLevel : nil
        batteryState = device.batteryState
    }

    private func readRadio() {
        let technologies = telephony.serviceCurrentRadioAccessTechnology ?? [:]
        let current = telephony.dataServiceIdentifier.flatMap { technologies[$0] } ?? technologies.values.first
        radio = current.map(Self.name)
    }

    nonisolated private static func name(_ technology: String) -> String {
        switch technology {
        case CTRadioAccessTechnologyNR, CTRadioAccessTechnologyNRNSA: "5G"
        case CTRadioAccessTechnologyLTE: "LTE"
        case CTRadioAccessTechnologyEdge: "E"
        case CTRadioAccessTechnologyGPRS: "G"
        default: "3G"
        }
    }
}

/// The unfolded inner screen held upright: the system squeezes its status into a ring in the top corner there, so
/// Boaz draws a bar across the top as other iPhones have, in the page's top edge color: time and network on the
/// left, the battery on the right.
struct PortraitStatusBar: View {
    let site: SiteColor?

    var body: some View {
        HStack(spacing: 6) {
            StatusClock().padding(.trailing, 2)
            NetworkIndicator()
            Spacer(minLength: 8)
            BatteryIndicator()
        }
        .font(.system(size: 15, weight: .semibold))
        .padding(.horizontal, 26)
        .frame(height: 34)
        .padding(.top, 14)
        .frame(maxWidth: .infinity)
        .background(site?.color ?? Color(uiColor: .systemBackground))
        .chromeScheme(site)
    }
}

struct StatusClock: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute()).monospacedDigit()
        }
    }
}

/// Cellular service and the network in use: the bars while there's a carrier, then Wi-Fi, or the cellular
/// technology while on cellular data. iOS exposes no signal strength, so the bars and the Wi-Fi fan stay full.
struct NetworkIndicator: View {
    private let status = DeviceStatus.shared

    var body: some View {
        HStack(spacing: 5) {
            if status.radio != nil { Image(systemName: "cellularbars") }
            switch status.network {
            case .wifi: Image(systemName: "wifi")
            case .cellular: if let radio = status.radio { Text(radio).font(.system(size: 13, weight: .semibold)) }
            case .offline: if status.radio == nil { Image(systemName: "wifi.slash").foregroundStyle(.secondary) }
            case .other: EmptyView()
            }
        }
        .imageScale(.small)
        .animation(.smooth(duration: 0.2), value: status.network)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: Text {
        switch status.network {
        case .wifi: Text("Wi-Fi")
        case .cellular: Text("Cellular \(status.radio ?? "")")
        case .offline: Text("No Connection")
        case .other: Text("Connected")
        }
    }
}

/// The battery as iOS draws it: a body filled to the charge, green while charging, yellow in Low Power Mode, red
/// when low, with a bolt while plugged in and the percentage beside it.
struct BatteryIndicator: View {
    private let status = DeviceStatus.shared

    var body: some View {
        let level = status.batteryLevel ?? 1
        let plugged = status.batteryState == .charging || status.batteryState == .full
        HStack(spacing: 4) {
            if let percent = status.batteryLevel {
                Text(Double(percent), format: .percent.precision(.fractionLength(0))).monospacedDigit()
            }
            HStack(spacing: 1.5) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.primary.opacity(0.35))
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(fill(level: level, plugged: plugged))
                            .frame(width: max(3, proxy.size.width * CGFloat(level)))
                    }
                    if plugged {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.25), radius: 0.5)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: 25, height: 12)
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 1.5,
                                       topTrailingRadius: 1.5)
                    .fill(.primary.opacity(0.35))
                    .frame(width: 1.5, height: 4)
            }
        }
        .animation(.smooth(duration: 0.3), value: level)
        .animation(.smooth(duration: 0.2), value: plugged)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText(plugged: plugged))
    }

    private func fill(level: Float, plugged: Bool) -> AnyShapeStyle {
        if plugged { return AnyShapeStyle(Color.green) }
        if status.lowPower { return AnyShapeStyle(Color.yellow) }
        if level <= 0.2 { return AnyShapeStyle(Color.red) }
        return AnyShapeStyle(.primary)
    }

    private func accessibilityText(plugged: Bool) -> Text {
        guard let level = status.batteryLevel else { return Text("Battery") }
        let percent = Text(Double(level), format: .percent.precision(.fractionLength(0)))
        return plugged ? Text("Battery \(percent), charging") : Text("Battery \(percent)")
    }
}
