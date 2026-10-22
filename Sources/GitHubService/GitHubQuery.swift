import Foundation

/// The GraphQL a round asks (2026-10-22), and how its answer is read. One
/// query covers the user, their open PRs with checks, reviews and comments,
/// the PRs waiting for their review, and the repos they pushed to last.
enum GitHubQuery {
    static let text = """
    query {
      me: viewer {
        login avatarUrl(size: 96)
        repositories(first: 10, orderBy: {field: PUSHED_AT, direction: DESC}, ownerAffiliations: [OWNER, ORGANIZATION_MEMBER, COLLABORATOR]) {
          nodes { nameWithOwner pushedAt }
        }
      }
      mine: search(query: "is:open is:pr author:@me archived:false", type: ISSUE, first: 50) {
        issueCount
        nodes { ...pr }
      }
      asked: search(query: "is:open is:pr review-requested:@me archived:false", type: ISSUE, first: 20) {
        issueCount
        nodes { ...pr }
      }
    }
    # Up to 100 checks a commit (2026-10-22): past 30, the ring and the bar undercounted.
    fragment pr on PullRequest {
      id number title url
      repository { name }
      author { login avatarUrl(size: 64) }
      commits(last: 1) { nodes { commit { oid statusCheckRollup { state contexts(first: 100) { nodes {
        __typename
        ... on CheckRun { name status conclusion startedAt detailsUrl }
        ... on StatusContext { context state createdAt targetUrl }
      } } } } } }
      reviews(last: 10) { nodes { id state submittedAt url author { login avatarUrl(size: 64) } } }
      comments(last: 10) { nodes { id createdAt url author { login avatarUrl(size: 64) } } }
    }
    """

    /// What became of PRs that left the list: merged or closed, and by whom.
    static let departuresText = """
    query($ids: [ID!]!) {
      nodes(ids: $ids) {
        ... on PullRequest {
          id state
          mergedBy { login avatarUrl(size: 64) }
          timelineItems(itemTypes: [CLOSED_EVENT], last: 1) { nodes { ... on ClosedEvent { actor { login avatarUrl(size: 64) } } } }
        }
      }
    }
    """

    struct Pushed: Sendable, Equatable {
        let fullName: String
        let at: Date
    }

    struct Answer: Sendable, Equatable {
        let login: String
        let mine: [GitHubPR]
        let mineTotal: Int
        let requested: [GitHubPR]
        let requestedTotal: Int
        /// Newest first.
        let pushed: [Pushed]
        let hidesSomeOrganisations: Bool
        let avatarURL: URL?
    }

    struct Outcome: Sendable, Equatable {
        let merged: Bool
        let by: String?
        let byAvatarURL: URL?
    }

