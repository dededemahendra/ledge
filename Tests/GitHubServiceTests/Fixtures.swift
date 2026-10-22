import Foundation
import Synchronization
@testable import GitHubService

/// A minute after the fixtures' last push.
let fixtureNow = date("2026-10-22T03:10:00Z")

func date(_ text: String) -> Date { try! Date(text, strategy: .iso8601) }

/// GitHub's answer to the round's query: two PRs of the user's (one failed,
/// one still running), one waiting for their review, two repos pushed to.
let mineReply = #"""
{"data":{
 "me":{"login":"dede","avatarUrl":"https://avatars.githubusercontent.com/u/1?v=4","repositories":{"nodes":[
   {"nameWithOwner":"dede/ledge","pushedAt":"2026-10-22T03:00:00Z"},
   {"nameWithOwner":"dede/old","pushedAt":"2026-10-01T00:00:00Z"}]}},
 "mine":{"issueCount":2,"nodes":[
   {"id":"PR_1","number":4,"title":"update notice","url":"https://github.com/dede/ledge/pull/4",
    "repository":{"name":"ledge"},"author":{"login":"dede"},
    "commits":{"nodes":[{"commit":{"oid":"aaa","statusCheckRollup":{"state":"FAILURE","contexts":{"nodes":[
       {"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-10-22T02:50:00Z","detailsUrl":"https://github.com/dede/ledge/runs/1"},
       {"__typename":"CheckRun","name":"test (macos)","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-10-22T02:51:00Z","detailsUrl":"https://github.com/dede/ledge/runs/2"}]}}}}]},
    "reviews":{"nodes":[{"id":"R_1","state":"APPROVED","submittedAt":"2026-10-22T03:05:00Z","url":"https://github.com/dede/ledge/pull/4#pullrequestreview-1","author":{"login":"coderabbitai","avatarUrl":"https://avatars.githubusercontent.com/in/347564?v=4"}}]},
    "comments":{"nodes":[
       {"id":"C_1","createdAt":"2026-10-22T03:06:00Z","url":"https://github.com/dede/ledge/pull/4#issuecomment-1","author":{"login":"coderabbitai","avatarUrl":"https://avatars.githubusercontent.com/in/347564?v=4"}},
       {"id":"C_2","createdAt":"2026-10-22T03:07:00Z","url":null,"author":null}]}},
   {"id":"PR_2","number":5,"title":"github island","url":"https://github.com/dede/ledge/pull/5",
    "repository":{"name":"ledge"},"author":{"login":"dede"},
    "commits":{"nodes":[{"commit":{"oid":"bbb","statusCheckRollup":{"state":"PENDING","contexts":{"nodes":[
       {"__typename":"CheckRun","name":"test (macos)","status":"IN_PROGRESS","conclusion":null,"startedAt":"2026-10-22T03:08:00Z","detailsUrl":"https://github.com/dede/ledge/runs/3"},
       {"__typename":"StatusContext","context":"CodeRabbit","state":"PENDING","createdAt":"2026-10-22T03:07:30Z","targetUrl":null}]}}}}]},
    "reviews":{"nodes":[]},"comments":{"nodes":[]}}]},
 "asked":{"issueCount":1,"nodes":[
   {"id":"PR_9","number":12,"title":"date picker","url":"https://github.com/acme/web/pull/12",
    "repository":{"name":"web"},"author":{"login":"gede","avatarUrl":"https://avatars.githubusercontent.com/u/2?v=4"},
    "commits":{"nodes":[{"commit":{"oid":"ccc","statusCheckRollup":null}}]},
    "reviews":{"nodes":[]},"comments":{"nodes":[]}}]}
}}
"""#

/// The user's runs in dede/ledge: one of theirs going, one that is a PR's
/// own check, one on a schedule.
let runsReply = #"""
{"total_count":3,"workflow_runs":[
 {"id":101,"name":"Release","status":"in_progress","conclusion":null,"html_url":"https://github.com/dede/ledge/actions/runs/101","head_sha":"ddd","created_at":"2026-10-22T03:09:00Z","run_started_at":"2026-10-22T03:09:05Z","event":"push","repository":{"name":"ledge"}},
 {"id":102,"name":"CI","status":"completed","conclusion":"failure","html_url":"https://github.com/dede/ledge/actions/runs/102","head_sha":"bbb","created_at":"2026-10-22T03:08:00Z","run_started_at":"2026-10-22T03:08:00Z","event":"pull_request","repository":{"name":"ledge"}},
 {"id":103,"name":"Nightly","status":"completed","conclusion":"success","html_url":"https://github.com/dede/ledge/actions/runs/103","head_sha":"eee","created_at":"2026-10-22T01:00:00Z","run_started_at":null,"event":"schedule","repository":{"name":"ledge"}}]}
"""#

/// What became of PR_0: merged by someone else.
let departuresReply = #"""
{"data":{"nodes":[{"id":"PR_0","state":"MERGED","mergedBy":{"login":"octocat","avatarUrl":"https://avatars.githubusercontent.com/u/583231?v=4"},"timelineItems":{"nodes":[]}}]}}
"""#

/// Every request a fake GitHub saw.
final class Seen: Sendable {
    private let requests = Mutex<[URLRequest]>([])
    func add(_ request: URLRequest) { requests.withLock { $0.append(request) } }
    var all: [URLRequest] { requests.withLock { $0 } }
}

/// A count that goes up by one each time it is read.
final class Counter: Sendable {
    private let value = Mutex(0)
    func next() -> Int { value.withLock { defer { $0 += 1 }; return $0 } }
}

typealias Answer = @Sendable (URLRequest) -> (Int, [String: String], String)

/// A fetch that answers from `answer`: status, headers, body.
func fetch(_ seen: Seen = Seen(), answer: @escaping Answer) -> GitHubClient.Fetch {
    { request in
        seen.add(request)
        let (status, headers, body) = answer(request)
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
}

/// GitHub as the fixtures tell it: the query, the departures lookup, the runs.
func github(graphQL: String = mineReply, runs: String = runsReply, departures: String = departuresReply) -> Answer {
    { request in
        if request.url!.path().hasSuffix("/actions/runs") { return (200, ["ETag": "\"r1\""], runs) }
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        return (200, [:], body.contains("nodes(ids") ? departures : graphQL)
    }
}
