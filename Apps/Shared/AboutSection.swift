import BoazKit
import SwiftUI

/// The end of Settings on both platforms: privacy policy, support, Report a Problem and third-party notices.
struct AboutSection: View {
    static let privacyPolicy = URL(string: "https://github.com/chenkahana/Boaz/blob/master/docs/privacy.md")!
    static let support = URL(string: "https://github.com/chenkahana/Boaz/issues")!
    /// Opens the prefilled bug report in a Boaz tab.
    let reportProblem: (URL) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section {
            HStack(spacing: 14) {
                CurrentAppIcon(size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Boaz").font(.headline)
                    Text("Version \(version) · twisted with care").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            Link("Privacy Policy", destination: Self.privacyPolicy)
            Link("Support", destination: Self.support)
            Button("Report a Problem") { reportProblem(ProblemReport.current(dark: colorScheme == .dark).url) }
                #if os(macOS)
                .buttonStyle(.link)
                #endif
                .accessibilityIdentifier("settings.reportProblem")
            // The DMG is Chromium: WebKit never appears in its UI (must-have #1).
            #if !BOAZ_CHROMIUM
            LabeledContent("WebKit internals") {
                Text(WebKitInternals.summary).accessibilityIdentifier("settings.webkitDiagnostics")
            }
            #endif
        } header: {
            Text("About")
        } footer: {
            Text("""
                Boaz \(version). Ad and tracker blocking uses EasyList by the EasyList authors (easylist.to), \
                licensed under CC BY-SA 3.0. The library is stored with GRDB by Gwendal Roué (MIT License).\(Self.updatesNotice)
                """)
            .foregroundStyle(.secondary)
        }
    }

    #if SPARKLE
    private static let updatesNotice = " Updates come through Sparkle by the Sparkle Project (MIT License)."
    #else
    private static let updatesNotice = ""
    #endif

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
}
