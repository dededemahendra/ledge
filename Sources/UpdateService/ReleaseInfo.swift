import Foundation

/// The latest full release on GitHub (2026-10-22), read from
/// `GET /repos/{owner}/{repo}/releases/latest`: its version, its page, and
/// its disk image when it has one.
public struct ReleaseInfo: Sendable, Equatable {
    public let version: AppVersion
    public let pageURL: URL
    public let downloadURL: URL?

    public init(version: AppVersion, pageURL: URL, downloadURL: URL?) {
        self.version = version
        self.pageURL = pageURL
        self.downloadURL = downloadURL
    }

    /// GitHub's reply, or `nil` for anything that is not a full release
    /// with a version tag and a page.
    public static func decode(_ data: Data) -> ReleaseInfo? {
        struct Reply: Decodable {
            struct Asset: Decodable {
                let name: String
                let url: URL
                enum CodingKeys: String, CodingKey { case name, url = "browser_download_url" }
            }
            let tag: String
            let page: URL
            let draft: Bool?
            let prerelease: Bool?
            let assets: [Asset]?
            enum CodingKeys: String, CodingKey {
                case tag = "tag_name", page = "html_url", draft, prerelease, assets
            }
        }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data),
              reply.draft != true, reply.prerelease != true,
              let version = AppVersion(reply.tag) else { return nil }
        let disk = reply.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }?.url
        return ReleaseInfo(version: version, pageURL: reply.page, downloadURL: disk)
    }
}
