import Foundation
import Testing
@testable import BoazKit

@Suite("ProblemReport")
struct ProblemReportTests {
    private let dmg = ProblemReport(app: .mac, version: "0.5.0", build: "412", channel: "production",
                                    commit: "b7e319a", engine: "Chromium 157.0.8103.51", model: "Mac15,3",
                                    system: "macOS 26.1", dark: true)

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    @Test func opensTheBugReportTemplate() {
        let url = dmg.url
        #expect(url.scheme == "https")
        #expect(url.host() == "github.com")
        #expect(url.path() == "/chenkahana/Boaz/issues/new")
        #expect(query(url)["template"] == "bug_report.yml")
    }

    @Test func fillsOnlyTheTemplateFieldIDs() {
        // bug_report.yml: app, version, device, steps, expected, extra. Steps and expected are the user's.
        #expect(Set(query(dmg.url).keys) == ["template", "app", "version", "device", "extra"])
    }

    @Test func dmgValues() {
        let fields = query(dmg.url)
        #expect(fields["app"] == "Mac")
        #expect(fields["version"] == "0.5.0 (412), DMG, commit b7e319a, Chromium 157.0.8103.51")
        #expect(fields["device"] == "Mac15,3, macOS 26.1")
        #expect(fields["extra"] == "Appearance: Dark\n\nTo add a crash report, see \(ProblemReport.crashReportHelp)")
    }

    @Test func appStoreAndDevelopmentChannels() {
        var report = ProblemReport(app: .iPhone, version: "1.0.2", build: "9", channel: nil, commit: nil,
                                   engine: "WebKit", model: "iPhone18,1", system: "iOS 27.1", dark: false)
        #expect(query(report.url)["app"] == "iPhone")
        #expect(query(report.url)["version"] == "1.0.2 (9), App Store, commit unknown, WebKit")
        #expect(query(report.url)["extra"]?.hasPrefix("Appearance: Light\n\n") == true)
        report.channel = "development"
        report.commit = ""
        #expect(query(report.url)["version"] == "1.0.2 (9), Development, commit unknown, WebKit")
    }

    @Test func encodesReservedCharacters() {
        var report = dmg
        report.model = "Mac+1&x=2#y"
        let raw = report.url.absoluteString
        #expect(!raw.contains("+"))
        #expect(!raw.contains("#"))
        #expect(!raw.contains(" "))
        #expect(raw.contains("device=Mac%2B1%26x%3D2%23y%2C%20macOS%2026.1"))
        #expect(raw.contains("extra=Appearance%3A%20Dark%0A%0ATo%20add"))
        #expect(query(report.url)["device"] == "Mac+1&x=2#y, macOS 26.1")
    }
}
