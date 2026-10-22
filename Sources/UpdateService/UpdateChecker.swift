import Foundation

/// Asks GitHub for the latest release (2026-10-22): the app's only network
/// request. No cookies or cache, a `Ledge/<version>` User-Agent, a 15 s
/// timeout; anything but a readable 200 is "could not check". `fetch` is
/// injected so the tests can answer it.
public struct UpdateChecker: Sendable {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/dededemahendra/ledge/releases/latest")!

    private static let ephemeral = URLSession(configuration: .ephemeral)
    public static let session: Fetch = { request in try await ephemeral.data(for: request) }

    let currentVersion: AppVersion
    let fetch: Fetch

    public init(currentVersion: AppVersion, fetch: @escaping Fetch = UpdateChecker.session) {
        self.currentVersion = currentVersion
        self.fetch = fetch
    }

    public func latestRelease() async -> ReleaseInfo? {
        var request = URLRequest(url: Self.latestReleaseURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Ledge/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await fetch(request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return ReleaseInfo.decode(data)
    }

    /// One check, decided; `nil` when it could not be made or read.
    public func check(lastAnnounced: AppVersion?) async -> UpdateFinding? {
        guard let latest = await latestRelease() else { return nil }
        return UpdateDecision.evaluate(current: currentVersion, latest: latest, lastAnnounced: lastAnnounced)
    }
}
