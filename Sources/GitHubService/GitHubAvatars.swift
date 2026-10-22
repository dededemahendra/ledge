import Foundation

/// People's pictures for the island and Settings (2026-10-22): fetched from
/// GitHub's image server with no token and no cookies, the last 64 kept in
/// memory, none on disk. An address anywhere else is refused unasked, and
/// redirects off the server are refused, and so is anything over 1 MB (2026-10-22).
public actor GitHubAvatars {
    public static let limit = 64
    public static let maximumBytes = 1_000_000

    /// Avatars' own session (2026-10-22): nothing kept on disk, no cookies
    /// either way, and no redirect off GitHub's image server.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration, delegate: StayOnGitHub(), delegateQueue: nil)
    }()
    public static let fetchImage: GitHubClient.Fetch = { request in try await session.data(for: request) }

    /// Refuses any redirect that would leave GitHub's image server.
    final class StayOnGitHub: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            request.url.map(GitHubAvatars.isGitHubImage) == true ? request : nil
        }
    }

    /// `https`, on `*.githubusercontent.com`.
    static func isGitHubImage(_ url: URL) -> Bool {
        url.scheme == "https" && url.host()?.hasSuffix(".githubusercontent.com") == true
    }

    private let fetch: GitHubClient.Fetch
    private var cache: [URL: Data] = [:]
    private var order: [URL] = []

    public init(fetch: @escaping GitHubClient.Fetch = GitHubAvatars.fetchImage) {
        self.fetch = fetch
    }

    /// The picture at `url`, from memory or GitHub's image server; `nil`
    /// when it cannot be had.
    public func image(at url: URL) async -> Data? {
        if let data = cache[url] { return data }
        guard Self.isGitHubImage(url) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpShouldHandleCookies = false
        guard let (data, response) = try? await fetch(request),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty,
              data.count <= Self.maximumBytes,
              Self.isGitHubImage((response as? HTTPURLResponse)?.url ?? url) else { return nil }
        if cache[url] == nil { order.append(url) }
        cache[url] = data
        if order.count > Self.limit { cache[order.removeFirst()] = nil }
        return data
    }
}
