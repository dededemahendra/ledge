import Foundation

/// The requests (2026-10-22). Everything goes to api.github.com with the
/// user's token; nothing else leaves the Mac. `fetch` is injected so the
/// tests can answer it.
public actor GitHubClient {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public enum Failure: Error, Sendable, Equatable {
        /// 401: the token is gone or revoked.
        case unauthorised
        case rateLimited(until: Date)
        /// Offline, a server error, an unreadable answer.
        case unavailable
    }

    public static let api = URL(string: "https://api.github.com")!

    private static let ephemeral: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // A reply that trickles in gives up after 30 seconds (2026-10-22).
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()
    public static let session: Fetch = { request in try await ephemeral.data(for: request) }

    private let token: String
    private let userAgent: String
    private let fetch: Fetch
    /// The last runs answer per URL with its ETag: a 304 reuses it, and
    /// costs nothing against the rate limit.
    private var cachedRuns: [URL: (etag: String, runs: [GitHubRun])] = [:]

    public init(token: String, userAgent: String, fetch: @escaping Fetch = GitHubClient.session) {
        self.token = token
        self.userAgent = userAgent
        self.fetch = fetch
    }

    /// One round: the query; the user's runs in repos pushed to in the last
    /// day (five at most); what became of PRs that left the list since
    /// `previous`.
    public func round(previous: GitHubSnapshot?, now: Date) async -> Result<GitHubSnapshot, Failure> {
        let answer: GitHubQuery.Answer
        switch await post(GitHubQuery.text, ids: nil, now: now) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let data):
            guard let decoded = GitHubQuery.decode(data) else { return .failure(.unavailable) }
            answer = decoded
        }

        var allRuns: [GitHubRun] = []
        for repo in answer.pushed.filter({ now.timeIntervalSince($0.at) < 24 * 60 * 60 }).prefix(5) {
            switch await runs(of: repo.fullName, actor: answer.login, now: now) {
            case .success(let found): allRuns += found
            case .failure(let failure): return .failure(failure)
            }
        }

        var departed: [GitHubDeparture] = []
        if let previous {
            let open = Set(answer.mine.map(\.id))
            let gone = previous.mine.filter { !open.contains($0.id) }
            // A failed lookup only loses the merged or closed blip.
            if !gone.isEmpty, case .success(let data) = await post(GitHubQuery.departuresText, ids: gone.map(\.id), now: now) {
                let outcomes = GitHubQuery.decodeDepartures(data)
                departed = gone.compactMap { pr in
                    outcomes[pr.id].map { GitHubDeparture(pr: pr, merged: $0.merged, by: $0.by, byAvatarURL: $0.byAvatarURL) }
                }
            }
        }

        return .success(GitHubSnapshot(
            login: answer.login, takenAt: now, mine: answer.mine, mineTotal: answer.mineTotal,
            requested: answer.requested, requestedTotal: answer.requestedTotal, runs: allRuns,
            departed: departed, hidesSomeOrganisations: answer.hidesSomeOrganisations,
            avatarURL: answer.avatarURL
        ))
    }

    private func post(_ query: String, ids: [String]?, now: Date) async -> Result<Data, Failure> {
        var request = URLRequest(url: Self.api.appending(path: "graphql"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["query": query]
        if let ids { body["variables"] = ["ids": ids] }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await fetch(request), let http = response as? HTTPURLResponse else {
            return .failure(.unavailable)
        }
        if let failure = Self.failure(for: http, now: now) { return .failure(failure) }
        return .success(data)
    }

    /// A repo without Actions, or one the token cannot see, answers 404:
    /// that repo just has no runs this round. Only a 401 or a rate limit
    /// stops the round.
    private func runs(of fullName: String, actor login: String, now: Date) async -> Result<[GitHubRun], Failure> {
        var components = URLComponents(url: Self.api.appending(path: "repos/\(fullName)/actions/runs"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "actor", value: login), URLQueryItem(name: "per_page", value: "10")]
        let url = components.url!
        let cached = cachedRuns[url]?.runs ?? []
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let etag = cachedRuns[url]?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        guard let (data, response) = try? await fetch(request), let http = response as? HTTPURLResponse else {
            return .success(cached)
        }
        if http.statusCode == 304 { return .success(cached) }
        if let failure = Self.failure(for: http, now: now) {
            return failure == .unavailable ? .success(cached) : .failure(failure)
        }
        guard let runs = GitHubRuns.decode(data) else { return .success(cached) }
        if let etag = http.value(forHTTPHeaderField: "ETag") { cachedRuns[url] = (etag, runs) }
        return .success(runs)
    }

    /// What a status says: nothing wrong (200, 304), a refused login, a
    /// rate limit with its end, or GitHub being unavailable. A spent primary
    /// limit counts whatever the status, since GraphQL answers it with a 200 (2026-10-22).
    static func failure(for response: HTTPURLResponse, now: Date) -> Failure? {
        if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0",
           let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init) {
            return .rateLimited(until: Date(timeIntervalSince1970: reset))
        }
        switch response.statusCode {
        case 200, 304:
            return nil
        case 401:
            return .unauthorised
        case 403, 429:
            if let wait = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) {
                return .rateLimited(until: now.addingTimeInterval(wait))
            }
            if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0",
               let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init) {
                return .rateLimited(until: Date(timeIntervalSince1970: reset))
            }
            return response.statusCode == 429 ? .rateLimited(until: now.addingTimeInterval(60)) : .unavailable
        default:
            return .unavailable
        }
    }
}
