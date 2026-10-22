import Foundation

/// One check's state, for the GitHub ring and the hero's bar (2026-10-22).
/// Top level, not nested in the main-actor island controller, so plain
/// values can carry it anywhere.
public enum IslandCheck: Sendable, Equatable {
    case passed, failed, running
}

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

    /// What is most worth watching, drawn as a card above the rows
    /// (2026-10-22).
    public struct Hero: Sendable, Equatable {
        public enum Kind: Sendable, Equatable { case running, failed, review }
        public let id: String
        public let kind: Kind
        public let tag: String
        public let title: String
        public let detail: String
        public let segments: [IslandCheck]
        /// When it started, for the clock; only while it runs.
        public let since: Date?
        /// Who asks, for a review request.
        public let avatar: Data?
        public let url: URL

        public init(id: String, kind: Kind, tag: String, title: String, detail: String,
                    segments: [IslandCheck], since: Date?, avatar: Data?, url: URL) {
            self.id = id
            self.kind = kind
            self.tag = tag
            self.title = title
            self.detail = detail
            self.segments = segments
            self.since = since
            self.avatar = avatar
            self.url = url
        }
    }

    public let hero: Hero?
    public let rows: [Row]
    /// How many did not fit; the last row says so and opens `moreURL`.
    public let more: Int
    public let moreURL: URL

    public init(hero: Hero? = nil, rows: [Row], more: Int = 0, moreURL: URL = URL(string: "https://github.com/pulls")!) {
        self.hero = hero
        self.rows = rows
        self.more = more
        self.moreURL = moreURL
    }
}
