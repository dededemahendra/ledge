import Foundation

/// People's pictures for the island and Settings (2026-10-22): fetched from
/// GitHub's image server with no token and no cookies, the last 64 kept in
/// memory, none on disk. An address anywhere else is refused unasked.
public actor GitHubAvatars {
    public static let limit = 64

    private let fetch: GitHubClient.Fetch
    private var cache: [URL: Data] = [:]
    private var order: [URL] = []

    public init(fetch: @escaping GitHubClient.Fetch = GitHubClient.session) {
        self.fetch = fetch
    }

    /// The picture at `url`, from memory or GitHub's image server; `nil`
    /// when it cannot be had.
    public func image(at url: URL) async -> Data? {
        if let data = cache[url] { return data }
        guard url.scheme == "https", url.host()?.hasSuffix(".githubusercontent.com") == true else { return nil }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        guard let (data, response) = try? await fetch(request),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        if cache[url] == nil { order.append(url) }
        cache[url] = data
        if order.count > Self.limit { cache[order.removeFirst()] = nil }
        return data
    }
}
