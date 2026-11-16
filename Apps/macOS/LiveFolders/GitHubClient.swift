import BoazKit
import Foundation

/// The signed-in GitHub user.
struct GitHubViewer: Codable, Hashable, Sendable {
    var login: String
    var name: String?
    var avatarUrl: URL?
}

/// An open pull request, as GitHub's GraphQL `search` returns it (and as a test fixture lists it).
struct GitHubPull: Codable, Hashable, Sendable {
    struct Repository: Codable, Hashable, Sendable { var nameWithOwner: String }
    struct Author: Codable, Hashable, Sendable { var login: String; var avatarUrl: URL? }
    struct Commits: Codable, Hashable, Sendable {
        struct Node: Codable, Hashable, Sendable {
            struct Commit: Codable, Hashable, Sendable {
                struct Rollup: Codable, Hashable, Sendable { var state: String }
                var statusCheckRollup: Rollup?
            }
            var commit: Commit
        }
        var nodes: [Node]
    }

    var number: Int
    var title: String
    var url: URL
    var isDraft: Bool?
    var reviewDecision: String?
    var updatedAt: Date
    var repository: Repository
    var author: Author?
    var commits: Commits?

    /// The latest commit's checks, for the row's badge: nil when it has none.
    var checks: LiveFolderState.ItemStatus.Checks? {
        switch commits?.nodes.last?.commit.statusCheckRollup?.state {
        case "SUCCESS": .success
        case "FAILURE", "ERROR": .failure
        case "PENDING", "EXPECTED": .pending
        default: nil
        }
    }

    var status: LiveFolderState.ItemStatus {
        .init(checks: checks, review: reviewDecision, isDraft: isDraft ?? false,
              detail: "\(repository.nameWithOwner) #\(number)")
    }
}

/// What a refresh found: each search's pull requests, keyed by the search's qualifier, and the organizations whose
/// results GitHub held back until single sign-on is authorized.
struct GitHubSearchResult: Sendable {
    var pulls: [String: [GitHubPull]] = [:]
    var singleSignOn: [LiveFolderState.SingleSignOn] = []
}

enum GitHubError: LocalizedError, Equatable {
    case unauthorized
    case http(Int)
    case api(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "GitHub no longer accepts this sign-in. Sign in again."
        case .http(let code): "GitHub answered with error \(code)."
        case .api(let message): message
        }
    }
}

/// GitHub's GraphQL API, with the user's token. Under `UITestMode` with `BOAZ_GITHUB_FIXTURE` set, every answer comes
/// from that file instead (`GitHubFixture`), and nothing reaches the network.
struct GitHubClient: Sendable {
    let token: String
    var fixtureURL: URL? = UITestMode.githubFixtureURL

    static let graphQLURL = URL(string: "https://api.github.com/graphql")!

    // MARK: Requests

    func viewer() async throws -> GitHubViewer {
        if let fixture = try loadFixture() { return try fixture.answer { $0.viewer } }
        struct Data: Decodable { var viewer: GitHubViewer }
        let (data, _): (Data, _) = try await graphQL("query { viewer { login name avatarUrl } }")
        return data.viewer
    }

    /// "org/team" for every team the viewer is on, for Team Review Requests. Needs the read:org scope.
    func teams(login: String) async throws -> [String] {
        if let fixture = try loadFixture() { return try fixture.answer { $0.teams ?? [] } }
        struct Data: Decodable {
            struct Viewer: Decodable { var organizations: Nodes<Organization> }
            struct Organization: Decodable { var login: String; var teams: Nodes<Team> }
            struct Team: Decodable { var slug: String }
            var viewer: Viewer
        }
        let query = """
            query($login: String!) { viewer { organizations(first: 100) { nodes { login
                teams(first: 100, userLogins: [$login]) { nodes { slug } } } } } }
            """
        let (data, _): (Data, _) = try await graphQL(query, variables: ["login": login])
        return data.viewer.organizations.nodes.flatMap { org in org.teams.nodes.map { "\(org.login)/\($0.slug)" } }
    }

    /// The open pull requests matching each of `qualifiers` ("author:@me"), limited to `repositories` unless empty.
    func searchPulls(_ qualifiers: [String], repositories: [String]) async throws -> GitHubSearchResult {
        guard !qualifiers.isEmpty else { return GitHubSearchResult() }
        func inAllowlist(_ pull: GitHubPull) -> Bool {
            repositories.isEmpty || repositories.contains { $0.caseInsensitiveCompare(pull.repository.nameWithOwner) == .orderedSame }
        }
        if let fixture = try loadFixture() {
            return try fixture.answer { fixture in
                var result = GitHubSearchResult()
                for qualifier in qualifiers { result.pulls[qualifier] = (fixture.searches?[qualifier] ?? []).filter(inAllowlist) }
                result.singleSignOn = fixture.sso.map {
                    Self.singleSignOn(header: $0) { fixture.organizations?[$0] }
                } ?? []
                return result
            }
        }
        let scope = (["is:pr", "is:open", "archived:false"] + repositories.map { "repo:\($0)" }).joined(separator: " ")
        var variables: [String: String] = [:]
        var fields: [String] = []
        for (index, qualifier) in qualifiers.enumerated() {
            variables["q\(index)"] = "\(scope) \(qualifier)"
            fields.append("s\(index): search(type: ISSUE, first: 50, query: $q\(index)) { nodes { ...pull } }")
        }
        let query = """
            query(\(qualifiers.indices.map { "$q\($0): String!" }.joined(separator: ", "))) {
            \(fields.joined(separator: "\n"))
            }
            fragment pull on PullRequest {
                number title url isDraft reviewDecision updatedAt
                repository { nameWithOwner }
                author { login avatarUrl }
                commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
            }
            """
        let (data, response): ([String: Nodes<Lenient<GitHubPull>>?], HTTPURLResponse) =
            try await graphQL(query, variables: variables, allowPartial: true)
        var result = GitHubSearchResult()
        for (index, qualifier) in qualifiers.enumerated() {
            result.pulls[qualifier] = (data["s\(index)"] ?? nil)?.nodes.compactMap(\.value).filter(inAllowlist) ?? []
        }
        if let header = response.value(forHTTPHeaderField: "X-GitHub-SSO") {
            var logins: [String: String] = [:]
            for id in Self.ssoOrganizationIDs(header) { logins[id] = try? await organizationLogin(id: id) }
            result.singleSignOn = Self.singleSignOn(header: header) { logins[$0] }
        }
        return result
    }

