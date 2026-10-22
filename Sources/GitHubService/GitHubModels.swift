import Foundation

/// A check rollup's verdict on a PR's latest commit (2026-10-22): GitHub's
/// `SUCCESS` is passed, `FAILURE` and `ERROR` are failed, the rest pending.
public enum CheckState: String, Sendable, Equatable {
    case pending, passed, failed
}

/// One check's state on a PR's latest commit (2026-10-22): a segment of
/// the island's ring and the panel's bar.
public enum CheckSegment: String, Sendable, Equatable {
    case passed, failed, running
}

/// The checks on a PR's latest commit: Actions and outside statuses alike.
public struct GitHubChecks: Sendable, Equatable {
    public let state: CheckState
    /// When the earliest check still going started, if GitHub says.
    public let startedAt: Date?
    /// The first failing check, by name, and where it is.
    public let failedName: String?
    public let failedURL: URL?
    /// Every check, finished first: passed, failed, then still going (2026-10-22).
    public let segments: [CheckSegment]

    public init(state: CheckState, startedAt: Date? = nil, failedName: String? = nil, failedURL: URL? = nil,
                segments: [CheckSegment] = []) {
        self.state = state
        self.startedAt = startedAt
        self.failedName = failedName
        self.failedURL = failedURL
        self.segments = segments
    }
}

public enum ReviewState: String, Sendable, Equatable {
    case approved, changesRequested, commented
    /// Pending or dismissed: never news.
    case other
}

public struct GitHubReview: Sendable, Equatable {
    public let id: String
    public let author: String
    public let state: ReviewState
    public let at: Date?
    public let url: URL?
    /// Their picture on GitHub's image server (2026-10-22).
    public let avatarURL: URL?

    public init(id: String, author: String, state: ReviewState, at: Date?, url: URL?, avatarURL: URL? = nil) {
        self.id = id
        self.author = author
        self.state = state
        self.at = at
        self.url = url
        self.avatarURL = avatarURL
    }
}

public struct GitHubComment: Sendable, Equatable {
    public let id: String
    public let author: String
    public let at: Date?
    public let url: URL?
    /// Their picture on GitHub's image server (2026-10-22).
    public let avatarURL: URL?

    public init(id: String, author: String, at: Date?, url: URL?, avatarURL: URL? = nil) {
        self.id = id
        self.author = author
        self.at = at
        self.url = url
        self.avatarURL = avatarURL
    }
}

/// One open pull request (2026-10-22): one of the user's, or one waiting
/// for their review.
public struct GitHubPR: Sendable, Equatable, Identifiable {
    /// GitHub's node ID.
    public let id: String
    public let number: Int
    public let title: String
    public let url: URL
    /// The repository's short name, "ledge".
    public let repo: String
    public let author: String?
    /// The author's picture (2026-10-22).
    public let authorAvatarURL: URL?
    public let headSHA: String?
    public let checks: GitHubChecks?
    /// The last ten, oldest first.
    public let reviews: [GitHubReview]
    public let comments: [GitHubComment]

    public init(id: String, number: Int, title: String, url: URL, repo: String, author: String? = nil,
                authorAvatarURL: URL? = nil,
                headSHA: String? = nil, checks: GitHubChecks? = nil,
                reviews: [GitHubReview] = [], comments: [GitHubComment] = []) {
        self.id = id
        self.number = number
        self.title = title
        self.url = url
        self.repo = repo
        self.author = author
        self.authorAvatarURL = authorAvatarURL
        self.headSHA = headSHA
        self.checks = checks
        self.reviews = reviews
        self.comments = comments
    }
}

public enum RunStatus: String, Sendable, Equatable {
    case running, passed, failed
    /// Cancelled, skipped, neutral: ends without a word.
    case quiet
}

/// A workflow run the user started (2026-10-22): a push, a merge, a tag.
public struct GitHubRun: Sendable, Equatable, Identifiable {
    public let id: Int
    public let workflow: String
    public let repo: String
    public let url: URL
    public let headSHA: String
    public let status: RunStatus
    public let createdAt: Date
    public let startedAt: Date?

    public init(id: Int, workflow: String, repo: String, url: URL, headSHA: String, status: RunStatus,
                createdAt: Date, startedAt: Date?) {
        self.id = id
        self.workflow = workflow
        self.repo = repo
        self.url = url
        self.headSHA = headSHA
        self.status = status
        self.createdAt = createdAt
        self.startedAt = startedAt
    }
}

/// A PR that left the user's open list since the last round: merged or
/// closed, and by whom.
public struct GitHubDeparture: Sendable, Equatable {
    public let pr: GitHubPR
    public let merged: Bool
    public let by: String?
    /// Their picture (2026-10-22).
    public let byAvatarURL: URL?

    public init(pr: GitHubPR, merged: Bool, by: String?, byAvatarURL: URL? = nil) {
        self.pr = pr
        self.merged = merged
        self.by = by
        self.byAvatarURL = byAvatarURL
    }
}

/// What one round of questions found (2026-10-22).
public struct GitHubSnapshot: Sendable, Equatable {
    public let login: String
    public let takenAt: Date
    /// Up to 50 of the user's open PRs.
    public let mine: [GitHubPR]
    /// How many open PRs the user has in all.
    public let mineTotal: Int
    /// Up to 20 PRs waiting for the user's review.
    public let requested: [GitHubPR]
    public let requestedTotal: Int
    public let runs: [GitHubRun]
    /// PRs gone from `mine` since the snapshot this round compared with.
    public let departed: [GitHubDeparture]
    /// GitHub left some organisations out: the token is not authorised for
    /// their single sign-on.
    public let hidesSomeOrganisations: Bool
    /// The user's own picture, for Settings (2026-10-22).
    public let avatarURL: URL?

    public init(login: String, takenAt: Date, mine: [GitHubPR] = [], mineTotal: Int? = nil,
                requested: [GitHubPR] = [], requestedTotal: Int? = nil, runs: [GitHubRun] = [],
                departed: [GitHubDeparture] = [], hidesSomeOrganisations: Bool = false, avatarURL: URL? = nil) {
        self.login = login
        self.takenAt = takenAt
        self.mine = mine
        self.mineTotal = mineTotal ?? mine.count
        self.requested = requested
        self.requestedTotal = requestedTotal ?? requested.count
        self.runs = runs
        self.departed = departed
        self.hidesSomeOrganisations = hidesSomeOrganisations
        self.avatarURL = avatarURL
    }
}
