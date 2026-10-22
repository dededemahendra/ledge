import Foundation

/// One row of the open island's GitHub panel (2026-10-22).
public struct GitHubRow: Sendable, Equatable, Identifiable {
    public enum Mark: Sendable, Equatable { case running, passed, failed, none, review }
    public let id: String
    public let mark: Mark
    public let title: String
    public let repo: String
    public let url: URL
}

/// The panel's headline (2026-10-22): what is most worth watching.
public struct GitHubHero: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case running, failed, review }
    /// The id of the row it stands in for.
    public let id: String
    public let kind: Kind
    /// "Checks running", "Run going", "Checks failed", "Review requested".
    public let tag: String
    public let title: String
    /// "ledge #5 · 4 of 6 checks · 1 failed".
    public let detail: String
    public let segments: [CheckSegment]
    /// When it started, for the clock; only while it runs.
    public let startedAt: Date?
    /// Who asks, for a review request.
    public let avatarURL: URL?
    public let url: URL
}

public struct GitHubPanelList: Sendable, Equatable {
    public let hero: GitHubHero?
    public let rows: [GitHubRow]
    /// How many did not fit.
    public let more: Int
}

public enum GitHubPanelRows {
    public static let rowsUnderHero = 2
    public static let rowsAlone = 5
    public static let moreURL = URL(string: "https://github.com/pulls")!

    /// The hero, then the rest as rows: the user's runs going now, their
    /// PRs (failed first, then running, then the rest, each in GitHub's
    /// order), then PRs waiting for their review. Under a hero there is room
    /// for two rows and the "N more" line; alone, for five, or four and the
    /// line.
    public static func make(_ snapshot: GitHubSnapshot) -> GitHubPanelList {
        let heads = Set(snapshot.mine.compactMap(\.headSHA))
        let runs = snapshot.runs.filter { $0.status == .running && !heads.contains($0.headSHA) }
        func order(_ pr: GitHubPR) -> Int {
            switch pr.checks?.state {
            case .failed?: 0
            case .pending?: 1
            default: 2
            }
        }
        let mine = snapshot.mine.enumerated()
            .sorted { (order($0.element), $0.offset) < (order($1.element), $1.offset) }
            .map(\.element)
        let hero = hero(runs: runs, mine: mine, requested: snapshot.requested)
        let rows = (runs.map { GitHubRow(id: "run:\($0.id)", mark: .running, title: $0.workflow, repo: $0.repo, url: $0.url) }
            + mine.map { GitHubRow(id: $0.id, mark: mark($0.checks?.state), title: "#\($0.number) \($0.title)", repo: $0.repo, url: $0.url) }
            + snapshot.requested.map { GitHubRow(id: "asked:\($0.id)", mark: .review, title: "#\($0.number) \($0.title)", repo: $0.repo, url: $0.url) })
            .filter { $0.id != hero?.id }
        let total = runs.count + max(snapshot.mineTotal, mine.count) + max(snapshot.requestedTotal, snapshot.requested.count)
            - (hero == nil ? 0 : 1)
        let limit = hero == nil ? rowsAlone : rowsUnderHero
        guard total > limit else { return GitHubPanelList(hero: hero, rows: rows, more: 0) }
        let shown = hero == nil ? limit - 1 : limit
        return GitHubPanelList(hero: hero, rows: Array(rows.prefix(shown)), more: total - shown)
    }

    /// Running (the one that started first; one with no time goes last),
    /// else failed, else a review request, else nothing.
    static func hero(runs: [GitHubRun], mine: [GitHubPR], requested: [GitHubPR]) -> GitHubHero? {
        let checking = mine.compactMap { pr -> GitHubHero? in
            guard let checks = pr.checks, checks.state == .pending else { return nil }
            return GitHubHero(id: pr.id, kind: .running, tag: "Checks running", title: pr.title,
                              detail: checksDetail(pr, checks), segments: checks.segments,
                              startedAt: checks.startedAt, avatarURL: nil, url: pr.url)
        }
        let going = runs.map { run in
            GitHubHero(id: "run:\(run.id)", kind: .running, tag: "Run going", title: run.workflow,
                       detail: "\(run.repo) · your run", segments: [], startedAt: run.startedAt ?? run.createdAt,
                       avatarURL: nil, url: run.url)
        }
        let first = (checking + going).enumerated().min { a, b in
            switch (a.element.startedAt, b.element.startedAt) {
            case let (x?, y?): return (x, a.offset) < (y, b.offset)
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.offset < b.offset
            }
        }
        if let first { return first.element }
        if let pr = mine.first(where: { $0.checks?.state == .failed }), let checks = pr.checks {
            return GitHubHero(id: pr.id, kind: .failed, tag: "Checks failed", title: pr.title,
                              detail: "\(pr.repo) #\(pr.number) · \(checks.failedName.map { "\($0) failed" } ?? "checks failed")",
                              segments: checks.segments, startedAt: nil, avatarURL: nil, url: checks.failedURL ?? pr.url)
        }
        if let pr = requested.first {
            return GitHubHero(id: "asked:\(pr.id)", kind: .review, tag: "Review requested", title: pr.title,
                              detail: "\(pr.repo) #\(pr.number) · \(pr.author ?? "Someone") asks for your review",
                              segments: [], startedAt: nil, avatarURL: pr.authorAvatarURL, url: pr.url)
        }
        return nil
    }

    /// "ledge #5 · 4 of 6 checks · 1 failed".
    static func checksDetail(_ pr: GitHubPR, _ checks: GitHubChecks) -> String {
        var parts = ["\(pr.repo) #\(pr.number)"]
        if !checks.segments.isEmpty {
            parts.append("\(checks.segments.filter { $0 != .running }.count) of \(checks.segments.count) checks")
        }
        let failed = checks.segments.filter { $0 == .failed }.count
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: " · ")
    }

    static func mark(_ state: CheckState?) -> GitHubRow.Mark {
        switch state {
        case .failed?: .failed
        case .pending?: .running
        case .passed?: .passed
        case nil: .none
        }
    }
}