    /// An organization's login from its numeric id (what `X-GitHub-SSO` names).
    func organizationLogin(id: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.github.com/organizations/\(id)")!)
        authorize(&request)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response)
        struct Organization: Decodable { var login: String }
        return try JSONDecoder().decode(Organization.self, from: data).login
    }

    // MARK: Single sign-on

    /// `X-GitHub-SSO: required; url=…` (the whole request needs authorizing) or `partial-results; organizations=1,2`
    /// (results from those organizations were left out).
    static func singleSignOn(header: String, login: (String) -> String?) -> [LiveFolderState.SingleSignOn] {
        let parts = header.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.first == "required",
           let value = parts.first(where: { $0.hasPrefix("url=") })?.dropFirst(4), let url = URL(string: String(value)) {
            let components = url.pathComponents
            let organization = components.firstIndex(of: "orgs").flatMap { components.indices.contains($0 + 1) ? components[$0 + 1] : nil }
            return [.init(organization: organization ?? "GitHub", url: url)]
        }
        return ssoOrganizationIDs(header).compactMap { id in
            guard let name = login(id), let url = URL(string: "https://github.com/orgs/\(name)/sso") else { return nil }
            return .init(organization: name, url: url)
        }
    }

    static func ssoOrganizationIDs(_ header: String) -> [String] {
        guard header.hasPrefix("partial-results"),
              let list = header.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) })
                .first(where: { $0.hasPrefix("organizations=") })?.dropFirst("organizations=".count)
        else { return [] }
        return list.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // MARK: Transport

    private struct Nodes<Node: Decodable>: Decodable { var nodes: [Node] }

    /// Decodes what it can: a search can return nodes that aren't pull requests (`{}`).
    private struct Lenient<Value: Decodable>: Decodable {
        var value: Value?
        init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
    }

    private struct Envelope<Payload: Decodable>: Decodable {
        struct Message: Decodable { var message: String; var type: String? }
        var data: Payload?
        var errors: [Message]?
    }

    private func authorize(_ request: inout URLRequest) {
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Boaz", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
    }

    private func graphQL<Payload: Decodable>(_ query: String, variables: [String: String] = [:],
                                             allowPartial: Bool = false) async throws -> (Payload, HTTPURLResponse) {
        var request = URLRequest(url: Self.graphQLURL)
        request.httpMethod = "POST"
        authorize(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response)
        let envelope = try Self.decoder.decode(Envelope<Payload>.self, from: data)
        // Partial data (one organization's results held back for single sign-on) still lists the rest.
        if let payload = envelope.data, allowPartial || envelope.errors?.isEmpty != false {
            return (payload, response as! HTTPURLResponse)
        }
        throw GitHubError.api(envelope.errors?.first?.message ?? "GitHub sent an answer Boaz couldn't read.")
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw GitHubError.http(0) }
        if http.statusCode == 401 { throw GitHubError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw GitHubError.http(http.statusCode) }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func loadFixture() throws -> GitHubFixture? {
        guard let fixtureURL else { return nil }
        return try Self.decoder.decode(GitHubFixture.self, from: Data(contentsOf: fixtureURL))
    }
}

/// Canned GitHub answers for UI tests (`BOAZ_GITHUB_FIXTURE`), read afresh on every request so a test can rewrite the
/// file between refreshes. Every key is optional:
///
///     {
///       "viewer": { "login": "octocat", "name": "The Octocat", "avatarUrl": "https://…" },
///       "teams": ["acme/web"],
///       "searches": {                       // keyed by the filter's qualifier
///         "author:@me": [ <pull>, … ],      // Created by Me
///         "review-requested:@me": [ … ],    // Review Requests
///         "team-review-requested:acme/web": [ … ],
///         "assignee:@me": [ … ], "mentions:@me": [ … ]
///       },
///       "sso": "partial-results; organizations=42",   // an X-GitHub-SSO header
///       "organizations": { "42": "acme" },             // org ids it names → logins
///       "error": "Simulated outage"                    // when set, every request fails with it
///     }
///
/// A `<pull>` is a GraphQL PullRequest node: `number`, `title`, `url`, `isDraft`, `reviewDecision`, `updatedAt`
/// (ISO 8601), `repository.nameWithOwner`, `author.login`, and
/// `commits.nodes[0].commit.statusCheckRollup.state` (SUCCESS, FAILURE, ERROR, PENDING or absent).
struct GitHubFixture: Decodable {
    var viewer: GitHubViewer?
    var teams: [String]?
    var searches: [String: [GitHubPull]]?
    var sso: String?
    var organizations: [String: String]?
    var error: String?

    func answer<T>(_ read: (GitHubFixture) throws -> T?) throws -> T {
        if let error { throw GitHubError.api(error) }
        guard let value = try read(self) else { throw GitHubError.api("The GitHub fixture has no answer for this.") }
        return value
    }
}
