import Foundation

/// Made-up GitHub for the Settings preview and the debug probe
/// (2026-10-22). Nothing here is ever fetched.
public enum GitHubSample {
    public static let reviewer = "sam"
    static let link = URL(string: "https://github.com/pulls")!

    /// A PR of the user's whose checks failed.
    public static let pr = GitHubPR(id: "SAMPLE_1", number: 12, title: "Fix the date picker", url: link, repo: "web",
                                    author: "you", headSHA: "a1",
                                    checks: GitHubChecks(state: .failed, failedName: "test (macos)"))
    /// Someone else's PR, waiting for the user's review.
    public static let request = GitHubPR(id: "SAMPLE_9", number: 7, title: "Tidy the footer", url: link, repo: "site",
                                         author: reviewer)
    /// A deploy the user started.
    public static let run = GitHubRun(id: 1, workflow: "Deploy", repo: "web", url: link, headSHA: "d4", status: .passed,
                                      createdAt: Date(timeIntervalSinceReferenceDate: 0), startedAt: nil)

    /// The probe's story, a snapshot every three seconds from `start`: the
    /// baseline; checks start; they fail; a comment; an approval; merged by
    /// the reviewer; a review request.
    public static func story(login: String, start: Date) -> [GitHubSnapshot] {
        func at(_ step: Int) -> Date { start.addingTimeInterval(Double(step) * 3) }
        func main(_ checks: GitHubChecks?, reviews: [GitHubReview] = [], comments: [GitHubComment] = []) -> GitHubPR {
            GitHubPR(id: "SAMPLE_1", number: 12, title: "Fix the date picker", url: link, repo: "web", author: login,
                     headSHA: "a1", checks: checks, reviews: reviews, comments: comments)
        }
        let other = GitHubPR(id: "SAMPLE_2", number: 15, title: "Add dark mode", url: link, repo: "web", author: login,
                             headSHA: "b2", checks: GitHubChecks(state: .passed))
        let failed = GitHubChecks(state: .failed, failedName: "test (macos)")
        let comment = GitHubComment(id: "SAMPLE_C", author: reviewer, at: at(3), url: link)
        let approval = GitHubReview(id: "SAMPLE_R", author: reviewer, state: .approved, at: at(4), url: link)
        let done = main(failed, reviews: [approval], comments: [comment])
        return [
            GitHubSnapshot(login: login, takenAt: at(0), mine: [main(nil), other]),
            GitHubSnapshot(login: login, takenAt: at(1), mine: [main(GitHubChecks(state: .pending, startedAt: at(1))), other]),
            GitHubSnapshot(login: login, takenAt: at(2), mine: [main(failed), other]),
            GitHubSnapshot(login: login, takenAt: at(3), mine: [main(failed, comments: [comment]), other]),
            GitHubSnapshot(login: login, takenAt: at(4), mine: [done, other]),
            GitHubSnapshot(login: login, takenAt: at(5), mine: [other],
                           departed: [GitHubDeparture(pr: done, merged: true, by: reviewer)]),
            GitHubSnapshot(login: login, takenAt: at(6), mine: [other], requested: [request]),
        ]
    }
}
