import Foundation

/// The Actions runs answer (2026-10-22). Runs a PR sets off are its checks,
/// and scheduled runs are nobody's doing: both are left out here.
enum GitHubRuns {
    static func decode(_ data: Data) -> [GitHubRun]? {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        return (wire.workflow_runs ?? []).compactMap { run in
            let event = run.event ?? ""
            guard !event.hasPrefix("pull_request"), event != "schedule",
                  let url = URL(string: run.html_url), let created = GitHubQuery.date(run.created_at) else { return nil }
            return GitHubRun(id: run.id, workflow: run.name ?? "Workflow", repo: run.repository?.name ?? "",
                             url: url, headSHA: run.head_sha, status: status(run.status, run.conclusion),
                             createdAt: created, startedAt: GitHubQuery.date(run.run_started_at))
        }
    }

    static func status(_ status: String?, _ conclusion: String?) -> RunStatus {
        guard status == "completed" else { return .running }
        switch conclusion ?? "" {
        case "success": return .passed
        case "failure", "timed_out", "startup_failure": return .failed
        default: return .quiet
        }
    }

    private struct Wire: Decodable {
        let workflow_runs: [Run]?
        struct Run: Decodable {
            let id: Int
            let name: String?
            let status: String?
            let conclusion: String?
            let html_url: String
            let head_sha: String
            let created_at: String
            let run_started_at: String?
            let event: String?
            let repository: Repo?
        }
        struct Repo: Decodable { let name: String }
    }
}
