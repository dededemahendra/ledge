import Foundation

/// Something that happened on GitHub between two rounds (2026-10-22).
public enum GitHubEvent: Sendable, Equatable {
    case checksPassed(GitHubPR)
    case checksFailed(GitHubPR)
    case reviewed(GitHubPR, GitHubReview)
    case commented(GitHubPR, GitHubComment)
    case merged(GitHubPR)
    case closed(GitHubPR)
    case reviewRequested(GitHubPR)
    case runPassed(GitHubRun)
    case runFailed(GitHubRun)
}

/// Something going on now: a PR's checks, or a run of the user's.
public struct GitHubRunning: Sendable, Equatable {
    public enum Source: Sendable, Equatable { case checks, run }
    public let key: String
    public let source: Source
    public let caption: String
    public let url: URL
    public let startedAt: Date?

    public init(key: String, source: Source, caption: String, url: URL, startedAt: Date?) {
        self.key = key
        self.source = source
        self.caption = caption
        self.url = url
        self.startedAt = startedAt
    }
}

public enum GitHubEvents {
    /// GitHub's clock and the Mac's can differ a little: something not seen
    /// before counts as new if it is no older than the last round, give or
    /// take two minutes.
    static let slack: TimeInterval = 120

    /// What happened between two rounds. The first round (`old` is `nil`)
    /// only sets the baseline. The user's own reviews, comments, merges and
    /// closes are left out; runs they start are the point.
    public static func between(_ old: GitHubSnapshot?, _ new: GitHubSnapshot) -> [GitHubEvent] {
        guard let old else { return [] }
        let me = new.login
        let since = old.takenAt.addingTimeInterval(-slack)
        func fresh(_ at: Date?) -> Bool { (at ?? new.takenAt) > since }
        var events: [GitHubEvent] = []

        let before = Dictionary(old.mine.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for pr in new.mine {
            let was = before[pr.id]
            // Once per head commit: a result already seen on this commit is
            // not news, and a new commit's pending checks are quiet.
            if let checks = pr.checks, checks.state != .pending,
               !(was?.headSHA == pr.headSHA && was?.checks?.state == checks.state) {
                events.append(checks.state == .passed ? .checksPassed(pr) : .checksFailed(pr))
            }
            let seenReviews = Set(was?.reviews.map(\.id) ?? [])
            for review in pr.reviews where review.author != me && review.state != .other
                && !seenReviews.contains(review.id) && fresh(review.at) {
                events.append(.reviewed(pr, review))
            }
            let seenComments = Set(was?.comments.map(\.id) ?? [])
            for comment in pr.comments where comment.author != me
                && !seenComments.contains(comment.id) && fresh(comment.at) {
                events.append(.commented(pr, comment))
            }
        }

        for departure in new.departed where departure.by != me {
            events.append(departure.merged ? .merged(departure.pr) : .closed(departure.pr))
        }

        let asked = Set(old.requested.map(\.id))
        for pr in new.requested where !asked.contains(pr.id) {
            events.append(.reviewRequested(pr))
        }

        let heads = Set(new.mine.compactMap(\.headSHA))
        let runsBefore = Dictionary(old.runs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for run in new.runs where !heads.contains(run.headSHA) {
            let was = runsBefore[run.id]
            guard run.status == .passed || run.status == .failed, was?.status != run.status else { continue }
            // A repo pushed to today brings its last ten runs with it.
            guard was != nil || fresh(run.createdAt) else { continue }
            events.append(run.status == .passed ? .runPassed(run) : .runFailed(run))
        }
        return events
    }

    /// As `between(_:_:)`, remembering the commits whose checks have passed
    /// (2026-10-22): a pass is told once per PR head commit even when the
    /// rollup goes back to pending in between, as when a late check joins;
    /// a failure is told each time, since a re-run that fails again is news.
    /// `passed` keeps only the PRs' current commits.
    public static func between(_ old: GitHubSnapshot?, _ new: GitHubSnapshot, passed: inout Set<String>) -> [GitHubEvent] {
        func key(_ pr: GitHubPR) -> String { "\(pr.id) \(pr.headSHA ?? "")" }
        let seen = passed
        let events = between(old, new).filter { event in
            if case .checksPassed(let pr) = event { return !seen.contains(key(pr)) }
            return true
        }
        passed = passed.intersection(new.mine.map(key))
            .union(new.mine.filter { $0.checks?.state == .passed }.map(key))
        return events
    }

    /// What is going on now: the user's PRs whose checks are pending, then
    /// their runs outside PRs.
    public static func running(in snapshot: GitHubSnapshot) -> [GitHubRunning] {
        let checks = snapshot.mine.compactMap { pr -> GitHubRunning? in
            guard let state = pr.checks, state.state == .pending else { return nil }
            return GitHubRunning(key: "pr:\(pr.id):\(pr.headSHA ?? "")", source: .checks,
                                 caption: GitHubNotice.prCaption(pr), url: pr.url, startedAt: state.startedAt)
        }
        let heads = Set(snapshot.mine.compactMap(\.headSHA))
        let runs = snapshot.runs.filter { $0.status == .running && !heads.contains($0.headSHA) }.map { run in
            GitHubRunning(key: "run:\(run.id)", source: .run, caption: GitHubNotice.runCaption(run), url: run.url,
                          startedAt: run.startedAt ?? run.createdAt)
        }
        return checks + runs
    }
}

/// Keeps each running item's start (2026-10-22): GitHub's own time when it
/// gives one, else when Ledge first saw it, so the clock never jumps back.
public struct RunningClock: Sendable {
    public struct Lead: Sendable, Equatable {
        public let item: GitHubRunning
        public let since: Date
        /// How many are running, the lead included.
        public let count: Int
    }

    private var since: [String: Date] = [:]

    public init() {}

    /// The item that started first, since when, and how many run; `nil`
    /// when nothing does. Forgets what is no longer running.
    public mutating func lead(of items: [GitHubRunning], now: Date) -> Lead? {
        var next: [String: Date] = [:]
        for item in items { next[item.key] = item.startedAt ?? since[item.key] ?? now }
        since = next
        guard let first = items.min(by: { (next[$0.key] ?? now) < (next[$1.key] ?? now) }) else { return nil }
        return Lead(item: first, since: next[first.key] ?? now, count: items.count)
    }
}
