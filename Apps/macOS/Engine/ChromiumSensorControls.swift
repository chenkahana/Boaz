#if BOAZ_CHROMIUM
import SwiftUI

@MainActor
struct ChromiumSensorControls: View {
    let adapter: ChromiumEnginePageAdapter
    @State private var locationEnabled = false
    @State private var latitude = 0.0
    @State private var longitude = 0.0
    @State private var accuracy = 100.0
    @State private var timezone = ""
    @State private var locale = ""

    var body: some View {
        DisclosureGroup("Location, Timezone and Locale") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Override Location", isOn: $locationEnabled)
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    GridRow {
                        Text("Latitude")
                        coordinate("Latitude (−90 to 90)", value: $latitude)
                        Text("Longitude")
                        coordinate("Longitude (−180 to 180)", value: $longitude)
                    }.disabled(!locationEnabled)
                    GridRow {
                        Text("Accuracy (m)")
                        coordinate("Location accuracy in meters", value: $accuracy)
                    }.disabled(!locationEnabled)
                    GridRow {
                        Text("Timezone")
                        TextField("System, or IANA name", text: $timezone)
                            .accessibilityLabel("Timezone override, empty uses system")
                            .gridCellColumns(3)
                    }
                    GridRow {
                        Text("Locale")
                        TextField("System, or locale identifier", text: $locale)
                            .accessibilityLabel("Locale override, empty uses system")
                            .gridCellColumns(3)
                    }
                }
                HStack {
                    Button("Apply Sensors") {
                        let value = ChromiumSensors(location: locationEnabled ?
                            .init(latitude: latitude, longitude: longitude, accuracy: accuracy) : nil,
                            timezone: timezone, locale: locale)
                        apply(value)
                    }
                    Button("Reset Sensors") { apply(nil) }
                }
            }
            .controlSize(.small)
            .disabled(adapter.emulationPending || adapter.state.isLoading || adapter.state.lifecycle != .active)
            Text(appliedDescription).font(.caption).foregroundStyle(.secondary)
            Text("Timezone and locale can affect pages sharing this renderer. Sites still need location permission. Empty fields use system defaults.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { refresh() }
        .onChange(of: adapter.state.navigationID) { refresh() }
    }

    private var appliedDescription: String {
        guard let value = adapter.appliedSensors else { return "No sensor overrides applied." }
        let location = value.location == nil ? "Location: system" : "Location override active"
        return location + " · Timezone: " + (value.timezone.isEmpty ? "system" : value.timezone) +
            " · Locale: " + (value.locale.isEmpty ? "system" : value.locale)
    }
    private func coordinate(_ label: String, value: Binding<Double>) -> some View {
        TextField(label, value: value, format: .number).accessibilityLabel(label)
    }
    private func refresh() {
        let value = adapter.appliedSensors ?? ChromiumSensors()
        locationEnabled = value.location != nil
        latitude = value.location?.latitude ?? 0
        longitude = value.location?.longitude ?? 0
        accuracy = value.location?.accuracy ?? 100
        timezone = value.timezone
        locale = value.locale
    }
    private func apply(_ value: ChromiumSensors?) {
        Task {
            do { try await adapter.applySensors(value); refresh() }
            catch { }
        }
    }
}
#endif
