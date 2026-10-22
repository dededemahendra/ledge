import Foundation

/// What the open island's GitHub panel lists (2026-10-22). Built by
/// `AppModel` from GitHubService's rows; pure here, so NotchKit stays free
/// of the service.
public struct GitHubPanelData: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public enum Mark: Sendable, Equatable { case running, passed, failed, none, review }
        public let id: String
        public let mark: Mark
        public let title: String
        public let repo: String
        public let url: URL

        public init(id: String, mark: Mark, title: String, repo: String, url: URL) {
            self.id = id
            self.mark = mark
            self.title = title
            self.repo = repo
            self.url = url
        }
    }

    public let rows: [Row]
    /// How many did not fit; the last row says so and opens `moreURL`.
    public let more: Int
    public let moreURL: URL

    public init(rows: [Row], more: Int = 0, moreURL: URL = URL(string: "https://github.com/pulls")!) {
        self.rows = rows
        self.more = more
        self.moreURL = moreURL
    }
}
