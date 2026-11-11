import SwiftUI

/// The end of Settings on both platforms: privacy policy, support and third-party notices.
struct AboutSection: View {
    static let privacyPolicy = URL(string: "https://github.com/chenkahana/Boaz/blob/master/docs/privacy.md")!
    static let support = URL(string: "https://github.com/chenkahana/Boaz/issues")!

    var body: some View {
        Section {
            Link("Privacy Policy", destination: Self.privacyPolicy)
            Link("Support", destination: Self.support)
        } header: {
            Text("About")
        } footer: {
            Text("""
                Boaz \(version). Ad and tracker blocking uses EasyList by the EasyList authors (easylist.to), \
                licensed under CC BY-SA 3.0. The library is stored with GRDB by Gwendal Roué (MIT License).
                """)
            .foregroundStyle(.secondary)
        }
    }

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "" }
}