    /// `nil` when there is no data to read. Errors beside data (an
    /// organisation's single sign-on, say) leave what did come.
    static func decode(_ data: Data) -> Answer? {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data),
              let body = wire.data, let me = body.me else { return nil }
        let hides = (wire.errors ?? []).contains { $0.type == "FORBIDDEN" || ($0.message ?? "").contains("SAML") }
        return Answer(
            login: me.login,
            mine: (body.mine?.nodes ?? []).compactMap { $0?.pr },
            mineTotal: body.mine?.issueCount ?? 0,
            requested: (body.asked?.nodes ?? []).compactMap { $0?.pr },
            requestedTotal: body.asked?.issueCount ?? 0,
            pushed: (me.repositories?.nodes ?? []).compactMap { repo in
                guard let repo, let at = date(repo.pushedAt) else { return nil }
                return Pushed(fullName: repo.nameWithOwner, at: at)
            },
            hidesSomeOrganisations: hides,
            avatarURL: me.avatarUrl.flatMap(URL.init(string:))
        )
    }

    /// By PR node ID; a PR that is still open is left out.
    static func decodeDepartures(_ data: Data) -> [String: Outcome] {
        guard let wire = try? JSONDecoder().decode(DeparturesWire.self, from: data) else { return [:] }
        var outcomes: [String: Outcome] = [:]
        for node in (wire.data?.nodes ?? []).compactMap({ $0 }) {
            guard let id = node.id else { continue }
            switch node.state ?? "" {
            case "MERGED":
                outcomes[id] = Outcome(merged: true, by: node.mergedBy?.login,
                                       byAvatarURL: node.mergedBy?.avatarUrl.flatMap(URL.init(string:)))
            case "CLOSED":
                let actor = node.timelineItems?.nodes?.compactMap { $0 }.last?.actor
                outcomes[id] = Outcome(merged: false, by: actor?.login, byAvatarURL: actor?.avatarUrl.flatMap(URL.init(string:)))
            default: continue
            }
        }
        return outcomes
    }

    static func date(_ text: String?) -> Date? {
        text.flatMap { try? Date($0, strategy: .iso8601) }
    }

    static func checks(_ rollup: Wire.Rollup) -> GitHubChecks? {
        let state: CheckState
        switch rollup.state ?? "" {
        case "SUCCESS": state = .passed
        case "FAILURE", "ERROR": state = .failed
        case "PENDING", "EXPECTED": state = .pending
        default: return nil
        }
        let contexts = (rollup.contexts?.nodes ?? []).compactMap { $0 }
        let going = contexts.compactMap { context -> Date? in
            if context.__typename == "CheckRun" { return context.status == "COMPLETED" ? nil : date(context.startedAt) }
            return context.state == "PENDING" || context.state == "EXPECTED" ? date(context.createdAt) : nil
        }
        let failing = contexts.first { context in
            context.__typename == "CheckRun"
                ? ["FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "CANCELLED", "ACTION_REQUIRED"].contains(context.conclusion ?? "")
                : ["FAILURE", "ERROR"].contains(context.state ?? "")
        }
        // A segment per check, finished first (2026-10-22): an unknown
        // state counts as still going.
        let segments = contexts.map { context -> CheckSegment in
            if context.__typename == "CheckRun" {
                guard context.status == "COMPLETED" else { return .running }
                switch context.conclusion ?? "" {
                case "FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "CANCELLED", "ACTION_REQUIRED": return .failed
                case "SUCCESS", "NEUTRAL", "SKIPPED", "STALE": return .passed
                default: return .running
                }
            }
            switch context.state ?? "" {
            case "SUCCESS": return .passed
            case "FAILURE", "ERROR": return .failed
            default: return .running
            }
        }
        return GitHubChecks(
            state: state,
            startedAt: going.min(),
            failedName: failing.flatMap { $0.name ?? $0.context },
            failedURL: failing.flatMap { ($0.detailsUrl ?? $0.targetUrl).flatMap(URL.init(string:)) },
            segments: segments.filter { $0 == .passed } + segments.filter { $0 == .failed } + segments.filter { $0 == .running }
        )
    }

    /// GitHub's JSON, every field optional: a missing one drops the item,
    /// not the round.
    struct Wire: Decodable {
        let data: Body?
        let errors: [Problem]?

        struct Problem: Decodable { let type: String?; let message: String? }
        struct Body: Decodable { let me: Me?; let mine: Search?; let asked: Search? }
        struct Me: Decodable { let login: String; let avatarUrl: String?; let repositories: Nodes<Repo>? }
        struct Repo: Decodable { let nameWithOwner: String; let pushedAt: String? }
        struct Search: Decodable { let issueCount: Int?; let nodes: [PR?]? }
        struct Nodes<T: Decodable>: Decodable { let nodes: [T?]? }
        struct Login: Decodable { let login: String?; let avatarUrl: String? }
        struct Named: Decodable { let name: String? }
        struct CommitNode: Decodable { let commit: Commit? }
        struct Commit: Decodable { let oid: String?; let statusCheckRollup: Rollup? }
        struct Rollup: Decodable { let state: String?; let contexts: Nodes<Context>? }
        struct Context: Decodable {
            let __typename: String?
            let name: String?, status: String?, conclusion: String?, startedAt: String?, detailsUrl: String?
            let context: String?, state: String?, createdAt: String?, targetUrl: String?
        }
        struct Review: Decodable { let id: String?; let state: String?; let submittedAt: String?; let url: String?; let author: Login? }
        struct Comment: Decodable { let id: String?; let createdAt: String?; let url: String?; let author: Login? }

        struct PR: Decodable {
            let id: String?, number: Int?, title: String?, url: String?
            let repository: Named?
            let author: Login?
            let commits: Nodes<CommitNode>?
            let reviews: Nodes<Review>?
            let comments: Nodes<Comment>?

            var pr: GitHubPR? {
                guard let id, let number, let title, let url = url.flatMap(URL.init(string:)),
                      let repo = repository?.name else { return nil }
                let commit = (commits?.nodes ?? []).compactMap { $0 }.last?.commit
                return GitHubPR(
                    id: id, number: number, title: title, url: url, repo: repo, author: author?.login,
                    authorAvatarURL: author?.avatarUrl.flatMap(URL.init(string:)),
                    headSHA: commit?.oid,
                    checks: commit?.statusCheckRollup.flatMap(GitHubQuery.checks),
                    reviews: (reviews?.nodes ?? []).compactMap { review in
                        guard let review, let id = review.id else { return nil }
                        let state: ReviewState = switch review.state ?? "" {
                        case "APPROVED": .approved
                        case "CHANGES_REQUESTED": .changesRequested
                        case "COMMENTED": .commented
                        default: .other
                        }
                        return GitHubReview(id: id, author: review.author?.login ?? "ghost", state: state,
                                            at: GitHubQuery.date(review.submittedAt), url: review.url.flatMap(URL.init(string:)),
                                            avatarURL: review.author?.avatarUrl.flatMap(URL.init(string:)))
                    },
                    comments: (comments?.nodes ?? []).compactMap { comment in
                        guard let comment, let id = comment.id else { return nil }
                        return GitHubComment(id: id, author: comment.author?.login ?? "ghost",
                                             at: GitHubQuery.date(comment.createdAt), url: comment.url.flatMap(URL.init(string:)),
                                             avatarURL: comment.author?.avatarUrl.flatMap(URL.init(string:)))
                    }
                )
            }
        }
    }

    struct DeparturesWire: Decodable {
        let data: Body?
        struct Body: Decodable { let nodes: [Node?]? }
        struct Node: Decodable {
            let id: String?
            let state: String?
            let mergedBy: Wire.Login?
            let timelineItems: Wire.Nodes<Closed>?
        }
        struct Closed: Decodable { let actor: Wire.Login? }
    }
}
