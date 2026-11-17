import BoazKit
import Foundation

/// An open pull request, as github.com's pull request dashboard lists it (and as a test fixture lists it). What the
/// page doesn't say is nil.
struct GitHubPull: Codable, Hashable, Sendable {
    var url: URL
    var number: Int
    var title: String
    /// "owner/name".
    var repository: String
    var isDraft: Bool?
    var updatedAt: Date?
    /// The head commit's checks: SUCCESS, FAILURE, ERROR, PENDING or EXPECTED.
    var checks: String?
    /// APPROVED, CHANGES_REQUESTED or REVIEW_REQUIRED.
    var review: String?

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(URL.self, forKey: .url)
        number = try c.decode(Int.self, forKey: .number)
        title = try c.decode(String.self, forKey: .title)
        repository = try c.decode(String.self, forKey: .repository)
        isDraft = try? c.decodeIfPresent(Bool.self, forKey: .isDraft)
        updatedAt = try? c.decodeIfPresent(Date.self, forKey: .updatedAt)
        checks = try? c.decodeIfPresent(String.self, forKey: .checks)
        review = try? c.decodeIfPresent(String.self, forKey: .review)
    }

    var status: LiveFolderState.ItemStatus {
        let checks: LiveFolderState.ItemStatus.Checks? = switch self.checks {
        case "SUCCESS": .success
        case "FAILURE", "ERROR": .failure
        case "PENDING", "EXPECTED": .pending
        default: nil
        }
        return .init(checks: checks, review: review, isDraft: isDraft ?? false, detail: "\(repository) #\(number)",
                     title: title)
    }
}

/// What a refresh found: each search's pull requests, keyed by its qualifier ("author:@me"), and the organizations
/// whose pull requests GitHub leaves out until the user renews their single sign-on.
struct GitHubSearchResult: Sendable {
    var signedIn = true
    var pulls: [String: [GitHubPull]] = [:]
    var singleSignOn: [LiveFolderState.SingleSignOn] = []
}

struct GitHubError: LocalizedError {
    let errorDescription: String?
}

/// github.com read the way Arc reads it: as the signed-in user, from a page no window shows (`BackgroundPage`) in the
/// folder's profile, so it lists what github.com lists them. No OAuth app, token or scope: whatever the profile's
/// session can see, including organizations that block third-party apps.
///
/// Under `UITestMode` with `BOAZ_GITHUB_FIXTURE` set, the answer comes from that file instead (`GitHubWeb.Answer`),
/// read afresh each refresh, and nothing reaches the network; `BOAZ_GITHUB_SIGNED_OUT` answers as if no one is
/// signed in.
enum GitHubWeb {
    static let loginURL = URL(string: "https://github.com/login")!
    /// A light github.com document to run in: the script only needs its origin.
    static let pageURL = URL(string: "https://github.com/robots.txt")!

    /// The script's answer, and a fixture's format:
    ///
    ///     {
    ///       "signedIn": true,
    ///       "singleSignOn": [{ "login": "acme" }],      // organizations awaiting single sign-on
    ///       "searches": { "author:@me": [ <pull>, … ] },  // keyed by qualifier
    ///       "error": "Simulated outage"                   // fixtures only: fails every refresh
    ///     }
    ///
    /// A `<pull>` is a `GitHubPull`: `url`, `number`, `title`, `repository`, and optionally `isDraft`, `updatedAt`
    /// (ISO 8601), `checks` and `review`.
    struct Answer: Decodable {
        struct Organization: Decodable { var login: String }
        var signedIn: Bool?
        var singleSignOn: [Organization]?
        var searches: [String: [Lenient<GitHubPull>]]?
        var error: String?
    }

    /// Decodes what it can: one odd row never hides the rest.
    struct Lenient<Value: Decodable>: Decodable {
        var value: Value?
        init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
    }

