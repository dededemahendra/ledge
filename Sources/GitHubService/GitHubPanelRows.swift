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

public struct GitHubPanelList: Sendable, Equatable {
    public let rows: [GitHubRow]
    /// How many did not fit.
    public let more: Int
}

public enum GitHubPanelRows {
    public static let limit = 4
    public static let moreURL = URL(string: "https://github.com/pulls")!

    /// The user's runs going now, their PRs (failed first, then running,
    /// then the rest, each in GitHub's order), then PRs waiting for their
    /// review. More than `limit`: one row fewer, and the count of the rest.
    public static func make(_ snapshot: GitHubSnapshot) -> GitHubPanelList {
        let heads = Set(snapshot.mine.compactMap(\.headSHA))
        let runs = snapshot.runs.filter { $0.status == .running && !heads.contains($0.headSHA) }.map {
            GitHubRow(id: "run:\($0.id)", mark: .running, title: $0.workflow, repo: $0.repo, url: $0.url)
        }
        func order(_ pr: GitHubPR) -> Int {
            switch pr.checks?.state {
            case .failed?: 0
            case .pending?: 1
            default: 2
            }
        }
        let mine = snapshot.mine.enumerated()
            .sorted { (order($0.element), $0.offset) < (order($1.element), $1.offset) }
            .map { GitHubRow(id: $0.element.id, mark: mark($0.element.checks?.state), title: "#\($0.element.number) \($0.element.title)",
                             repo: $0.element.repo, url: $0.element.url) }
        let asked = snapshot.requested.map {
            GitHubRow(id: "asked:\($0.id)", mark: .review, title: "#\($0.number) \($0.title)", repo: $0.repo, url: $0.url)
        }
        let all = runs + mine + asked
        let total = runs.count + max(snapshot.mineTotal, mine.count) + max(snapshot.requestedTotal, asked.count)
        guard total > limit else { return GitHubPanelList(rows: all, more: 0) }
        return GitHubPanelList(rows: Array(all.prefix(limit - 1)), more: total - (limit - 1))
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
