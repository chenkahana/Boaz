import BoazKit
import Foundation

extension Notification.Name {
    /// Posted when the GitHub account signs in or out, so live folders refresh at once.
    static let githubAccountDidChange = Notification.Name("BoazGitHubAccountDidChange")
}

/// The GitHub account live folders read with: OAuth device flow sign-in (or a personal access token), its token in this
/// Mac's Keychain, and the signed-in user.
///
/// Under `UITestMode` the Keychain is never touched: `BOAZ_GITHUB_TOKEN` signs in with that token for the run, and
/// with a fixture the device flow shows a code and succeeds a moment later.
@Observable
final class GitHubAuth {
    static let shared = GitHubAuth()

    /// The Boaz OAuth App's client ID (github.com › Settings › Developer settings › OAuth Apps, device flow enabled).
    /// Not a secret: the device flow has none.
    static let clientID = "Ov23liMIq1lh30dIy0ML"
    /// Private repositories' pull requests, and the teams a user is on (Team Review Requests).
    static let scopes = "repo read:org"
    static var hasClientID: Bool { !clientID.hasPrefix("BOAZ_") || UITestMode.githubFixtureURL != nil }

    private static let secret = KeychainSecret(service: "com.chenkahana.boaz.github", account: "token")
    private static let viewerKey = "githubViewer"

    enum DeviceFlow: Equatable {
        case idle
        case requesting
        /// Waiting for the user to enter `code` at `verificationURL`.
        case waiting(code: String, verificationURL: URL)
        case signedIn
        case failed(String)
    }

    private(set) var token: String?
    private(set) var viewer: GitHubViewer?
    private(set) var flow: DeviceFlow = .idle
    @ObservationIgnored private var flowTask: Task<Void, Never>?
    /// What the sign-in under way was for (a Pull Requests folder), run once it succeeds.
    @ObservationIgnored var onNextSignIn: (() -> Void)?

    var isSignedIn: Bool { token != nil }

    init() {
        if UITestMode.isActive {
            token = ProcessInfo.processInfo.environment["BOAZ_GITHUB_TOKEN"].flatMap { $0.isEmpty ? nil : $0 }
        } else {
            token = Self.secret.read()
            viewer = UserDefaults.standard.data(forKey: Self.viewerKey).flatMap { try? JSONDecoder().decode(GitHubViewer.self, from: $0) }
        }
    }

    var client: GitHubClient? { token.map { GitHubClient(token: $0) } }

    /// The signed-in user, fetched once per sign-in.
    func loadViewer() async {
        guard viewer == nil, let client else { return }
        if let viewer = try? await client.viewer() { setViewer(viewer) }
    }

    // MARK: Device flow

    func beginDeviceFlow() {
        flowTask?.cancel()
        flow = .requesting
        flowTask = Task { await runDeviceFlow() }
    }

    func cancelDeviceFlow() {
        flowTask?.cancel()
        flowTask = nil
        if flow != .signedIn { flow = .idle }
    }

    private func runDeviceFlow() async {
        do {
            if UITestMode.isActive, UITestMode.githubFixtureURL != nil {
                flow = .waiting(code: "BOAZ-TEST", verificationURL: URL(string: "https://github.com/login/device")!)
                // Long enough for a UI test to find the code: one query of the whole app can take a few seconds.
                try await Task.sleep(for: .seconds(6))
                try await finish(token: "fixture-token")
                return
            }
            let code: DeviceCode = try await post("https://github.com/login/device/code",
                                                  ["client_id": Self.clientID, "scope": Self.scopes])
            guard let verification = URL(string: code.verification_uri) else { throw GitHubError.api("GitHub sent no sign-in page.") }
            flow = .waiting(code: code.user_code, verificationURL: verification)
            var interval = max(code.interval ?? 5, 1)
            let expires = Date.now.addingTimeInterval(TimeInterval(code.expires_in))
            while Date.now < expires {
                try await Task.sleep(for: .seconds(interval))
                let answer: TokenAnswer = try await post("https://github.com/login/oauth/access_token", [
                    "client_id": Self.clientID, "device_code": code.device_code,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                ])
                if let token = answer.access_token {
                    try await finish(token: token)
                    return
                }
                switch answer.error {
                case "authorization_pending": continue
                case "slow_down": interval = answer.interval ?? interval + 5
                case "expired_token": throw GitHubError.api("The code expired. Start again for a new one.")
                case "access_denied": throw GitHubError.api("Sign-in was canceled on GitHub.")
                default: throw GitHubError.api(answer.error_description ?? answer.error ?? "GitHub didn't finish signing in.")
                }
            }
            throw GitHubError.api("The code expired. Start again for a new one.")
        } catch is CancellationError {
        } catch {
            flow = .failed(error.localizedDescription)
        }
    }

    /// Signs in with a personal access token, after checking GitHub accepts it.
    func signIn(personalAccessToken: String) async throws {
        let token = personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        flowTask?.cancel()
        try await finish(token: token)
    }

    private func finish(token: String) async throws {
        let viewer = try await GitHubClient(token: token).viewer()
        if !UITestMode.isActive { try Self.secret.save(token) }
        self.token = token
        setViewer(viewer)
        flow = .signedIn
        NotificationCenter.default.post(name: .githubAccountDidChange, object: nil)
        let next = onNextSignIn
        onNextSignIn = nil
        next?()
    }

    func signOut() {
        flowTask?.cancel()
        if !UITestMode.isActive {
            try? Self.secret.delete()
            UserDefaults.standard.removeObject(forKey: Self.viewerKey)
        }
        token = nil
        viewer = nil
        flow = .idle
        NotificationCenter.default.post(name: .githubAccountDidChange, object: nil)
    }

    private func setViewer(_ viewer: GitHubViewer) {
        self.viewer = viewer
        if !UITestMode.isActive {
            UserDefaults.standard.set(try? JSONEncoder().encode(viewer), forKey: Self.viewerKey)
        }
    }

    // MARK: Transport

    private struct DeviceCode: Decodable {
        var device_code: String
        var user_code: String
        var verification_uri: String
        var expires_in: Int
        var interval: Int?
    }

    private struct TokenAnswer: Decodable {
        var access_token: String?
        var error: String?
        var error_description: String?
        var interval: Int?
    }

    private func post<Answer: Decodable>(_ address: String, _ form: [String: String]) async throws -> Answer {
        var request = URLRequest(url: URL(string: address)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Boaz", forHTTPHeaderField: "User-Agent")
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let answer = try? JSONDecoder().decode(Answer.self, from: data) { return answer }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        throw GitHubError.api(status == 404 ? "GitHub doesn't know this app's client ID." : "GitHub answered with error \(status).")
    }
}
