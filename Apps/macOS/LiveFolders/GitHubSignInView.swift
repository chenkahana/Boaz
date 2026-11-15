import AppKit
import BoazKit
import SwiftUI

/// A sign-in sheet, optionally for a Pull Requests folder to make in `spaceID` once signed in.
struct GitHubSignInRequest: Identifiable {
    let id = UUID()
    var spaceID: String?
}

/// GitHub's device flow: the user code in big type, Open GitHub (which copies it and opens the device page in a Boaz
/// tab), then a spinner until GitHub confirms. A personal access token works as well.
///
/// The sheet would hold the window the code is typed into, so Open GitHub closes it and the sign-in finishes in the
/// background: `GitHubAuth.onNextSignIn` makes the folder and a toast says so.
struct GitHubSignInView: View {
    var request: GitHubSignInRequest?
    /// Opens a page in a Boaz tab.
    var open: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var usesToken = false
    @State private var token = ""
    @State private var tokenError: String?
    @State private var checking = false

    var body: some View {
        let auth = GitHubAuth.shared
        VStack(spacing: 16) {
            GitHubMark(size: 36)
            Text("Sign In to GitHub").font(.title2.weight(.semibold))
            Text("Live folders list your pull requests from GitHub, refreshed every minute.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Group {
                if auth.isSignedIn {
                    signedIn(auth.viewer)
                } else {
                    switch auth.flow {
                    case .idle, .requesting, .signedIn:
                        if GitHubAuth.hasClientID {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Getting a code…") }
                        } else {
                            Text("This build has no GitHub app set up yet. Use a personal access token.")
                                .font(.callout).multilineTextAlignment(.center)
                        }
                    case .waiting(let code, let url):
                        waiting(code: code, url: url)
                    case .failed(let message):
                        VStack(spacing: 8) {
                            Text(message).foregroundStyle(.red).multilineTextAlignment(.center)
                            Button("Try Again") { auth.beginDeviceFlow() }
                        }
                    }
                }
            }
            .frame(minHeight: 120)
            if !auth.isSignedIn { tokenSection(auth) }
            HStack {
                Spacer()
                Button(auth.isSignedIn ? "Done" : "Cancel") {
                    if !auth.isSignedIn {
                        auth.cancelDeviceFlow()
                        auth.onNextSignIn = nil
                    }
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 440)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.githubSignIn")
        // Signed in while the sheet is up: show who, then get out of the way.
        .task(id: auth.isSignedIn) {
            guard auth.isSignedIn, request != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { dismiss() }
        }
        .onAppear {
            guard !auth.isSignedIn else { return }
            if case .waiting = auth.flow {} else if GitHubAuth.hasClientID { auth.beginDeviceFlow() }
        }
    }

    private func waiting(code: String, url: URL) -> some View {
        VStack(spacing: 12) {
            Text("Enter this code on GitHub:").font(.callout)
            Text(code)
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityIdentifier("control.githubSignIn.code")
            HStack {
                Button("Copy Code") { copy(code) }
                Button("Open GitHub") {
                    copy(code)
                    open(url)
                    MacModel.shared.showToast("Code copied. Paste it on GitHub to finish signing in.")
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Waiting for GitHub…").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func signedIn(_ viewer: GitHubViewer?) -> some View {
        VStack(spacing: 8) {
            GitHubAvatar(viewer: viewer, size: 48)
            Text(viewer.map { "Signed in as @\($0.login)" } ?? "Signed in").font(.headline)
        }
    }

    private func tokenSection(_ auth: GitHubAuth) -> some View {
        DisclosureGroup("Use a personal access token…", isExpanded: $usesToken) {
            VStack(alignment: .leading, spacing: 8) {
                SecureField("Token", text: $token).textFieldStyle(.roundedBorder).onSubmit { signIn(auth) }
                Text("Needs the repo and read:org scopes. It stays in this Mac's Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
                if let tokenError { Text(tokenError).font(.caption).foregroundStyle(.red) }
                HStack {
                    Spacer()
                    if checking { ProgressView().controlSize(.small) }
                    Button("Sign In") { signIn(auth) }.disabled(token.isEmpty || checking)
                }
            }
            .padding(.top, 6)
        }
    }

    private func signIn(_ auth: GitHubAuth) {
        checking = true
        tokenError = nil
        Task {
            do { try await auth.signIn(personalAccessToken: token) } catch { tokenError = error.localizedDescription }
            checking = false
        }
    }

    private func copy(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }
}

struct GitHubAvatar: View {
    let viewer: GitHubViewer?
    var size: CGFloat = 28

    var body: some View {
        AsyncImage(url: UITestMode.isActive ? nil : viewer?.avatarUrl) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            GitHubMark(size: size * 0.6).frame(width: size, height: size).background(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// Settings › Accounts: the GitHub account live folders use.
struct AccountsSettings: View {
    @State private var signingIn = false

    var body: some View {
        let auth = GitHubAuth.shared
        Form {
            Section {
                HStack(spacing: 10) {
                    GitHubAvatar(viewer: auth.isSignedIn ? auth.viewer : nil)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("GitHub")
                        Text(auth.isSignedIn ? auth.viewer.map { "@\($0.login)" } ?? "Signed in" : "Not signed in")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if auth.isSignedIn {
                        Button("Sign Out") { auth.signOut() }
                    } else {
                        Button("Sign In…") { signingIn = true }
                    }
                }
            } footer: {
                Text("Live folders use this account to list your pull requests. Its token stays in this Mac's Keychain.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 200)
        .accessibilityIdentifier("screen.settings.accounts")
        .task { await auth.loadViewer() }
        .sheet(isPresented: $signingIn) {
            GitHubSignInView { url in
                if let browser = MacModel.shared.lastActiveBrowser { browser.openTab(url) } else { MacModel.shared.newTab(url, in: nil) }
            }
        }
    }
}