    /// The open pull requests matching each of `qualifiers`, as `profileID`'s github.com session sees them.
    @MainActor
    static func searchPulls(_ qualifiers: [String], profileID: String) async throws -> GitHubSearchResult {
        guard !qualifiers.isEmpty else { return GitHubSearchResult() }
        let data: Data
        if let fixture = UITestMode.githubFixtureURL {
            if ProcessInfo.processInfo.environment["BOAZ_GITHUB_SIGNED_OUT"] != nil { return GitHubSearchResult(signedIn: false) }
            data = try Data(contentsOf: fixture)
        } else {
            let arguments = try JSONSerialization.data(withJSONObject: ["qualifiers": qualifiers])
            data = Data(try await BackgroundPage.run(script, arguments: String(decoding: arguments, as: UTF8.self),
                                                     at: pageURL, profileID: profileID).utf8)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let answer = try decoder.decode(Answer.self, from: data)
        if let error = answer.error { throw GitHubError(errorDescription: error) }
        guard answer.signedIn ?? false else { return GitHubSearchResult(signedIn: false) }
        var result = GitHubSearchResult()
        for qualifier in qualifiers { result.pulls[qualifier] = answer.searches?[qualifier]?.compactMap(\.value) ?? [] }
        result.singleSignOn = (answer.singleSignOn ?? []).compactMap { organization in
            URL(string: "https://github.com/orgs/\(organization.login)/sso").map { .init(organization: organization.login, url: $0) }
        }
        return result
    }

    /// Runs in a github.com document with the profile's cookies; answers an `Answer` as JSON text.
    ///
    /// Each qualifier is one search of github.com/pulls (the page behind its Created, Assigned, Mentioned and Review
    /// requests tabs), at most two pages of 25. The first comes as HTML: only its embedded React data
    /// (`script[data-target="react-app.embeddedData"]`) names the signed-in user and the organizations awaiting single
    /// sign-on (`sso_organizations`). The rest ask for JSON, the same data without the page. Pull requests are found
    /// by their URL anywhere in that data rather than at one path, and checks and review state come from
    /// /pulls/deferred, as the page itself fetches them. If GitHub's markup changes enough that a search comes back
    /// with no pulls and no evidence it's genuinely empty, the script throws rather than answering a false zero.
    static let script = #"""
        async ({qualifiers}) => {
            const scope = 'is:pr state:open archived:false sort:updated-desc ';
            const pullURL = /^https:\/\/github\.com\/([^/?#]+\/[^/?#]+)\/pull\/(\d+)$/;
            const absolute = (value) => typeof value !== 'string' ? null : value.startsWith('/') ? 'https://github.com' + value : value;
            const text = (value) => typeof value === 'string' ? value : null;
            const walk = (value, visit, depth = 0) => {
                if (!value || typeof value !== 'object' || depth > 16) return;
                if (visit(value) === false) return;
                for (const child of Array.isArray(value) ? value : Object.values(value)) walk(child, visit, depth + 1);
            };
            const signedOut = (response) => /^\/(login|sessions?)\b/.test(new URL(response.url).pathname);
            const read = async (path, html) => {
                const response = await fetch(path, {credentials: 'include', headers: html ? {} : {Accept: 'application/json'}});
                if (signedOut(response)) return null;
                if (response.status === 429) throw new Error('GitHub rate limit exceeded.');
                if (!response.ok) throw new Error('GitHub answered with error ' + response.status + '.');
                const body = await response.text();
                if (!html) { try { return {data: JSON.parse(body)}; } catch {} }
                const doc = new DOMParser().parseFromString(body, 'text/html');
                let data = null;
                try { data = JSON.parse(doc.querySelector('script[data-target="react-app.embeddedData"]')?.textContent ?? 'null'); } catch {}
                // A page without the embedded data still links its pull requests.
                const links = data ? [] : [...doc.querySelectorAll('a[href*="/pull/"]')]
                    .map((a) => ({permalink: a.getAttribute('href'), title: a.textContent.trim()}));
                return {data: data ?? {links}, login: doc.querySelector('meta[name="user-login"]')?.content ?? ''};
            };
            const pulls = (data) => {
                const found = new Map();
                walk(data, (value) => {
                    if (Array.isArray(value)) return;
                    const url = [value.permalink, value.url, value.html_url].map(absolute).find((link) => link && pullURL.test(link));
                    if (!url || !text(value.title)) return;
                    // Only an explicit CLOSED or MERGED state drops a row: draft, open and anything unrecognized stay.
                    const state = text(value.state) ?? text(value.displayState);
                    if (state && /^(closed|merged)$/i.test(state)) return false;
                    const [, repository, number] = url.match(pullURL);
                    if (!found.has(url)) found.set(url, {
                        url, number: Number(number), title: value.title.trim(),
                        repository: text(value.repoNameWithOwner) ?? repository,
                        id: value.id == null ? null : String(value.id),
                        isDraft: typeof value.isDraft === 'boolean' ? value.isDraft : null,
                        updatedAt: text(value.updatedAt),
                        checks: text(value.statusCheckRollup?.state),
                        review: text(value.reviewDecision) ?? text(value.reviewDecisionState),
                    });
                    return false;
                });
                return [...found.values()];
            };
            const totalPages = (data) => {
                let pages = 1;
                walk(data, (value) => { if (typeof value.totalPages === 'number') { pages = value.totalPages; return false; } });
                return pages;
            };
            // Whether `data` itself says how many pull requests there are (even zero): a numeric total/totalPages,
            // pagination info, or an explicit empty-results marker. Without this, zero pulls found could as easily
            // mean GitHub's markup changed as a genuinely empty search.
            const hasCountEvidence = (data) => {
                let found = false;
                walk(data, (value) => {
                    if (typeof value.total === 'number' || typeof value.totalCount === 'number'
                        || typeof value.totalPages === 'number' || 'pageInfo' in value
                        || value.blankslate === true || value.emptyState === true) { found = true; return false; }
                });
                return found;
            };
            const enrich = async (query, page, list) => {
                const ids = list.map((pull) => pull.id).filter(Boolean);
                if (!ids.length) return;
                const params = new URLSearchParams({q: query, page: String(page)});
                for (const id of ids) params.append('ids[]', id);
                try {
                    const answer = await read('/pulls/deferred?' + params, false);
                    const byID = new Map();
                    walk(answer?.data, (value) => {
                        if (Array.isArray(value) || value.id == null || !('statusCheckRollup' in value || 'reviewDecisionState' in value)) return;
                        byID.set(String(value.id), value);
                        return false;
                    });
                    for (const pull of list) {
                        const extra = byID.get(pull.id);
                        if (!extra) continue;
                        pull.checks ??= text(extra.statusCheckRollup?.state);
                        pull.review ??= text(extra.reviewDecisionState) ?? text(extra.reviewDecision);
                    }
                } catch {}
            };
            const search = async (qualifier, html) => {
                const query = scope + qualifier;
                const path = (page) => '/pulls/search?' + new URLSearchParams(page > 1 ? {q: query, page: String(page)} : {q: query});
                const first = await read(path(1), html);
                if (!first) return null;
                const result = {first, list: pulls(first.data), parsed: false};
                result.parsed = result.list.length > 0 || hasCountEvidence(first.data);
                await enrich(query, 1, result.list);
                if (totalPages(first.data) > 1) {
                    const second = await read(path(2), false);
                    if (second) {
                        const more = pulls(second.data).filter((pull) => !result.list.some((known) => known.url === pull.url));
                        await enrich(query, 2, more);
                        result.list.push(...more);
                    }
                }
                return result;
            };
            const [head, ...rest] = qualifiers;
            const first = await search(head, true);
            if (!first) return JSON.stringify({signedIn: false});
            const others = await Promise.all(rest.map((qualifier) => search(qualifier, false)));
            if (others.some((result) => !result)) return JSON.stringify({signedIn: false});
            // A search with no pulls and no sign it's genuinely empty (GitHub's markup changed under us) must not
            // report a false, folder-emptying zero: fail the whole refresh instead.
            if ([first, ...others].some((result) => !result.parsed)) {
                throw new Error("GitHub's page changed; Boaz couldn't read it.");
            }
            const organizations = new Map();
            walk(first.first.data, (value) => {
                if (!Array.isArray(value.sso_organizations)) return;
                for (const organization of value.sso_organizations) {
                    const login = text(organization?.login);
                    if (login) organizations.set(login.toLowerCase(), {login});
                }
                return false;
            });
            let login = first.first.login;
            walk(first.first.data, (value) => { if (!login && text(value.current_user?.login)) { login = value.current_user.login; return false; } });
            const searches = {};
            [first, ...others].forEach((result, index) => { searches[qualifiers[index]] = result.list.map(({id, ...pull}) => pull); });
            return JSON.stringify({signedIn: Boolean(login), singleSignOn: [...organizations.values()], searches});
        }
        """#
}
