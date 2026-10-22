# GitHub on the Island Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Once the user connects GitHub, the island tells them when checks on their PRs run, pass or fail, when someone reviews, comments, merges or closes one, when their review is requested, and when a run they started outside a PR finishes; the open island lists it all.

**Architecture:** A new `GitHubService` library holds the requests (`GitHubClient`, an actor with an injected fetch), the plain values (`GitHubSnapshot` and friends), the comparison (`GitHubEvents`), the look (`GitHubNotice`), the panel's rows, the schedule, the token, and the loop (`GitHubMonitor`). The island gains two activity kinds, a `badge` on records, a GitHub panel and a turning ring. SettingsKit gains six scenes; `AppSettings` seven keys; `AppModel` wires the monitor to the queue, the panel and the lock screen; Settings gains a GitHub pane.

**Tech Stack:** Swift 6.4, Swift 6 language mode, SwiftPM only, swift-testing, macOS 27, Foundation `URLSession`, Security (Keychain), SwiftUI.

**Spec:** `docs/superpowers/specs/2026-10-22-github-island-design.md`.

## Global Constraints

- Every request goes to `https://api.github.com` with the user's token: GraphQL `POST /graphql` (`Authorization: bearer <token>`), REST `GET /repos/{owner}/{repo}/actions/runs?actor={login}&per_page=10` (`Authorization: Bearer <token>`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, `If-None-Match` when an ETag is known). `User-Agent: Ledge/<version>`. Ephemeral session, 15 s timeout, 30 s in all.
- Not connected is the default (`githubConnected` false): no GitHub request at all until the user connects.
- Rounds: every 60 s, every 20 s while anything runs, at once on start, on wake and on Check now. Failures back off 60, 120, then 300 s. A rate limit waits until GitHub's reset (at least 60 s). A 401 stops until the user tries again.
- The first round after start is a quiet baseline. A result is announced once per PR head commit. The user's own reviews, comments, merges and closes are never announced; runs they start are.
- `ActivityKind.github`: priority 38, TTL 8 s. `ActivityKind.githubRun`: priority 18, sticky. Record ids `"github"` and `"github-run"`.
- Blip looks, burst order and captions exactly as the spec's table: failed, changes requested, review requested, approved, merged, passed, comment, closed; a burst's caption ends ` · +N more`. Running tint `yellow`.
- Lock screen: no GitHub blip, running item or panel while locked; what was missed shows as one blip after unlock.
- Panel: up to 4 rows (runs going, the user's PRs failed-first then running then the rest, then review requests); more than fits gives 3 rows and "N more on GitHub" opening `https://github.com/pulls`.
- A pasted token (Keychain, service `<bundle id>.github`, account `github.com`) wins over `gh auth token`; `gh` is looked for at `/opt/homebrew/bin/gh` and `/usr/local/bin/gh`.
- Run tests with `make test` / `make test FILTER=<name>`; never bare `swift test`. Only `brightnessTargetsTheBuiltInDisplay` and `bridgeLoadsAndReadsARealBrightnessValue` may fail. `make build` builds the app without launching it.
- `@State` cannot be used as a macro: spelled-out `State` as elsewhere (`private var _x: State<T>`).
- Text people read: Australian English, no em or en dashes, no exclamation marks, sentence case.
- Comments: plain sentences, dated `(2026-10-22)`. Commits: one lowercase sentence, blank line, `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; `git add` only the task's files (paths under `Sources/`, `Tests/`, `Package.swift`, `README.md`, `docs/`), never `.superpowers`; confirm with `git log -1`.
- Implementers do not launch, install or stop the app, and never call the real GitHub API.

## Review Focus

1. A title of 60 characters: the caption shortens it to 39 and an ellipsis instead of stretching across the menu bar (Task 2, `aLongTitleIsShortenedInTheCaption`).
2. A repo pushed to today brings its last ten runs, some days old: none is announced (Task 2, `oldRunsInANewlyPushedRepoStayQuiet`).
3. A comment by a deleted account (`"author": null`): read as `ghost`, no crash (Task 1, `aRoundReadsTheUsersPRsChecksReviewsAndRuns`).
4. A partial GraphQL answer (SSO errors beside data) and a repo whose runs answer 404: the round still succeeds (Task 1, `organisationsBehindSingleSignOnAreNoted`, `aRepoWithoutActionsDoesNotSinkTheRound`).
5. In one round, the user's own comment and a bot's: only the bot's is news (Task 2, `reviewsAndCommentsFromOthersAreNewsAndTheUsersOwnAreNot`).

## File structure

| File | Change |
| --- | --- |
| `Package.swift` | `GitHubService` target and tests; `Ledge` and `SettingsKit` depend on it |
| `Sources/GitHubService/GitHubModels.swift`, `GitHubQuery.swift`, `GitHubRuns.swift`, `GitHubClient.swift` | New (Task 1) |
| `Sources/GitHubService/GitHubEvents.swift`, `GitHubNotice.swift`, `GitHubPanelRows.swift`, `GitHubSample.swift` | New (Task 2) |
| `Sources/GitHubService/GitHubToken.swift`, `GitHubSchedule.swift`, `GitHubMonitor.swift` | New (Task 3) |
| `Sources/ActivityKit/ActivityKind.swift`, `ActivityRecord.swift` | Two kinds, `badge` (Task 4) |
| `Sources/NotchKit/GitHubPanel.swift`, `GitHubPanelView.swift` | New (Task 4) |
| `Sources/NotchKit/NotchController.swift`, `NotchPresenter.swift`, `NotchRootView.swift` | Ids, caption, panel, hover, swipe, ring (Task 4) |
| `Sources/LedgeSettings/AppSettings.swift` | Seven keys (Task 5) |
| `Sources/SettingsKit/PreviewScene.swift`, `PreviewContent.swift`, `PreviewStage.swift` | Six scenes (Task 5) |
| `Sources/Ledge/AppModel.swift` | Wiring, lock, probe (Task 6) |
| `Sources/Ledge/GitHubSettings.swift` | New pane (Task 7) |
| `Sources/Ledge/SettingsWindow.swift`, `SettingsPanes.swift` | Sidebar, badge, shared toggle (Task 7) |
| `Tests/GitHubServiceTests/Fixtures.swift`, `GitHubClientTests.swift`, `GitHubEventsTests.swift`, `GitHubMonitorTests.swift` | New |
| `Tests/ActivityKitTests/ActivityQueueTests.swift`, `Tests/NotchKitTests/NotchControllerTests.swift`, `Tests/LedgeSettingsTests/AppSettingsTests.swift`, `Tests/SettingsKitTests/PreviewStageTests.swift` | New expectations |
| `README.md`, `docs/superpowers/specs/2026-09-25-notch-companion-design.md`, `docs/manual-checks.md` | Docs (Task 7) |

---

### Task 1: The requests and what they return

**Files:** Modify `Package.swift`; create `Sources/GitHubService/GitHubModels.swift`, `GitHubQuery.swift`, `GitHubRuns.swift`, `GitHubClient.swift`, `Tests/GitHubServiceTests/Fixtures.swift`, `Tests/GitHubServiceTests/GitHubClientTests.swift`.

**Interfaces — Produces:**
- `public enum CheckState: String { pending, passed, failed }`
- `public struct GitHubChecks` (`state`, `startedAt: Date?`, `failedName: String?`, `failedURL: URL?`; `init(state:startedAt:failedName:failedURL:)` with nil defaults)
- `public enum ReviewState { approved, changesRequested, commented, other }`
- `public struct GitHubReview` (`id`, `author`, `state`, `at: Date?`, `url: URL?`), `public struct GitHubComment` (`id`, `author`, `at: Date?`, `url: URL?`), both with public memberwise-style inits
- `public struct GitHubPR: Identifiable` (`id`, `number`, `title`, `url`, `repo`, `author: String?`, `headSHA: String?`, `checks: GitHubChecks?`, `reviews`, `comments`; init with defaults `author: nil, headSHA: nil, checks: nil, reviews: [], comments: []`)
- `public enum RunStatus { running, passed, failed, quiet }`; `public struct GitHubRun: Identifiable` (`id: Int`, `workflow`, `repo`, `url`, `headSHA`, `status`, `createdAt: Date`, `startedAt: Date?`)
- `public struct GitHubDeparture` (`pr`, `merged: Bool`, `by: String?`)
- `public struct GitHubSnapshot` (`login`, `takenAt`, `mine`, `mineTotal`, `requested`, `requestedTotal`, `runs`, `departed`, `hidesSomeOrganisations`; `init(login:takenAt:mine:mineTotal:requested:requestedTotal:runs:departed:hidesSomeOrganisations:)` with defaults `[]`, `nil` totals meaning the array's count, `false`)
- `public actor GitHubClient` (`typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)`; `enum Failure: Error, Equatable { unauthorised, rateLimited(until: Date), unavailable }`; `static let session: Fetch`; `init(token: String, userAgent: String, fetch: @escaping Fetch = GitHubClient.session)`; `func round(previous: GitHubSnapshot?, now: Date) async -> Result<GitHubSnapshot, Failure>`)

- [ ] **Step 1: Targets.** In `Package.swift`:
  - add `"GitHubService"` to the `Ledge` executable target's dependency list (after `"UpdateService"`) and to `SettingsKit`'s (after `"UpdateService"`);
  - after `.target(name: "UpdateService"),` add `.target(name: "GitHubService"),`;
  - after `.testTarget(name: "UpdateServiceTests", dependencies: ["UpdateService"]),` add `.testTarget(name: "GitHubServiceTests", dependencies: ["GitHubService"]),`.

- [ ] **Step 2: Fixtures.** Create `Tests/GitHubServiceTests/Fixtures.swift`:

```swift
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
 "me":{"login":"dede","repositories":{"nodes":[
   {"nameWithOwner":"dede/ledge","pushedAt":"2026-10-22T03:00:00Z"},
   {"nameWithOwner":"dede/old","pushedAt":"2026-10-01T00:00:00Z"}]}},
 "mine":{"issueCount":2,"nodes":[
   {"id":"PR_1","number":4,"title":"update notice","url":"https://github.com/dede/ledge/pull/4",
    "repository":{"name":"ledge"},"author":{"login":"dede"},
    "commits":{"nodes":[{"commit":{"oid":"aaa","statusCheckRollup":{"state":"FAILURE","contexts":{"nodes":[
       {"__typename":"CheckRun","name":"build","status":"COMPLETED","conclusion":"SUCCESS","startedAt":"2026-10-22T02:50:00Z","detailsUrl":"https://github.com/dede/ledge/runs/1"},
       {"__typename":"CheckRun","name":"test (macos)","status":"COMPLETED","conclusion":"FAILURE","startedAt":"2026-10-22T02:51:00Z","detailsUrl":"https://github.com/dede/ledge/runs/2"}]}}}}]},
    "reviews":{"nodes":[{"id":"R_1","state":"APPROVED","submittedAt":"2026-10-22T03:05:00Z","url":"https://github.com/dede/ledge/pull/4#pullrequestreview-1","author":{"login":"coderabbitai"}}]},
    "comments":{"nodes":[
       {"id":"C_1","createdAt":"2026-10-22T03:06:00Z","url":"https://github.com/dede/ledge/pull/4#issuecomment-1","author":{"login":"coderabbitai"}},
       {"id":"C_2","createdAt":"2026-10-22T03:07:00Z","url":null,"author":null}]}},
   {"id":"PR_2","number":5,"title":"github island","url":"https://github.com/dede/ledge/pull/5",
    "repository":{"name":"ledge"},"author":{"login":"dede"},
    "commits":{"nodes":[{"commit":{"oid":"bbb","statusCheckRollup":{"state":"PENDING","contexts":{"nodes":[
       {"__typename":"CheckRun","name":"test (macos)","status":"IN_PROGRESS","conclusion":null,"startedAt":"2026-10-22T03:08:00Z","detailsUrl":"https://github.com/dede/ledge/runs/3"},
       {"__typename":"StatusContext","context":"CodeRabbit","state":"PENDING","createdAt":"2026-10-22T03:07:30Z","targetUrl":null}]}}}}]},
    "reviews":{"nodes":[]},"comments":{"nodes":[]}}]},
 "asked":{"issueCount":1,"nodes":[
   {"id":"PR_9","number":12,"title":"date picker","url":"https://github.com/acme/web/pull/12",
    "repository":{"name":"web"},"author":{"login":"gede"},
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
{"data":{"nodes":[{"id":"PR_0","state":"MERGED","mergedBy":{"login":"octocat"},"timelineItems":{"nodes":[]}}]}}
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
```

- [ ] **Step 3: Failing tests.** Create `Tests/GitHubServiceTests/GitHubClientTests.swift`:

```swift
import Testing
import Foundation
@testable import GitHubService

/// Review Focus 3: a deleted account's comment reads as "ghost".
@Test func aRoundReadsTheUsersPRsChecksReviewsAndRuns() async throws {
    let client = GitHubClient(token: "t0k", userAgent: "Ledge/0.1.2", fetch: fetch(answer: github()))
    let snapshot = try await client.round(previous: nil, now: fixtureNow).get()
    #expect(snapshot.login == "dede")
    #expect(snapshot.takenAt == fixtureNow)
    #expect(snapshot.mine.map(\.number) == [4, 5])
    #expect(snapshot.mineTotal == 2)
    let failed = snapshot.mine[0]
    #expect(failed.repo == "ledge" && failed.headSHA == "aaa")
    #expect(failed.checks?.state == .failed)
    #expect(failed.checks?.failedName == "test (macos)")
    #expect(failed.checks?.failedURL?.absoluteString == "https://github.com/dede/ledge/runs/2")
    #expect(failed.reviews == [GitHubReview(id: "R_1", author: "coderabbitai", state: .approved, at: date("2026-10-22T03:05:00Z"),
                                            url: URL(string: "https://github.com/dede/ledge/pull/4#pullrequestreview-1"))])
    #expect(failed.comments.map(\.author) == ["coderabbitai", "ghost"])
    let running = snapshot.mine[1]
    #expect(running.checks?.state == .pending)
    #expect(running.checks?.startedAt == date("2026-10-22T03:07:30Z"), "the earliest of what is still going")
    #expect(snapshot.requested.map(\.number) == [12])
    #expect(snapshot.requested.first?.author == "gede")
    #expect(snapshot.requested.first?.checks == nil)
    #expect(snapshot.runs.map(\.id) == [101], "a PR's own run and a scheduled run are not the user's own")
    #expect(snapshot.runs.first?.status == .running)
    #expect(snapshot.runs.first?.startedAt == date("2026-10-22T03:09:05Z"))
    #expect(!snapshot.hidesSomeOrganisations)
}

@Test func everyRequestGoesToGitHubWithTheToken() async throws {
    let seen = Seen()
    let client = GitHubClient(token: "t0k", userAgent: "Ledge/0.1.2", fetch: fetch(seen, answer: github()))
    _ = await client.round(previous: nil, now: fixtureNow)
    let requests = seen.all
    #expect(requests.count == 2, "the query, then the runs of the one repo pushed to today")
    for request in requests {
        #expect(request.url?.host() == "api.github.com")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasSuffix(" t0k") == true)
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "Ledge/0.1.2")
    }
    #expect(requests[0].httpMethod == "POST")
    #expect(requests[0].url?.path() == "/graphql")
    #expect(String(decoding: requests[0].httpBody ?? Data(), as: UTF8.self).contains("author:@me"))
    #expect(requests[1].url?.path() == "/repos/dede/ledge/actions/runs")
    #expect(requests[1].url?.query()?.contains("actor=dede") == true)
    #expect(requests[1].value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
}

@Test func failuresAreToldApart() async {
    func failure(_ status: Int, _ headers: [String: String] = [:]) async -> GitHubClient.Failure? {
        let client = GitHubClient(token: "t", userAgent: "Ledge", fetch: fetch { _ in (status, headers, "{}") })
        if case .failure(let failure) = await client.round(previous: nil, now: fixtureNow) { return failure }
        return nil
    }
    #expect(await failure(401) == .unauthorised)
    #expect(await failure(403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1792641600"])
            == .rateLimited(until: Date(timeIntervalSince1970: 1792641600)))
    #expect(await failure(429, ["Retry-After": "30"]) == .rateLimited(until: fixtureNow.addingTimeInterval(30)))
    #expect(await failure(500) == .unavailable)
    #expect(await failure(200) == .unavailable, "an answer with no data is no answer")
    let offline = GitHubClient(token: "t", userAgent: "Ledge", fetch: { _ in throw URLError(.notConnectedToInternet) })
    guard case .failure(let failure) = await offline.round(previous: nil, now: fixtureNow) else {
        Issue.record("offline is a failure")
        return
    }
    #expect(failure == .unavailable)
}

@Test func anUnchangedRunsAnswerIsReused() async throws {
    let seen = Seen()
    let client = GitHubClient(token: "t", userAgent: "Ledge", fetch: fetch(seen) { request in
        if request.url!.path().hasSuffix("/actions/runs") {
            return request.value(forHTTPHeaderField: "If-None-Match") == "\"r1\""
                ? (304, [:], "") : (200, ["ETag": "\"r1\""], runsReply)
        }
        return (200, [:], mineReply)
    })
    let first = try await client.round(previous: nil, now: fixtureNow).get()
    let second = try await client.round(previous: first, now: fixtureNow.addingTimeInterval(60)).get()
    #expect(second.runs == first.runs && !second.runs.isEmpty)
    #expect(seen.all.last?.value(forHTTPHeaderField: "If-None-Match") == "\"r1\"")
}

/// Review Focus 4.
@Test func aRepoWithoutActionsDoesNotSinkTheRound() async throws {
    let client = GitHubClient(token: "t", userAgent: "Ledge", fetch: fetch { request in
        request.url!.path().hasSuffix("/actions/runs") ? (404, [:], #"{"message":"Not Found"}"#) : (200, [:], mineReply)
    })
    let snapshot = try await client.round(previous: nil, now: fixtureNow).get()
    #expect(snapshot.runs.isEmpty && snapshot.mine.count == 2)
}

@Test func aPRThatLeftTheListIsLookedUp() async throws {
    let client = GitHubClient(token: "t", userAgent: "Ledge", fetch: fetch(answer: github()))
    let gone = GitHubPR(id: "PR_0", number: 3, title: "old work", url: URL(string: "https://github.com/dede/ledge/pull/3")!, repo: "ledge")
    let previous = GitHubSnapshot(login: "dede", takenAt: fixtureNow.addingTimeInterval(-60), mine: [gone])
    let snapshot = try await client.round(previous: previous, now: fixtureNow).get()
    #expect(snapshot.departed == [GitHubDeparture(pr: gone, merged: true, by: "octocat")])
}

/// Review Focus 4.
@Test func organisationsBehindSingleSignOnAreNoted() async throws {
    let partial = mineReply.replacingOccurrences(
        of: #"{"data":{"#,
        with: #"{"errors":[{"type":"FORBIDDEN","message":"Resource protected by organization SAML enforcement."}],"data":{"#
    )
    let client = GitHubClient(token: "t", userAgent: "Ledge", fetch: fetch(answer: github(graphQL: partial)))
    let snapshot = try await client.round(previous: nil, now: fixtureNow).get()
    #expect(snapshot.hidesSomeOrganisations)
    #expect(snapshot.mine.count == 2, "what GitHub did send is used")
}
```

- [ ] **Step 4: Run them to see them fail.** `make test FILTER=GitHubServiceTests` → does not build: `GitHubClient` unknown.

- [ ] **Step 5: The values.** Create `Sources/GitHubService/GitHubModels.swift`:

```swift
import Foundation

/// A check rollup's verdict on a PR's latest commit (2026-10-22): GitHub's
/// `SUCCESS` is passed, `FAILURE` and `ERROR` are failed, the rest pending.
public enum CheckState: String, Sendable, Equatable {
    case pending, passed, failed
}

/// The checks on a PR's latest commit: Actions and outside statuses alike.
public struct GitHubChecks: Sendable, Equatable {
    public let state: CheckState
    /// When the earliest check still going started, if GitHub says.
    public let startedAt: Date?
    /// The first failing check, by name, and where it is.
    public let failedName: String?
    public let failedURL: URL?

    public init(state: CheckState, startedAt: Date? = nil, failedName: String? = nil, failedURL: URL? = nil) {
        self.state = state
        self.startedAt = startedAt
        self.failedName = failedName
        self.failedURL = failedURL
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

    public init(id: String, author: String, state: ReviewState, at: Date?, url: URL?) {
        self.id = id
        self.author = author
        self.state = state
        self.at = at
        self.url = url
    }
}

public struct GitHubComment: Sendable, Equatable {
    public let id: String
    public let author: String
    public let at: Date?
    public let url: URL?

    public init(id: String, author: String, at: Date?, url: URL?) {
        self.id = id
        self.author = author
        self.at = at
        self.url = url
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
    public let headSHA: String?
    public let checks: GitHubChecks?
    /// The last ten, oldest first.
    public let reviews: [GitHubReview]
    public let comments: [GitHubComment]

    public init(id: String, number: Int, title: String, url: URL, repo: String, author: String? = nil,
                headSHA: String? = nil, checks: GitHubChecks? = nil,
                reviews: [GitHubReview] = [], comments: [GitHubComment] = []) {
        self.id = id
        self.number = number
        self.title = title
        self.url = url
        self.repo = repo
        self.author = author
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

    public init(pr: GitHubPR, merged: Bool, by: String?) {
        self.pr = pr
        self.merged = merged
        self.by = by
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

    public init(login: String, takenAt: Date, mine: [GitHubPR] = [], mineTotal: Int? = nil,
                requested: [GitHubPR] = [], requestedTotal: Int? = nil, runs: [GitHubRun] = [],
                departed: [GitHubDeparture] = [], hidesSomeOrganisations: Bool = false) {
        self.login = login
        self.takenAt = takenAt
        self.mine = mine
        self.mineTotal = mineTotal ?? mine.count
        self.requested = requested
        self.requestedTotal = requestedTotal ?? requested.count
        self.runs = runs
        self.departed = departed
        self.hidesSomeOrganisations = hidesSomeOrganisations
    }
}
```

- [ ] **Step 6: The query.** Create `Sources/GitHubService/GitHubQuery.swift`:

```swift
import Foundation

/// The GraphQL a round asks (2026-10-22), and how its answer is read. One
/// query covers the user, their open PRs with checks, reviews and comments,
/// the PRs waiting for their review, and the repos they pushed to last.
enum GitHubQuery {
    static let text = """
    query {
      me: viewer {
        login
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
    fragment pr on PullRequest {
      id number title url
      repository { name }
      author { login }
      commits(last: 1) { nodes { commit { oid statusCheckRollup { state contexts(first: 30) { nodes {
        __typename
        ... on CheckRun { name status conclusion startedAt detailsUrl }
        ... on StatusContext { context state createdAt targetUrl }
      } } } } } }
      reviews(last: 10) { nodes { id state submittedAt url author { login } } }
      comments(last: 10) { nodes { id createdAt url author { login } } }
    }
    """

    /// What became of PRs that left the list: merged or closed, and by whom.
    static let departuresText = """
    query($ids: [ID!]!) {
      nodes(ids: $ids) {
        ... on PullRequest {
          id state
          mergedBy { login }
          timelineItems(itemTypes: [CLOSED_EVENT], last: 1) { nodes { ... on ClosedEvent { actor { login } } } }
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
    }

    struct Outcome: Sendable, Equatable {
        let merged: Bool
        let by: String?
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
            hidesSomeOrganisations: hides
        )
    }

    /// By PR node ID; a PR that is still open is left out.
    static func decodeDepartures(_ data: Data) -> [String: Outcome] {
        guard let wire = try? JSONDecoder().decode(DeparturesWire.self, from: data) else { return [:] }
        var outcomes: [String: Outcome] = [:]
        for node in (wire.data?.nodes ?? []).compactMap({ $0 }) {
            guard let id = node.id else { continue }
            switch node.state ?? "" {
            case "MERGED": outcomes[id] = Outcome(merged: true, by: node.mergedBy?.login)
            case "CLOSED": outcomes[id] = Outcome(merged: false, by: node.timelineItems?.nodes?.compactMap { $0 }.last?.actor?.login)
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
                ? ["FAILURE", "TIMED_OUT", "STARTUP_FAILURE"].contains(context.conclusion ?? "")
                : ["FAILURE", "ERROR"].contains(context.state ?? "")
        }
        return GitHubChecks(
            state: state,
            startedAt: going.min(),
            failedName: failing.flatMap { $0.name ?? $0.context },
            failedURL: failing.flatMap { ($0.detailsUrl ?? $0.targetUrl).flatMap(URL.init(string:)) }
        )
    }

    /// GitHub's JSON, every field optional: a missing one drops the item,
    /// not the round.
    struct Wire: Decodable {
        let data: Body?
        let errors: [Problem]?

        struct Problem: Decodable { let type: String?; let message: String? }
        struct Body: Decodable { let me: Me?; let mine: Search?; let asked: Search? }
        struct Me: Decodable { let login: String; let repositories: Nodes<Repo>? }
        struct Repo: Decodable { let nameWithOwner: String; let pushedAt: String? }
        struct Search: Decodable { let issueCount: Int?; let nodes: [PR?]? }
        struct Nodes<T: Decodable>: Decodable { let nodes: [T?]? }
        struct Login: Decodable { let login: String? }
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
                                            at: GitHubQuery.date(review.submittedAt), url: review.url.flatMap(URL.init(string:)))
                    },
                    comments: (comments?.nodes ?? []).compactMap { comment in
                        guard let comment, let id = comment.id else { return nil }
                        return GitHubComment(id: id, author: comment.author?.login ?? "ghost",
                                             at: GitHubQuery.date(comment.createdAt), url: comment.url.flatMap(URL.init(string:)))
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
```

- [ ] **Step 7: The runs.** Create `Sources/GitHubService/GitHubRuns.swift`:

```swift
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
```

- [ ] **Step 8: The client.** Create `Sources/GitHubService/GitHubClient.swift`:

```swift
import Foundation

/// The requests (2026-10-22). Everything goes to api.github.com with the
/// user's token; nothing else leaves the Mac. `fetch` is injected so the
/// tests can answer it.
public actor GitHubClient {
    public typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public enum Failure: Error, Sendable, Equatable {
        /// 401: the token is gone or revoked.
        case unauthorised
        case rateLimited(until: Date)
        /// Offline, a server error, an unreadable answer.
        case unavailable
    }

    public static let api = URL(string: "https://api.github.com")!

    private static let ephemeral: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // A reply that trickles in gives up after 30 seconds (2026-10-22).
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }()
    public static let session: Fetch = { request in try await ephemeral.data(for: request) }

    private let token: String
    private let userAgent: String
    private let fetch: Fetch
    /// The last runs answer per URL with its ETag: a 304 reuses it, and
    /// costs nothing against the rate limit.
    private var cachedRuns: [URL: (etag: String, runs: [GitHubRun])] = [:]

    public init(token: String, userAgent: String, fetch: @escaping Fetch = GitHubClient.session) {
        self.token = token
        self.userAgent = userAgent
        self.fetch = fetch
    }

    /// One round: the query; the user's runs in repos pushed to in the last
    /// day (five at most); what became of PRs that left the list since
    /// `previous`.
    public func round(previous: GitHubSnapshot?, now: Date) async -> Result<GitHubSnapshot, Failure> {
        let answer: GitHubQuery.Answer
        switch await post(GitHubQuery.text, ids: nil, now: now) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let data):
            guard let decoded = GitHubQuery.decode(data) else { return .failure(.unavailable) }
            answer = decoded
        }

        var runs: [GitHubRun] = []
        for repo in answer.pushed.filter({ now.timeIntervalSince($0.at) < 24 * 60 * 60 }).prefix(5) {
            switch await runs(of: repo.fullName, actor: answer.login, now: now) {
            case .success(let found): runs += found
            case .failure(let failure): return .failure(failure)
            }
        }

        var departed: [GitHubDeparture] = []
        if let previous {
            let open = Set(answer.mine.map(\.id))
            let gone = previous.mine.filter { !open.contains($0.id) }
            // A failed lookup only loses the merged or closed blip.
            if !gone.isEmpty, case .success(let data) = await post(GitHubQuery.departuresText, ids: gone.map(\.id), now: now) {
                let outcomes = GitHubQuery.decodeDepartures(data)
                departed = gone.compactMap { pr in
                    outcomes[pr.id].map { GitHubDeparture(pr: pr, merged: $0.merged, by: $0.by) }
                }
            }
        }

        return .success(GitHubSnapshot(
            login: answer.login, takenAt: now, mine: answer.mine, mineTotal: answer.mineTotal,
            requested: answer.requested, requestedTotal: answer.requestedTotal, runs: runs,
            departed: departed, hidesSomeOrganisations: answer.hidesSomeOrganisations
        ))
    }

    private func post(_ query: String, ids: [String]?, now: Date) async -> Result<Data, Failure> {
        var request = URLRequest(url: Self.api.appending(path: "graphql"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["query": query]
        if let ids { body["variables"] = ["ids": ids] }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await fetch(request), let http = response as? HTTPURLResponse else {
            return .failure(.unavailable)
        }
        if let failure = Self.failure(for: http, now: now) { return .failure(failure) }
        return .success(data)
    }

    /// A repo without Actions, or one the token cannot see, answers 404:
    /// that repo just has no runs this round. Only a 401 or a rate limit
    /// stops the round.
    private func runs(of fullName: String, actor login: String, now: Date) async -> Result<[GitHubRun], Failure> {
        var components = URLComponents(url: Self.api.appending(path: "repos/\(fullName)/actions/runs"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "actor", value: login), URLQueryItem(name: "per_page", value: "10")]
        let url = components.url!
        let cached = cachedRuns[url]?.runs ?? []
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let etag = cachedRuns[url]?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        guard let (data, response) = try? await fetch(request), let http = response as? HTTPURLResponse else {
            return .success(cached)
        }
        if http.statusCode == 304 { return .success(cached) }
        if let failure = Self.failure(for: http, now: now) {
            return failure == .unavailable ? .success(cached) : .failure(failure)
        }
        guard let runs = GitHubRuns.decode(data) else { return .success(cached) }
        if let etag = http.value(forHTTPHeaderField: "ETag") { cachedRuns[url] = (etag, runs) }
        return .success(runs)
    }

    /// What a status says: nothing wrong (200, 304), a refused login, a
    /// rate limit with its end, or GitHub being unavailable.
    static func failure(for response: HTTPURLResponse, now: Date) -> Failure? {
        switch response.statusCode {
        case 200, 304:
            return nil
        case 401:
            return .unauthorised
        case 403, 429:
            if let wait = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init) {
                return .rateLimited(until: now.addingTimeInterval(wait))
            }
            if response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0",
               let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(TimeInterval.init) {
                return .rateLimited(until: Date(timeIntervalSince1970: reset))
            }
            return response.statusCode == 429 ? .rateLimited(until: now.addingTimeInterval(60)) : .unavailable
        default:
            return .unavailable
        }
    }
}
```

- [ ] **Step 9: Run the tests.** `make test FILTER=GitHubServiceTests` → all seven pass. Then `make build` → builds.

- [ ] **Step 10: Commit.**

```bash
git add Package.swift Sources/GitHubService Tests/GitHubServiceTests
git commit -m "ask github in one round for the user's open prs with their checks, reviews and comments, the prs waiting for their review, and their own runs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log -1 --stat
```

---

### Task 2: What happened, how it looks, and the panel's list

**Files:** Create `Sources/GitHubService/GitHubEvents.swift`, `GitHubNotice.swift`, `GitHubPanelRows.swift`, `GitHubSample.swift`, `Tests/GitHubServiceTests/GitHubEventsTests.swift`.

**Interfaces — Consumes:** Task 1's values.
**Produces:**
- `public enum GitHubEvent: Equatable { checksPassed(GitHubPR), checksFailed(GitHubPR), reviewed(GitHubPR, GitHubReview), commented(GitHubPR, GitHubComment), merged(GitHubPR), closed(GitHubPR), reviewRequested(GitHubPR), runPassed(GitHubRun), runFailed(GitHubRun) }`
- `public struct GitHubRunning` (`enum Source { checks, run }`; `key`, `source`, `caption`, `url`, `startedAt: Date?`; public init)
- `public enum GitHubEvents { static func between(_ old: GitHubSnapshot?, _ new: GitHubSnapshot) -> [GitHubEvent]; static func running(in: GitHubSnapshot) -> [GitHubRunning] }`
- `public struct RunningClock { struct Lead { item, since: Date, count: Int }; init(); mutating func lead(of: [GitHubRunning], now: Date) -> Lead? }`
- `public struct GitHubBlip` (`title`, `symbolName`, `word`, `tintName: String?`, `caption`, `url`)
- `public enum GitHubNotice { static let runningTintName = "yellow"; static func blip(for: GitHubEvent) -> GitHubBlip; static func rank(_:) -> Int; static func burst(_: [GitHubEvent]) -> GitHubBlip? }`
- `public struct GitHubRow: Identifiable` (`enum Mark { running, passed, failed, none, review }`; `id`, `mark`, `title`, `repo`, `url`), `public struct GitHubPanelList { rows, more }`, `public enum GitHubPanelRows { static let limit = 4; static let moreURL; static func make(_: GitHubSnapshot) -> GitHubPanelList }`
- `public enum GitHubSample { static let reviewer = "sam"; static let pr: GitHubPR; static let request: GitHubPR; static let run: GitHubRun; static func story(login: String, start: Date) -> [GitHubSnapshot] }`

- [ ] **Step 1: Failing tests.** Create `Tests/GitHubServiceTests/GitHubEventsTests.swift`:

```swift
import Testing
import Foundation
@testable import GitHubService

private let t0 = date("2026-10-22T03:00:00Z")
private let link = URL(string: "https://github.com/dede/ledge")!

private func pr(_ id: String = "PR_1", number: Int = 4, sha: String = "aaa", checks: CheckState? = nil, failed: String? = nil,
                reviews: [GitHubReview] = [], comments: [GitHubComment] = []) -> GitHubPR {
    GitHubPR(id: id, number: number, title: "update notice", url: URL(string: "https://github.com/dede/ledge/pull/\(number)")!,
             repo: "ledge", author: "dede", headSHA: sha, checks: checks.map { GitHubChecks(state: $0, failedName: failed) },
             reviews: reviews, comments: comments)
}

/// A snapshot `minutes` after t0.
private func snap(_ minutes: Double, mine: [GitHubPR] = [], requested: [GitHubPR] = [], runs: [GitHubRun] = [],
                  departed: [GitHubDeparture] = []) -> GitHubSnapshot {
    GitHubSnapshot(login: "dede", takenAt: t0.addingTimeInterval(minutes * 60), mine: mine, requested: requested,
                   runs: runs, departed: departed)
}

private func run(_ id: Int, _ status: RunStatus, sha: String = "zzz", created minutes: Double = 0.5) -> GitHubRun {
    GitHubRun(id: id, workflow: "Deploy", repo: "web", url: URL(string: "https://github.com/dede/web/actions/runs/\(id)")!,
              headSHA: sha, status: status, createdAt: t0.addingTimeInterval(minutes * 60), startedAt: nil)
}

private func review(_ id: String, _ who: String, _ state: ReviewState) -> GitHubReview {
    GitHubReview(id: id, author: who, state: state, at: t0.addingTimeInterval(30), url: nil)
}

private func comment(_ id: String, _ who: String) -> GitHubComment {
    GitHubComment(id: id, author: who, at: t0.addingTimeInterval(30), url: nil)
}

@Test func theFirstRoundIsQuiet() {
    #expect(GitHubEvents.between(nil, snap(0, mine: [pr(checks: .failed)], requested: [pr("PR_9")], runs: [run(1, .failed)])).isEmpty)
}

@Test func checksAreNewsOncePerCommit() {
    let running = snap(0, mine: [pr(checks: .pending)])
    let failed = snap(1, mine: [pr(checks: .failed, failed: "test (macos)")])
    #expect(GitHubEvents.between(running, failed) == [.checksFailed(failed.mine[0])])
    #expect(GitHubEvents.between(failed, snap(2, mine: failed.mine)).isEmpty, "the same result is not news")
    let pushed = snap(3, mine: [pr(sha: "bbb", checks: .pending)])
    #expect(GitHubEvents.between(failed, pushed).isEmpty, "a new commit starts over, quietly")
    let passed = snap(4, mine: [pr(sha: "bbb", checks: .passed)])
    #expect(GitHubEvents.between(pushed, passed) == [.checksPassed(passed.mine[0])])
}

/// Review Focus 5.
@Test func reviewsAndCommentsFromOthersAreNewsAndTheUsersOwnAreNot() {
    let before = snap(0, mine: [pr()])
    let after = snap(1, mine: [pr(reviews: [review("R1", "coderabbitai", .approved), review("R2", "dede", .commented)],
                                 comments: [comment("C1", "dede"), comment("C2", "sam")])])
    let mine = after.mine[0]
    #expect(GitHubEvents.between(before, after) == [.reviewed(mine, mine.reviews[0]), .commented(mine, mine.comments[1])])
    #expect(GitHubEvents.between(after, snap(2, mine: after.mine)).isEmpty, "seen once, said once")
}

@Test func mergesAndClosesBySomeoneElseAreNews() {
    let open = snap(0, mine: [pr("PR_1"), pr("PR_2", number: 5), pr("PR_3", number: 6)])
    let after = snap(1, departed: [GitHubDeparture(pr: open.mine[0], merged: true, by: "sam"),
                                   GitHubDeparture(pr: open.mine[1], merged: false, by: "sam"),
                                   GitHubDeparture(pr: open.mine[2], merged: true, by: "dede")])
    #expect(GitHubEvents.between(open, after) == [.merged(open.mine[0]), .closed(open.mine[1])])
}

@Test func aReviewRequestIsNewsOnce() {
    let asked = pr("PR_9", number: 12)
    #expect(GitHubEvents.between(snap(0), snap(1, requested: [asked])) == [.reviewRequested(asked)])
    #expect(GitHubEvents.between(snap(1, requested: [asked]), snap(2, requested: [asked])).isEmpty)
}

@Test func theUsersRunsOutsidePRsAreNews() {
    let going = snap(0, mine: [pr(sha: "aaa", checks: .pending)], runs: [run(1, .running), run(2, .running, sha: "aaa")])
    let done = snap(1, mine: [pr(sha: "aaa", checks: .pending)], runs: [run(1, .passed), run(2, .failed, sha: "aaa")])
    #expect(GitHubEvents.between(going, done) == [.runPassed(done.runs[0])], "a run on a PR's head is that PR's checks")
    #expect(GitHubEvents.between(snap(0), snap(1, runs: [run(3, .failed)])) == [.runFailed(run(3, .failed))],
            "a short run seen only once it has ended")
    #expect(GitHubEvents.between(snap(0), snap(1, runs: [run(4, .quiet)])).isEmpty, "a cancelled run ends quietly")
}

/// Review Focus 2.
@Test func oldRunsInANewlyPushedRepoStayQuiet() {
    #expect(GitHubEvents.between(snap(0), snap(1, runs: [run(5, .passed, created: -600)])).isEmpty)
}

@Test func whatIsRunningNow() {
    let s = snap(0, mine: [pr(sha: "aaa", checks: .pending), pr("PR_2", number: 5, checks: .passed)],
                 runs: [run(1, .running), run(2, .running, sha: "aaa"), run(3, .passed)])
    let items = GitHubEvents.running(in: s)
    #expect(items.map(\.key) == ["pr:PR_1:aaa", "run:1"])
    #expect(items.map(\.source) == [.checks, .run])
    #expect(items.map(\.caption) == ["#4 update notice · ledge", "Deploy · web"])
}

@Test func theRunningClockKeepsEachStartAndCounts() {
    var clock = RunningClock()
    let a = GitHubRunning(key: "a", source: .checks, caption: "A", url: link, startedAt: nil)
    let b = GitHubRunning(key: "b", source: .run, caption: "B", url: link, startedAt: t0)
    let first = clock.lead(of: [a], now: t0.addingTimeInterval(60))
    #expect(first == RunningClock.Lead(item: a, since: t0.addingTimeInterval(60), count: 1))
    let both = clock.lead(of: [a, b], now: t0.addingTimeInterval(120))
    #expect(both?.item == b && both?.count == 2, "the one that started first leads")
    #expect(clock.lead(of: [a], now: t0.addingTimeInterval(180))?.since == t0.addingTimeInterval(60), "a's start is kept")
    #expect(clock.lead(of: [], now: t0) == nil)
}

@Test func eachEventHasItsLook() {
    let p = pr(checks: .failed, failed: "test (macos)")
    #expect(GitHubNotice.blip(for: .checksFailed(p)) == GitHubBlip(
        title: "Checks failed", symbolName: "xmark.circle.fill", word: "Failed", tintName: "red",
        caption: "#4 update notice · test (macos)", url: p.url))
    #expect(GitHubNotice.blip(for: .checksPassed(p)).caption == "#4 update notice · ledge")
    #expect(GitHubNotice.blip(for: .checksPassed(p)).tintName == "green")
    let approved = GitHubNotice.blip(for: .reviewed(p, review("R1", "coderabbitai", .approved)))
    #expect(approved.caption == "coderabbitai · #4 ledge" && approved.word == "Approved" && approved.symbolName == "checkmark.seal.fill")
    let changes = GitHubNotice.blip(for: .reviewed(p, review("R2", "sam", .changesRequested)))
    #expect(changes.word == "Changes" && changes.tintName == "orange" && changes.symbolName == "exclamationmark.bubble.fill")
    let said = GitHubNotice.blip(for: .commented(p, comment("C1", "sam")))
    #expect(said.word == "Comment" && said.tintName == nil && said.symbolName == "bubble.left.fill")
    #expect(GitHubNotice.blip(for: .merged(p)).symbolName == "arrow.triangle.merge")
    #expect(GitHubNotice.blip(for: .merged(p)).tintName == "purple")
    #expect(GitHubNotice.blip(for: .closed(p)).tintName == "gray")
    let asked = GitHubNotice.blip(for: .reviewRequested(pr("PR_9", number: 12)))
    #expect(asked.caption == "dede asks for your review · #12 ledge" && asked.word == "Review" && asked.tintName == "blue")
    #expect(GitHubNotice.blip(for: .runFailed(run(1, .failed))).caption == "Deploy · web")
    #expect(GitHubNotice.blip(for: .runPassed(run(1, .passed))).word == "Passed")
}

@Test func aBurstIsOneBlip() {
    let p = pr(checks: .passed)
    let events: [GitHubEvent] = [.commented(p, comment("C1", "sam")), .checksPassed(p), .reviewed(p, review("R1", "sam", .changesRequested))]
    let blip = GitHubNotice.burst(events)
    #expect(blip?.word == "Changes")
    #expect(blip?.caption == "sam · #4 ledge · +2 more")
    #expect(GitHubNotice.burst([]) == nil)
    #expect(GitHubNotice.burst([.checksPassed(p)])?.caption == "#4 update notice · ledge")
}

/// Review Focus 1.
@Test func aLongTitleIsShortenedInTheCaption() {
    let long = GitHubPR(id: "x", number: 9, title: String(repeating: "a", count: 60), url: link, repo: "ledge")
    #expect(GitHubNotice.blip(for: .merged(long)).caption == "#9 " + String(repeating: "a", count: 39) + "… · ledge")
}

@Test func thePanelListsRunsThenPRsThenRequests() {
    let s = snap(0, mine: [pr("PR_1", number: 4, checks: .passed), pr("PR_2", number: 5, checks: .failed), pr("PR_3", number: 6, checks: .pending)],
                 requested: [pr("PR_9", number: 12)], runs: [run(1, .running)])
    let list = GitHubPanelRows.make(s)
    #expect(list.rows.map(\.id) == ["run:1", "PR_2", "PR_3"])
    #expect(list.rows.map(\.mark) == [.running, .failed, .running])
    #expect(list.more == 2, "PR_1 and the review request did not fit")
    let few = GitHubPanelRows.make(snap(0, mine: [pr(checks: .passed)], requested: [pr("PR_9", number: 12)]))
    #expect(few.rows.map(\.mark) == [.passed, .review] && few.more == 0)
    #expect(few.rows[0].title == "#4 update notice" && few.rows[0].repo == "ledge")
    #expect(GitHubPanelRows.make(snap(0)).rows.isEmpty)
}

@Test func theProbesStoryTellsEveryMoment() {
    let story = GitHubSample.story(login: "you", start: t0)
    let pairs = zip([nil] + story.map(Optional.some), story)
    let told = pairs.map { old, new in GitHubEvents.between(old, new).map(name) }
    #expect(told == [[], [], ["checksFailed"], ["commented"], ["reviewed"], ["merged"], ["reviewRequested"]])
    #expect(GitHubEvents.running(in: story[1]).count == 1)
    #expect(!GitHubPanelRows.make(story[6]).rows.isEmpty)
}

private func name(_ event: GitHubEvent) -> String {
    switch event {
    case .checksPassed: "checksPassed"
    case .checksFailed: "checksFailed"
    case .reviewed: "reviewed"
    case .commented: "commented"
    case .merged: "merged"
    case .closed: "closed"
    case .reviewRequested: "reviewRequested"
    case .runPassed: "runPassed"
    case .runFailed: "runFailed"
    }
}
```

- [ ] **Step 2: Run them to see them fail.** `make test FILTER=GitHubServiceTests` → does not build: `GitHubEvents` unknown.

- [ ] **Step 3: The comparison.** Create `Sources/GitHubService/GitHubEvents.swift`:

```swift
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
```

- [ ] **Step 4: The look.** Create `Sources/GitHubService/GitHubNotice.swift`:

```swift
import Foundation

/// How one event looks on the island (2026-10-22).
public struct GitHubBlip: Sendable, Equatable {
    public let title: String
    public let symbolName: String
    /// The trailing ear's word.
    public let word: String
    /// An Apple system colour by name (`SystemTint`), `nil` for white.
    public let tintName: String?
    public let caption: String
    public let url: URL
}

public enum GitHubNotice {
    /// The running item's ring and clock.
    public static let runningTintName = "yellow"

    public static func blip(for event: GitHubEvent) -> GitHubBlip {
        switch event {
        case .checksPassed(let pr):
            return GitHubBlip(title: "Checks passed", symbolName: "checkmark.circle.fill", word: "Passed",
                              tintName: "green", caption: prCaption(pr), url: pr.url)
        case .checksFailed(let pr):
            return GitHubBlip(title: "Checks failed", symbolName: "xmark.circle.fill", word: "Failed", tintName: "red",
                              caption: "#\(pr.number) \(short(pr.title)) · \(pr.checks?.failedName ?? pr.repo)",
                              url: pr.checks?.failedURL ?? pr.url)
        case .reviewed(let pr, let review):
            let url = review.url ?? pr.url
            switch review.state {
            case .approved:
                return GitHubBlip(title: "Approved", symbolName: "checkmark.seal.fill", word: "Approved", tintName: "green",
                                  caption: byCaption(review.author, pr), url: url)
            case .changesRequested:
                return GitHubBlip(title: "Changes requested", symbolName: "exclamationmark.bubble.fill", word: "Changes",
                                  tintName: "orange", caption: byCaption(review.author, pr), url: url)
            case .commented, .other:
                return GitHubBlip(title: "Comment", symbolName: "bubble.left.fill", word: "Comment", tintName: nil,
                                  caption: byCaption(review.author, pr), url: url)
            }
        case .commented(let pr, let comment):
            return GitHubBlip(title: "Comment", symbolName: "bubble.left.fill", word: "Comment", tintName: nil,
                              caption: byCaption(comment.author, pr), url: comment.url ?? pr.url)
        case .merged(let pr):
            return GitHubBlip(title: "Merged", symbolName: "arrow.triangle.merge", word: "Merged", tintName: "purple",
                              caption: prCaption(pr), url: pr.url)
        case .closed(let pr):
            return GitHubBlip(title: "Closed", symbolName: "xmark.circle", word: "Closed", tintName: "gray",
                              caption: prCaption(pr), url: pr.url)
        case .reviewRequested(let pr):
            return GitHubBlip(title: "Review requested", symbolName: "eye.fill", word: "Review", tintName: "blue",
                              caption: "\(pr.author ?? "Someone") asks for your review · #\(pr.number) \(pr.repo)", url: pr.url)
        case .runPassed(let run):
            return GitHubBlip(title: "Run passed", symbolName: "checkmark.circle.fill", word: "Passed", tintName: "green",
                              caption: runCaption(run), url: run.url)
        case .runFailed(let run):
            return GitHubBlip(title: "Run failed", symbolName: "xmark.circle.fill", word: "Failed", tintName: "red",
                              caption: runCaption(run), url: run.url)
        }
    }

    /// Lower is more important: what needs the user, then good news, then
    /// chatter.
    public static func rank(_ event: GitHubEvent) -> Int {
        switch event {
        case .checksFailed, .runFailed: return 0
        case .reviewed(_, let review) where review.state == .changesRequested: return 1
        case .reviewRequested: return 2
        case .reviewed(_, let review) where review.state == .approved: return 3
        case .merged: return 4
        case .checksPassed, .runPassed: return 5
        case .reviewed, .commented: return 6
        case .closed: return 7
        }
    }

    /// One blip for everything a round found: the most important, and how
    /// many more there were.
    public static func burst(_ events: [GitHubEvent]) -> GitHubBlip? {
        guard let top = events.enumerated()
            .min(by: { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) })?.element else { return nil }
        let blip = blip(for: top)
        guard events.count > 1 else { return blip }
        return GitHubBlip(title: blip.title, symbolName: blip.symbolName, word: blip.word, tintName: blip.tintName,
                          caption: "\(blip.caption) · +\(events.count - 1) more", url: blip.url)
    }

    static func prCaption(_ pr: GitHubPR) -> String { "#\(pr.number) \(short(pr.title)) · \(pr.repo)" }
    static func runCaption(_ run: GitHubRun) -> String { "\(run.workflow) · \(run.repo)" }
    static func byCaption(_ login: String, _ pr: GitHubPR) -> String { "\(login) · #\(pr.number) \(pr.repo)" }

    /// A long title would stretch the caption across the menu bar.
    static func short(_ title: String) -> String {
        title.count > 40 ? String(title.prefix(39)) + "…" : title
    }
}
```

- [ ] **Step 5: The panel's list.** Create `Sources/GitHubService/GitHubPanelRows.swift`:

```swift
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
```

- [ ] **Step 6: The sample.** Create `Sources/GitHubService/GitHubSample.swift`:

```swift
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
```

- [ ] **Step 7: Run the tests.** `make test FILTER=GitHubServiceTests` → all pass (Task 1's seven and these fourteen).

- [ ] **Step 8: Commit.**

```bash
git add Sources/GitHubService Tests/GitHubServiceTests
git commit -m "tell what happened on github between two rounds, how each moment looks on the island, and what the panel lists

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log -1 --stat
```

---

### Task 3: The login, the schedule and the loop

**Files:** Create `Sources/GitHubService/GitHubToken.swift`, `GitHubSchedule.swift`, `GitHubMonitor.swift`, `Tests/GitHubServiceTests/GitHubMonitorTests.swift`.

**Interfaces — Consumes:** `GitHubClient.round(previous:now:)`, `GitHubEvents.between`, `GitHubEvents.running(in:)`.
**Produces:**
- `public enum GitHubTokenSource: String { gh, keychain }`
- `public enum GitHubToken { static let ghPaths; static func parse(ghOutput: String) -> String?; static func fromGH(paths: [String] = ghPaths) async -> String? }`
- `public struct GitHubKeychain { init(service: String); func read() -> String?; @discardableResult func save(_: String) -> Bool; func delete() }`
- `public enum GitHubOutcome { ok(anythingRunning: Bool), unauthorised, rateLimited(until: Date), unavailable }`; `public enum GitHubSchedule { static func delay(after: GitHubOutcome, failures: Int, now: Date) -> TimeInterval? }`
- `@MainActor public final class GitHubMonitor` (`enum Status: Equatable { off, checking, ok(at: Date), signInAgain, rateLimited(until: Date), failed(at: Date) }`; `status`; `snapshot: GitHubSnapshot?`; `onRound: ((GitHubSnapshot, [GitHubEvent]) -> Void)?`; `isRunning: Bool`; `init(now:)`; `start(_ client: GitHubClient)`; `stop()`; `checkNow()`; internal `prepare(_:)` and `round() async -> TimeInterval?` for tests)

- [ ] **Step 1: Failing tests.** Create `Tests/GitHubServiceTests/GitHubMonitorTests.swift`:

```swift
import Testing
import Foundation
@testable import GitHubService

@Test func ghsOutputIsReadAsOneToken() {
    #expect(GitHubToken.parse(ghOutput: "gho_abc123\n") == "gho_abc123")
    #expect(GitHubToken.parse(ghOutput: "") == nil)
    #expect(GitHubToken.parse(ghOutput: "no oauth token found for github.com\n") == nil)
    #expect(GitHubToken.parse(ghOutput: "one\ntwo\n") == nil)
}

@Test func theTokenComesFromGhWhenItIsThere() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "gh-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    func script(_ name: String, _ body: String) throws -> String {
        let file = folder.appending(path: name)
        try body.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path(percentEncoded: false))
        return file.path(percentEncoded: false)
    }
    let gh = try script("gh", "#!/bin/sh\necho gho_fromgh\n")
    let loggedOut = try script("gh-out", "#!/bin/sh\necho 'not logged in' >&2\nexit 1\n")
    #expect(await GitHubToken.fromGH(paths: [gh]) == "gho_fromgh")
    #expect(await GitHubToken.fromGH(paths: [loggedOut]) == nil)
    #expect(await GitHubToken.fromGH(paths: [folder.appending(path: "missing").path(percentEncoded: false)]) == nil)
}

@Test func theScheduleWaitsAsTheSpecSays() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(GitHubSchedule.delay(after: .ok(anythingRunning: false), failures: 0, now: now) == 60)
    #expect(GitHubSchedule.delay(after: .ok(anythingRunning: true), failures: 0, now: now) == 20)
    #expect(GitHubSchedule.delay(after: .unavailable, failures: 1, now: now) == 60)
    #expect(GitHubSchedule.delay(after: .unavailable, failures: 2, now: now) == 120)
    #expect(GitHubSchedule.delay(after: .unavailable, failures: 9, now: now) == 300)
    #expect(GitHubSchedule.delay(after: .rateLimited(until: now.addingTimeInterval(600)), failures: 0, now: now) == 600)
    #expect(GitHubSchedule.delay(after: .rateLimited(until: now.addingTimeInterval(-5)), failures: 0, now: now) == 60,
            "a reset already past waits the usual minute")
    #expect(GitHubSchedule.delay(after: .unauthorised, failures: 0, now: now) == nil)
}

@MainActor
private final class Clock {
    var now = fixtureNow
}

@MainActor
@Test func theMonitorIsQuietOnItsFirstRoundThenTellsWhatChanged() async {
    let calls = Counter()
    let client = GitHubClient(token: "t", userAgent: "Ledge", fetch: fetch { request in
        if request.url!.path().hasSuffix("/actions/runs") { return (200, [:], runsReply) }
        // The second round: PR #5's checks have passed.
        return (200, [:], calls.next() == 0 ? mineReply : mineReply.replacingOccurrences(
            of: #""statusCheckRollup":{"state":"PENDING""#, with: #""statusCheckRollup":{"state":"SUCCESS""#))
    })
    let clock = Clock()
    let monitor = GitHubMonitor(now: { clock.now })
    var rounds: [[GitHubEvent]] = []
    monitor.onRound = { _, events in rounds.append(events) }
    monitor.prepare(client)
    #expect(monitor.isRunning)
    #expect(await monitor.round() == 20, "something runs, so the next round comes sooner")
    #expect(rounds == [[]])
    #expect(monitor.status == .ok(at: fixtureNow))
    #expect(monitor.snapshot?.login == "dede")
    clock.now = fixtureNow.addingTimeInterval(60)
    _ = await monitor.round()
    #expect(rounds.count == 2)
    guard case .checksPassed(let pr)? = rounds.last?.first, rounds.last?.count == 1 else {
        Issue.record("expected one checks-passed event, got \(String(describing: rounds.last))")
        return
    }
    #expect(pr.number == 5)
}

@MainActor
@Test func aRefusedLoginStopsAndFailuresBackOff() async {
    let refused = GitHubMonitor(now: { fixtureNow })
    refused.prepare(GitHubClient(token: "t", userAgent: "Ledge", fetch: fetch { _ in (401, [:], "") }))
    #expect(await refused.round() == nil)
    #expect(refused.status == .signInAgain)

    let flaky = GitHubMonitor(now: { fixtureNow })
    flaky.prepare(GitHubClient(token: "t", userAgent: "Ledge", fetch: fetch { _ in (502, [:], "") }))
    #expect(await flaky.round() == 60)
    #expect(await flaky.round() == 120)
    #expect(await flaky.round() == 300)
    #expect(flaky.status == .failed(at: fixtureNow))
    flaky.stop()
    #expect(flaky.status == .off && flaky.snapshot == nil && !flaky.isRunning)
}
```

- [ ] **Step 2: Run them to see them fail.** `make test FILTER=GitHubServiceTests` → does not build: `GitHubToken` unknown.

- [ ] **Step 3: The login.** Create `Sources/GitHubService/GitHubToken.swift`:

```swift
import Foundation
import Security

/// Where the user's GitHub login came from (2026-10-22).
public enum GitHubTokenSource: String, Sendable, Equatable {
    case gh, keychain
}

public enum GitHubToken {
    /// Where Homebrew puts `gh` on Apple silicon and on Intel.
    public static let ghPaths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]

    /// `gh auth token` prints the token and a newline; anything else
    /// (nothing, a message, several lines) is no token.
    public static func parse(ghOutput: String) -> String? {
        let lines = ghOutput.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard lines.count == 1, let token = lines.first, !token.contains(" ") else { return nil }
        return token
    }

    /// Asks `gh` for its token; `nil` when `gh` is not installed or not
    /// logged in.
    public static func fromGH(paths: [String] = ghPaths) async -> String? {
        guard let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        return await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: path)
            process.arguments = ["auth", "token", "--hostname", "github.com"]
            let out = Pipe()
            process.standardOutput = out
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? parse(ghOutput: String(decoding: data, as: UTF8.self)) : nil
        }.value
    }
}

/// A token pasted in Settings (2026-10-22), kept in the login keychain.
public struct GitHubKeychain: Sendable {
    public static let account = "github.com"
    public let service: String

    public init(service: String) {
        self.service = service
    }

    public func read() -> String? {
        var query = base
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public func save(_ token: String) -> Bool {
        delete()
        var query = base
        query[kSecValueData as String] = Data(token.utf8)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    public func delete() {
        SecItemDelete(base as CFDictionary)
    }

    private var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: Self.account]
    }
}
```

The Keychain store has no automated test: a test would write to the user's real login keychain. It is checked live in Task 7.

- [ ] **Step 4: The schedule.** Create `Sources/GitHubService/GitHubSchedule.swift`:

```swift
import Foundation

/// How a round went, for the schedule (2026-10-22).
public enum GitHubOutcome: Sendable, Equatable {
    case ok(anythingRunning: Bool)
    case unauthorised
    case rateLimited(until: Date)
    case unavailable
}

public enum GitHubSchedule {
    public static let idle: TimeInterval = 60
    public static let busy: TimeInterval = 20
    public static let backoff: [TimeInterval] = [60, 120, 300]

    /// Seconds until the next round, or `nil` to stop until the user tries
    /// again. `failures` counts unavailable rounds in a row, this one
    /// included.
    public static func delay(after outcome: GitHubOutcome, failures: Int, now: Date) -> TimeInterval? {
        switch outcome {
        case .ok(let running): return running ? busy : idle
        case .unauthorised: return nil
        case .rateLimited(let until): return max(idle, until.timeIntervalSince(now))
        case .unavailable: return backoff[min(max(failures, 1), backoff.count) - 1]
        }
    }
}
```

- [ ] **Step 5: The loop.** Create `Sources/GitHubService/GitHubMonitor.swift`:

```swift
import Foundation

/// The loop (2026-10-22): asks GitHub, compares with the last good answer,
/// and hands the app what it found. A round at once on `start` and on
/// `checkNow()`; between rounds it waits as `GitHubSchedule` says. The last
/// good snapshot is kept through failures, so what happened while GitHub
/// was out of reach is told once it answers again.
@MainActor
public final class GitHubMonitor {
    public enum Status: Sendable, Equatable {
        case off
        /// The first round after start.
        case checking
        case ok(at: Date)
        case signInAgain
        case rateLimited(until: Date)
        case failed(at: Date)
    }

    public private(set) var status: Status = .off
    /// The last good answer, and the baseline the next round compares with.
    public private(set) var snapshot: GitHubSnapshot?
    /// Every good round: what was found, and what happened since the last.
    public var onRound: ((GitHubSnapshot, [GitHubEvent]) -> Void)?

    private var client: GitHubClient?
    private var loop: Task<Void, Never>?
    private var failures = 0
    private let now: @MainActor () -> Date

    public init(now: @escaping @MainActor () -> Date = { Date() }) {
        self.now = now
    }

    public var isRunning: Bool { client != nil }

    /// Starts over with `client`: the first round is a quiet baseline.
    public func start(_ client: GitHubClient) {
        prepare(client)
        restart()
    }

    public func stop() {
        loop?.cancel()
        loop = nil
        client = nil
        snapshot = nil
        failures = 0
        status = .off
    }

    /// A round now, then the schedule as usual. Nothing while stopped or
    /// after a 401, which needs `start` with a new client.
    public func checkNow() {
        guard client != nil, status != .signInAgain else { return }
        restart()
    }

    func prepare(_ client: GitHubClient) {
        stop()
        self.client = client
        status = .checking
    }

    private func restart() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled, let delay = await self?.round() {
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// One round; how long to wait before the next, or `nil` to stop.
    func round() async -> TimeInterval? {
        guard let client else { return nil }
        let previous = snapshot
        let result = await client.round(previous: previous, now: now())
        // Stopped, restarted or given another client while asking.
        guard !Task.isCancelled, client === self.client else { return nil }
        let outcome: GitHubOutcome
        switch result {
        case .success(let next):
            failures = 0
            snapshot = next
            status = .ok(at: next.takenAt)
            onRound?(next, GitHubEvents.between(previous, next))
            outcome = .ok(anythingRunning: !GitHubEvents.running(in: next).isEmpty)
        case .failure(.unauthorised):
            status = .signInAgain
            outcome = .unauthorised
        case .failure(.rateLimited(let until)):
            status = .rateLimited(until: until)
            outcome = .rateLimited(until: until)
        case .failure(.unavailable):
            failures += 1
            status = .failed(at: now())
            outcome = .unavailable
        }
        return GitHubSchedule.delay(after: outcome, failures: failures, now: now())
    }
}
```

- [ ] **Step 6: Run the tests.** `make test FILTER=GitHubServiceTests` → all pass. `make build` → builds.

- [ ] **Step 7: Commit.**

```bash
git add Sources/GitHubService Tests/GitHubServiceTests
git commit -m "take the github login from gh or the keychain, and ask every minute, every 20 seconds while something runs, backing off when github is out of reach

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log -1 --stat
```

---

### Task 4: The island: two kinds, a panel and a turning ring

**Files:** Modify `Sources/ActivityKit/ActivityKind.swift`, `Sources/ActivityKit/ActivityRecord.swift`, `Sources/NotchKit/NotchController.swift`, `Sources/NotchKit/NotchPresenter.swift`, `Sources/NotchKit/NotchRootView.swift`; create `Sources/NotchKit/GitHubPanel.swift`, `Sources/NotchKit/GitHubPanelView.swift`; test `Tests/ActivityKitTests/ActivityQueueTests.swift`, `Tests/NotchKitTests/NotchControllerTests.swift`.

**Interfaces — Produces:**
- `ActivityKind.github` (38, 8 s), `ActivityKind.githubRun` (18, sticky)
- `ActivityRecord.badge: Int?` and `ActivityDisplay.badge: Int?`, both a last init parameter `badge: Int? = nil`
- `NotchController.githubActivityID = "github"`, `githubRunActivityID = "github-run"`, `isGitHubLeading`, `Panel.github`, `githubPanel: GitHubPanelData?`, `setGitHubPanel(_:)`
- `NotchPresenter.setGitHubPanel(_:)`
- `public struct GitHubPanelData` (`struct Row: Identifiable { enum Mark { running, passed, failed, none, review }; id, mark, title, repo, url; public init }`, `rows`, `more`, `moreURL`; `init(rows:more:moreURL:)` with defaults `0` and `https://github.com/pulls`)

- [ ] **Step 1: Failing tests.** Append to `Tests/ActivityKitTests/ActivityQueueTests.swift`:

```swift
@Test func gitHubBlipsAndTheRunningItemSitWhereTheSpecSays() {
    #expect(ActivityKind.github.priority == 38)
    #expect(ActivityKind.github.defaultTTL == 8)
    #expect(ActivityKind.github < .notification && ActivityKind.github > .update)
    #expect(ActivityKind.githubRun.priority == 18)
    #expect(ActivityKind.githubRun.defaultTTL == nil, "sticky while anything runs")
    #expect(ActivityKind.githubRun < .timer && ActivityKind.githubRun > .liveActivity)
}

@Test func aRecordCarriesItsBadge() {
    let record = ActivityRecord(id: "github-run", kind: .githubRun, insertedAt: Date(), ttl: nil, title: "Checks running", badge: 2)
    #expect(record.badge == 2)
}
```

Append to `Tests/NotchKitTests/NotchControllerTests.swift`:

```swift
private let gitHubPanel = GitHubPanelData(rows: [
    .init(id: "PR_1", mark: .failed, title: "#4 update notice", repo: "ledge", url: URL(string: "https://github.com/dede/ledge/pull/4")!),
])

@MainActor
@Test func aGitHubBlipCarriesItsCaption() {
    let c = makeController()
    c.setActivities([.init(id: NotchController.githubActivityID, title: "Checks failed", compactText: "Failed",
                           symbolName: "xmark.circle.fill")], overflow: 0)
    c.setCaption("#4 update notice · test (macos)")
    #expect(c.state == .activity)
    #expect(c.isGitHubLeading)
    #expect(c.captionText == "#4 update notice · test (macos)")
}

@MainActor
@Test func theGitHubPanelJoinsTheSwipeOrderAndGoesWithItsData() {
    let c = makeController()
    c.setMedia(MediaPresentation(title: "Song", artist: "Artist", artwork: nil, isPlaying: true, elapsed: 10, duration: 200))
    #expect(c.availablePanels == [.media])
    c.setGitHubPanel(gitHubPanel)
    #expect(c.availablePanels == [.media, .github])
    c.setHovered(true)
    #expect(c.state == .expanded && c.panel == .media)
    #expect(c.swipe(.next))
    #expect(c.panel == .github)
    c.setGitHubPanel(nil)
    #expect(c.panel == .media)
}

@MainActor
@Test func hoveringTheRunningItemOpensTheGitHubPanel() {
    let c = makeController()
    c.setGitHubPanel(gitHubPanel)
    c.setActivities([.init(id: NotchController.githubRunActivityID, title: "Checks running", compactText: "2:14", badge: 2)],
                    overflow: 0)
    #expect(c.activities.first?.badge == 2)
    c.setHovered(true)
    #expect(c.state == .expanded && c.panel == .github)
    c.setHovered(false)
    #expect(c.state == .activity)
}

@MainActor
@Test func aSwipeOnTheEmptyPeekOpensTheGitHubPanel() {
    let c = makeController()
    c.setHovered(true)
    #expect(c.state == .peek)
    #expect(!c.swipe(.next), "nothing to open yet")
    c.setGitHubPanel(gitHubPanel)
    #expect(c.swipe(.next))
    #expect(c.state == .expanded && c.panel == .github)
}

@MainActor
@Test func withoutAPanelTheRunningItemStaysAnItem() {
    let c = makeController()
    c.setActivities([.init(id: NotchController.githubRunActivityID, title: "Checks running", compactText: "0:42")], overflow: 0)
    c.setHovered(true)
    #expect(c.state == .activity)
}
```

- [ ] **Step 2: Run them to see them fail.** `make test FILTER=ActivityKitTests` and `make test FILTER=NotchKitTests` → do not build.

- [ ] **Step 3: The kinds.** In `Sources/ActivityKit/ActivityKind.swift`:
  - after `case notification` add:
    ```swift
        /// Something on GitHub (2026-10-22): checks finished, a review, a
        /// merge, a review request. Under a notification, over the update
        /// notice.
        case github
    ```
  - after `case timer`'s declaration add:
    ```swift
        /// GitHub checks or a run of the user's going now (2026-10-22):
        /// sticky while anything runs, under a Clock timer (the user's own
        /// doing), over an iPhone Live Activity.
        case githubRun
    ```
  - in `priority` add `case .github:       return 38` after `.notification`, and `case .githubRun:    return 18` after `.timer`;
  - in `defaultTTL` add `case .github:       return 8       // a word and a line to read` after `.notification`, and `case .githubRun:    return nil` after `.timer`.

- [ ] **Step 4: The badge.** In `Sources/ActivityKit/ActivityRecord.swift`, in `ActivityRecord`: after `public let lines: [String]` add

```swift
    /// A small count on the leading glyph (2026-10-22): how many GitHub
    /// checks and runs are going. `nil` draws none.
    public let badge: Int?
```

add `badge: Int? = nil` as the init's last parameter (after `lines: [String] = []`) and `self.badge = badge` as its last line. Make the same three changes to `NotchController.ActivityDisplay` in `Sources/NotchKit/NotchController.swift` (after its `public let lines: [String]`, its init's last parameter, its init's last line).

- [ ] **Step 5: The panel's data.** Create `Sources/NotchKit/GitHubPanel.swift`:

```swift
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
```

- [ ] **Step 6: The controller.** In `Sources/NotchKit/NotchController.swift`:
  1. After the `isUpdateLeading` property add:
     ```swift
         /// `AppModel` inserts a GitHub blip with this id, and the running
         /// item with `githubRunActivityID` (2026-10-22).
         public static let githubActivityID = "github"
         public static let githubRunActivityID = "github-run"

         public var isGitHubLeading: Bool {
             activities.first?.id == Self.githubActivityID
         }

         /// A GitHub blip or the running item leads: hover opens the panel.
         private var isAnyGitHubLeading: Bool {
             isGitHubLeading || activities.first?.id == Self.githubRunActivityID
         }
     ```
  2. In `hasCaption`, change `(isMediaLeading || isCalendarLeading || isUpdateLeading)` to `(isMediaLeading || isCalendarLeading || isUpdateLeading || isGitHubLeading)` and add to its doc comment the line `/// A GitHub blip (2026-10-22) carries its own as well.`
  3. In `enum Panel`, after `case liveActivity` add:
     ```swift
             /// What is going on on GitHub (2026-10-22).
             case github
     ```
  4. After `setCalendarMode(_:)` add:
     ```swift
         /// What the GitHub panel lists; `nil` means no panel: not connected,
         /// nothing to list, or the screen is locked (2026-10-22).
         public private(set) var githubPanel: GitHubPanelData?

         public func setGitHubPanel(_ data: GitHubPanelData?) {
             guard data != githubPanel else { return }
             githubPanel = data
             if githubPanel == nil, panel == .github { panel = .media }
             recomputeState()
         }
     ```
  5. In `availablePanels`, after `if calendarMode != nil { panels.append(.calendar) }` add `if githubPanel != nil { panels.append(.github) }`.
  6. In `swipe(_:)`, after the `if isPreviewingUpcoming, calendarMode != nil { … }` block and before `return false` add:
     ```swift
             // The empty peek (2026-10-22): a swipe opens the GitHub panel.
             if state == .peek, githubPanel != nil {
                 lastSwipe = direction
                 panel = .github
                 recomputeState()
                 return true
             }
     ```
  7. In `setHovered(_:)`, after `if hovered, hasCard, !isPinnedOpen { panel = .liveActivity }` add:
     ```swift
             // So does a GitHub item's, the way a Live Activity's card opens
             // (2026-10-22).
             if hovered, isAnyGitHubLeading, githubPanel != nil, !isPinnedOpen { panel = .github }
     ```
  8. In `recomputeState()`, after the `} else if isHovered, panel == .liveActivity, hasCard {` branch's `state = .expanded` add:
     ```swift
             } else if isHovered, panel == .github, githubPanel != nil {
                 state = .expanded
     ```

- [ ] **Step 7: The presenter.** In `Sources/NotchKit/NotchPresenter.swift`, after `setCalendarMode(_:)` add:

```swift
    /// The GitHub panel (2026-10-22); can open or close the card.
    public func setGitHubPanel(_ data: GitHubPanelData?) {
        guard data != controller.githubPanel else { return }
        controller.setGitHubPanel(data)
        syncWindowToVisibility()
    }
```

- [ ] **Step 8: The panel and the ring.** Create `Sources/NotchKit/GitHubPanelView.swift`:

```swift
import SwiftUI

/// The GitHub panel of the open island (2026-10-22): a heading, then up to
/// four rows (the user's runs going now, their PRs, PRs waiting for their
/// review), each with its mark, its title, and its repo dim at the end. A
/// click opens it on GitHub; the last row says how many more there are.
/// The reveal and the rows follow `CalendarPanelView`.
struct GitHubPanelView: View {
    let data: GitHubPanelData
    let contentColor: Color
    let reduceMotion: Bool
    let emit: (NotchIntent) -> Void

    /// Spelled-out `State`, as elsewhere here.
    private var _revealed: State<Bool> = State(initialValue: false)
    private var revealed: Bool {
        get { _revealed.wrappedValue }
        nonmutating set { _revealed.wrappedValue = newValue }
    }

    private func reveal<V: View>(_ view: V, order: Int) -> some View {
        view
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 3)
            .animation(
                reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 1.0).delay(Double(order) * 0.022),
                value: revealed
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            reveal(Text("GITHUB")
                .font(.system(size: 9.5, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(contentColor.opacity(0.5))
                .frame(height: 14), order: 0)
            ForEach(Array(data.rows.enumerated()), id: \.element.id) { index, row in
                reveal(button(row.url) { label(row) }, order: 1 + index)
            }
            if data.more > 0 {
                reveal(button(data.moreURL) {
                    Text("\(data.more) more on GitHub")
                        .font(.system(size: 10.5))
                        .foregroundStyle(contentColor.opacity(0.5))
                        .padding(.leading, 17)
                }, order: 1 + data.rows.count)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.top, 8)
        .foregroundStyle(contentColor)
        .onAppear { revealed = true }
    }

    private func button<Label: View>(_ url: URL, @ViewBuilder label: () -> Label) -> some View {
        Button {
            emit(.open(url))
        } label: {
            label()
                .frame(height: 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(ListRowButtonStyle(reduceMotion: reduceMotion))
    }

    private func label(_ row: GitHubPanelData.Row) -> some View {
        HStack(spacing: 6) {
            mark(row.mark)
            Text(row.title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(contentColor.opacity(0.92))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(row.repo)
                .font(.system(size: 10.5))
                .foregroundStyle(contentColor.opacity(0.5))
                .lineLimit(1)
                .fixedSize()
        }
    }

    /// A check dot in GitHub's own colours, or an eye for a review
    /// request, in an 11 pt column so the titles line up.
    private func mark(_ mark: GitHubPanelData.Row.Mark) -> some View {
        Group {
            switch mark {
            case .review:
                Image(systemName: "eye.fill")
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .systemBlue))
            case .running:
                Circle().fill(Color(nsColor: .systemYellow)).frame(width: 7, height: 7)
            case .passed:
                Circle().fill(Color(nsColor: .systemGreen)).frame(width: 7, height: 7)
            case .failed:
                Circle().fill(Color(nsColor: .systemRed)).frame(width: 7, height: 7)
            case .none:
                Circle().fill(contentColor.opacity(0.3)).frame(width: 7, height: 7)
            }
        }
        .frame(width: 11)
    }
}

/// The running item's glyph (2026-10-22): an arc turning once every 1.2 s,
/// the island's "working" idiom, and the count of what runs when more than
/// one does. Still under Reduce Motion.
struct GitHubRunRing: View {
    let color: Color
    let count: Int?
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.25), lineWidth: 2)
            TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
                let turn = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1.2) / 1.2
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(turn * 360 - 90))
            }
            if let count, count > 1 {
                Text("\(count)")
                    .font(.system(size: 8, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
        .frame(width: 14, height: 14)
    }
}
```

- [ ] **Step 9: The view.** In `Sources/NotchKit/NotchRootView.swift`:
  1. In `leadingEar`, immediately before the branch `} else if let activity = controller.activities.first, activity.id == NotchController.timerActivityID,` insert:
     ```swift
             } else if let activity = controller.activities.first, activity.id == NotchController.githubRunActivityID {
                 // GitHub checks or a run going (2026-10-22): an amber arc
                 // turning, the count of what runs on it.
                 GitHubRunRing(color: tintColor(for: activity.tint) ?? contentColor, count: activity.badge,
                               reduceMotion: controller.reduceMotion)
     ```
  2. In `trailingEar`, replace
     ```swift
                     let isTimer = activity.id == NotchController.timerActivityID
                     compactValue(compact, bump: !isTimer, color: isTimer ? tintColor(for: activity.tint) : nil)
     ```
     with
     ```swift
                     // …and the GitHub running item's clock, amber (2026-10-22).
                     let isTicking = activity.id == NotchController.timerActivityID
                         || activity.id == NotchController.githubRunActivityID
                     compactValue(compact, bump: !isTicking, color: isTicking ? tintColor(for: activity.tint) : nil)
     ```
  3. In `detailRow`, immediately before the branch `} else if controller.state == .expanded, let media = controller.media {` insert:
     ```swift
             } else if controller.state == .expanded, controller.panel == .github, let data = controller.githubPanel {
                 // The GitHub panel (2026-10-22).
                 GitHubPanelView(
                     data: data, contentColor: contentColor,
                     reduceMotion: controller.reduceMotion, emit: { controller.emit($0) }
                 )
                 .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                 .id("github")
                 .transition(panelTransition)
     ```

- [ ] **Step 10: Run the tests.** `make test FILTER=ActivityKitTests`, `make test FILTER=NotchKitTests` → pass; then `make test` (the full suite; only the two known tests may fail) and `make build`.

- [ ] **Step 11: Commit.**

```bash
git add Sources/ActivityKit Sources/NotchKit Tests/ActivityKitTests Tests/NotchKitTests
git commit -m "give the island a github blip with its caption, a running item with a turning ring and a count, and a github panel that hover and swipe open

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log -1 --stat
```

---

### Task 5: The switches and the preview scenes

**Files:** Modify `Sources/LedgeSettings/AppSettings.swift`, `Sources/SettingsKit/PreviewScene.swift`, `Sources/SettingsKit/PreviewContent.swift`, `Sources/SettingsKit/PreviewStage.swift`; test `Tests/LedgeSettingsTests/AppSettingsTests.swift`, `Tests/SettingsKitTests/PreviewStageTests.swift`.

**Interfaces — Consumes:** `GitHubNotice.blip(for:)`, `GitHubNotice.runningTintName`, `GitHubSample.pr/.request/.run/.reviewer`, `GitHubReview`, `NotchController.githubActivityID/githubRunActivityID`.
**Produces:** `AppSettings.githubConnected` (default false), `githubChecksFinished`, `githubChecksRunning`, `githubReviews`, `githubMerges`, `githubReviewRequests`, `githubMyRuns` (default true); `PreviewScene.githubRunning, githubChecks, githubReviews, githubMerges, githubRequests, githubRuns`; `PreviewContent.pullRequest: GitHubPR?` (init parameter `pullRequest: GitHubPR? = nil`, last).

- [ ] **Step 1: Failing tests.** Append to `Tests/LedgeSettingsTests/AppSettingsTests.swift`:

```swift
@Test func gitHubStartsDisconnectedWithEveryMomentOn() {
    let (s, defaults) = fresh()
    #expect(!s.githubConnected)
    #expect(s.githubChecksFinished && s.githubChecksRunning && s.githubReviews)
    #expect(s.githubMerges && s.githubReviewRequests && s.githubMyRuns)
    s.githubConnected = true
    s.githubReviews = false
    let again = AppSettings(defaults: defaults)
    #expect(again.githubConnected && !again.githubReviews && again.githubMerges)
}
```

Append to `Tests/SettingsKitTests/PreviewStageTests.swift` (add `import GitHubService` to its imports, and add `"GitHubService"` to the `SettingsKitTests` test target's dependencies in `Package.swift`):

```swift
@MainActor
@Test func theGitHubScenesShowTheirMoments() {
    let c = island()
    let checks = PreviewStage.apply(.githubChecks, content: PreviewContent(), to: c)
    #expect(checks.text == "Checks finished · Sample: not connected")
    #expect(c.activities.first?.id == NotchController.githubActivityID)
    #expect(c.activities.first?.compactText == "Failed")
    #expect(c.captionText == "#12 Fix the date picker · test (macos)")
    _ = PreviewStage.apply(.githubRunning, content: PreviewContent(), to: c)
    #expect(c.activities.first?.id == NotchController.githubRunActivityID)
    #expect(c.activities.first?.compactText == "2:14")
    _ = PreviewStage.apply(.githubRequests, content: PreviewContent(), to: c)
    #expect(c.captionText == "sam asks for your review · #7 site")
    _ = PreviewStage.apply(.githubRuns, content: PreviewContent(), to: c)
    #expect(c.captionText == "Deploy · web")
    let mine = GitHubPR(id: "PR_1", number: 4, title: "update notice", url: URL(string: "https://github.com/dede/ledge/pull/4")!, repo: "ledge")
    let real = PreviewStage.apply(.githubMerges, content: PreviewContent(pullRequest: mine), to: c)
    #expect(real.sampleReason == nil)
    #expect(c.captionText == "#4 update notice · ledge")
}

@MainActor
@Test func theGitHubScenesFollowTheirSwitches() {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "ledge.tests.\(UUID().uuidString)")!)
    #expect(PreviewScene.githubReviews.isOn(in: settings))
    settings.githubReviews = false
    #expect(!PreviewScene.githubReviews.isOn(in: settings))
    #expect(PreviewScene.githubRunning.title == "Checks running")
}
```

- [ ] **Step 2: Run them to see them fail.** `make test FILTER=LedgeSettingsTests`, `make test FILTER=SettingsKitTests` → do not build.

- [ ] **Step 3: The switches.** In `Sources/LedgeSettings/AppSettings.swift`:
  - in `Key`, after `checksForUpdates`, add the seven keys, each named as its property: `githubConnected`, `githubChecksFinished`, `githubChecksRunning`, `githubReviews`, `githubMerges`, `githubReviewRequests`, `githubMyRuns` (for example `public static let githubConnected = "githubConnected"`);
  - after `checksForUpdates`'s property add:
    ```swift
        /// GitHub on the island (2026-10-22): off until the user connects.
        public var githubConnected: Bool { didSet { save(githubConnected, Key.githubConnected) } }
        /// The moments the island tells, each on by default.
        public var githubChecksFinished: Bool { didSet { save(githubChecksFinished, Key.githubChecksFinished) } }
        public var githubChecksRunning: Bool { didSet { save(githubChecksRunning, Key.githubChecksRunning) } }
        public var githubReviews: Bool { didSet { save(githubReviews, Key.githubReviews) } }
        public var githubMerges: Bool { didSet { save(githubMerges, Key.githubMerges) } }
        public var githubReviewRequests: Bool { didSet { save(githubReviewRequests, Key.githubReviewRequests) } }
        public var githubMyRuns: Bool { didSet { save(githubMyRuns, Key.githubMyRuns) } }
    ```
  - in `init(defaults:)`, after the `checksForUpdates = …` line add:
    ```swift
            githubConnected = defaults.object(forKey: Key.githubConnected) as? Bool ?? false
            githubChecksFinished = defaults.object(forKey: Key.githubChecksFinished) as? Bool ?? true
            githubChecksRunning = defaults.object(forKey: Key.githubChecksRunning) as? Bool ?? true
            githubReviews = defaults.object(forKey: Key.githubReviews) as? Bool ?? true
            githubMerges = defaults.object(forKey: Key.githubMerges) as? Bool ?? true
            githubReviewRequests = defaults.object(forKey: Key.githubReviewRequests) as? Bool ?? true
            githubMyRuns = defaults.object(forKey: Key.githubMyRuns) as? Bool ?? true
    ```

- [ ] **Step 4: The scenes.** In `Sources/SettingsKit/PreviewScene.swift`:
  - add a third `case` line: `case githubRunning, githubChecks, githubReviews, githubMerges, githubRequests, githubRuns`;
  - in `title` add:
    ```swift
            case .githubRunning:       return "Checks running"
            case .githubChecks:        return "Checks finished"
            case .githubReviews:       return "Reviews and comments"
            case .githubMerges:        return "Merges and closes"
            case .githubRequests:      return "Review requests"
            case .githubRuns:          return "Your runs outside PRs"
    ```
  - in `isOn(in:)` add:
    ```swift
            case .githubRunning:          return settings.githubChecksRunning
            case .githubChecks:           return settings.githubChecksFinished
            case .githubReviews:          return settings.githubReviews
            case .githubMerges:           return settings.githubMerges
            case .githubRequests:         return settings.githubReviewRequests
            case .githubRuns:             return settings.githubMyRuns
    ```

- [ ] **Step 5: The content.** In `Sources/SettingsKit/PreviewContent.swift`: add `import GitHubService` at the top; after `public var availableUpdate: String?` add

```swift
    /// The user's latest open PR, for the GitHub scenes (2026-10-22).
    public var pullRequest: GitHubPR?
```

add `pullRequest: GitHubPR? = nil` as the init's last parameter (after `availableUpdate: String? = nil`) and `self.pullRequest = pullRequest` as its last line.

- [ ] **Step 6: The stage.** In `Sources/SettingsKit/PreviewStage.swift`: add `import GitHubService` at the top; in `apply`'s switch, after the `.update` case, add:

```swift
        case .githubRunning:
            c.setActivities([NotchController.ActivityDisplay(
                id: NotchController.githubRunActivityID, title: "Checks running", compactText: "2:14",
                tint: .system(GitHubNotice.runningTintName)
            )], overflow: 0)
            return caption(scene, sample: "nothing running")
        case .githubChecks:
            showGitHub(c, .checksFailed(content.pullRequest ?? GitHubSample.pr))
            return caption(scene, sample: content.pullRequest == nil ? "not connected" : nil)
        case .githubReviews:
            let review = GitHubReview(id: "sample", author: GitHubSample.reviewer, state: .approved, at: nil, url: nil)
            showGitHub(c, .reviewed(content.pullRequest ?? GitHubSample.pr, review))
            return caption(scene, sample: content.pullRequest == nil ? "not connected" : nil)
        case .githubMerges:
            showGitHub(c, .merged(content.pullRequest ?? GitHubSample.pr))
            return caption(scene, sample: content.pullRequest == nil ? "not connected" : nil)
        case .githubRequests:
            showGitHub(c, .reviewRequested(GitHubSample.request))
            return caption(scene, sample: "no review requested")
        case .githubRuns:
            showGitHub(c, .runPassed(GitHubSample.run))
            return caption(scene, sample: "no run of yours")
```

and after `show(_:hud:)` add:

```swift
    /// A GitHub blip as the app shows it, caption and all (2026-10-22).
    private static func showGitHub(_ c: NotchController, _ event: GitHubEvent) {
        let blip = GitHubNotice.blip(for: event)
        c.setActivities([NotchController.ActivityDisplay(
            id: NotchController.githubActivityID, title: blip.title, compactText: blip.word,
            symbolName: blip.symbolName, tint: blip.tintName.map { .system($0) }
        )], overflow: 0)
        c.setCaption(blip.caption)
    }
```

- [ ] **Step 7: Run the tests.** `make test FILTER=LedgeSettingsTests`, `make test FILTER=SettingsKitTests` → pass (the existing `everySceneShowsSomethingAndIsCaptioned` covers the six new scenes). `make build`.

- [ ] **Step 8: Commit.**

```bash
git add Package.swift Sources/LedgeSettings Sources/SettingsKit Tests/LedgeSettingsTests Tests/SettingsKitTests
git commit -m "add the github switches, off until connected with every moment on, and a preview scene for each moment

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log -1 --stat
```

---

### Task 6: The app connects, tells, and keeps it off the lock screen

**Files:** Modify `Sources/Ledge/AppModel.swift`.

**Interfaces — Consumes:** everything above.
**Produces (for Task 7):** on `AppModel`: `githubStatus: GitHubMonitor.Status`, `githubLogin: String?`, `githubSource: GitHubTokenSource?`, `githubNeedsToken: Bool`, `githubHidesOrganisations: Bool`, `githubNeedsAttention: Bool`, `connectGitHub()`, `disconnectGitHub()`, `saveGitHubToken(_:)`, `checkGitHubNow()`.

The app target cannot be unit tested; this task is checked by `make build`, the full suite, and the live probe the controller runs afterwards.

- [ ] **Step 1: Imports.** Add `import GitHubService` beside the file's other module imports.

- [ ] **Step 2: The state and the actions.** After the `// MARK: - Updates (2026-10-22)` section (after `showPendingUpdate()`), add:

```swift
    // MARK: - GitHub (2026-10-22)

    private let github = GitHubMonitor()
    private var githubClock = RunningClock()
    private var githubRunShown: ActivityRecord?
    private var githubPanelShown: GitHubPanelData?
    private var githubWasLocked = false
    /// What happened while the screen was locked: one blip after unlock.
    private var githubMissed: [GitHubEvent] = []
    private var githubConnecting: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    /// The debug probe's made-up rounds stand in for GitHub's while it plays.
    private var githubProbeSnapshot: GitHubSnapshot?
    private static let githubKeychain = GitHubKeychain(service: "\(Bundle.main.bundleIdentifier ?? "Ledge").github")

    /// Where the login came from, once connected.
    private(set) var githubSource: GitHubTokenSource?
    /// Connected in Settings, but there is neither a pasted token nor `gh`.
    private(set) var githubNeedsToken = false
    var githubStatus: GitHubMonitor.Status { github.status }
    var githubLogin: String? { github.snapshot?.login }
    var githubHidesOrganisations: Bool { github.snapshot?.hidesSomeOrganisations ?? false }
    /// The sidebar badge: GitHub no longer takes the login.
    var githubNeedsAttention: Bool { github.status == .signInAgain }

    private var githubSnapshot: GitHubSnapshot? { githubProbeSnapshot ?? github.snapshot }

    func connectGitHub() {
        githubNeedsToken = false
        if settings.githubConnected { startGitHub() } else { settings.githubConnected = true }
    }

    /// Stops asking, and forgets a pasted token.
    func disconnectGitHub() {
        Self.githubKeychain.delete()
        settings.githubConnected = false
    }

    /// A token pasted in Settings: kept in the Keychain, then used.
    func saveGitHubToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Self.githubKeychain.save(trimmed) else { return }
        connectGitHub()
    }

    /// Settings' Check now, or Try again after GitHub refused the login
    /// (which reads the login again: the user may have signed in anew).
    func checkGitHubNow() {
        if github.status == .signInAgain || githubNeedsToken || !github.isRunning { startGitHub() } else { github.checkNow() }
    }

    /// A pasted token wins over `gh`'s: pasting one is the user choosing it.
    private func startGitHub() {
        githubConnecting?.cancel()
        githubNeedsToken = false
        githubConnecting = Task { @MainActor [weak self] in
            let pasted = Self.githubKeychain.read()
            let fromGH = pasted == nil ? await GitHubToken.fromGH() : nil
            guard let self, !Task.isCancelled, self.settings.githubConnected else { return }
            self.githubConnecting = nil
            guard let token = pasted ?? fromGH else {
                self.githubNeedsToken = true
                return
            }
            self.githubSource = pasted != nil ? .keychain : .gh
            self.github.onRound = { [weak self] snapshot, events in self?.handleGitHubRound(snapshot, events) }
            self.github.start(GitHubClient(token: token, userAgent: "Ledge/\(Self.runningVersion)"))
        }
    }

    private func stopGitHub() {
        githubConnecting?.cancel()
        githubConnecting = nil
        github.stop()
        githubSource = nil
        githubNeedsToken = false
        githubMissed = []
        githubClock = RunningClock()
        githubRunShown = nil
        queue.remove(kind: .githubRun)
        queue.remove(kind: .github)
        publish()
        publishGitHubPanel()
    }

    private func handleGitHubRound(_ snapshot: GitHubSnapshot, _ events: [GitHubEvent]) {
        let wanted = events.filter(isWanted)
        if presenter.isLocked {
            githubMissed += wanted
        } else if let blip = GitHubNotice.burst(wanted) {
            showGitHub(blip)
        }
        publishGitHubPanel()
    }

    private func isWanted(_ event: GitHubEvent) -> Bool {
        switch event {
        case .checksPassed, .checksFailed: return settings.githubChecksFinished
        case .reviewed, .commented:        return settings.githubReviews
        case .merged, .closed:             return settings.githubMerges
        case .reviewRequested:             return settings.githubReviewRequests
        case .runPassed, .runFailed:       return settings.githubMyRuns
        }
    }

    private func showGitHub(_ blip: GitHubBlip) {
        queue.insert(ActivityRecord(
            id: NotchController.githubActivityID, kind: .github, insertedAt: Date(),
            ttl: ActivityKind.github.defaultTTL, title: blip.title, compactText: blip.word,
            symbolName: blip.symbolName, tint: blip.tintName.map { .system($0) }, url: blip.url
        ))
        publish()
        showCaption(blip.caption, for: ActivityKind.github.defaultTTL ?? NotchController.captionDuration)
    }

    /// Every tick: what was missed while locked, the running item's clock,
    /// and the lock screen rule (no GitHub there at all).
    private func refreshGitHub() {
        let locked = presenter.isLocked
        if !locked, !githubMissed.isEmpty {
            let missed = githubMissed
            githubMissed = []
            if let blip = GitHubNotice.burst(missed) { showGitHub(blip) }
        }
        if locked, queue.ordered.contains(where: { $0.kind == .github }) {
            queue.remove(kind: .github)
            publish()
        }
        let now = Date()
        let running = locked ? [] : (githubSnapshot.map(GitHubEvents.running(in:)) ?? []).filter {
            $0.source == .checks ? settings.githubChecksRunning : settings.githubMyRuns
        }
        if let lead = githubClock.lead(of: running, now: now) {
            let record = ActivityRecord(
                id: NotchController.githubRunActivityID, kind: .githubRun,
                insertedAt: githubRunShown?.insertedAt ?? now, ttl: nil,
                title: lead.item.source == .run ? "Run going" : "Checks running", detail: lead.item.caption,
                compactText: TimerText.format(seconds: now.timeIntervalSince(lead.since).rounded(.down)),
                tint: .system(GitHubNotice.runningTintName), url: lead.item.url,
                badge: lead.count > 1 ? lead.count : nil
            )
            // Republished only when what the island draws changes.
            if record.compactText != githubRunShown?.compactText || record.badge != githubRunShown?.badge
                || record.url != githubRunShown?.url {
                githubRunShown = record
                queue.insert(record)
                publish()
            }
        } else if githubRunShown != nil {
            githubRunShown = nil
            queue.remove(kind: .githubRun)
            publish()
        }
        if locked != githubWasLocked {
            githubWasLocked = locked
            publishGitHubPanel()
        }
    }

    /// The panel's list, or none: not connected, nothing to list, or locked.
    private func publishGitHubPanel() {
        var data: GitHubPanelData?
        if !presenter.isLocked, let snapshot = githubSnapshot {
            let list = GitHubPanelRows.make(snapshot)
            if !list.rows.isEmpty {
                data = GitHubPanelData(
                    rows: list.rows.map { GitHubPanelData.Row(id: $0.id, mark: Self.panelMark($0.mark), title: $0.title, repo: $0.repo, url: $0.url) },
                    more: list.more, moreURL: GitHubPanelRows.moreURL
                )
            }
        }
        guard data != githubPanelShown else { return }
        githubPanelShown = data
        presenter.setGitHubPanel(data)
    }

    private static func panelMark(_ mark: GitHubRow.Mark) -> GitHubPanelData.Row.Mark {
        switch mark {
        case .running: .running
        case .passed:  .passed
        case .failed:  .failed
        case .none:    .none
        case .review:  .review
        }
    }

    #if DEBUG
    /// `ledge://probe/github`, debug builds only (2026-10-22): plays
    /// `GitHubSample.story` through the island a step every three seconds,
    /// as real rounds would land, with no network; the last step stays half
    /// a minute so the panel can be hovered.
    private func playGitHubStory() {
        let story = GitHubSample.story(login: "you", start: Date())
        Task { @MainActor [weak self] in
            var previous: GitHubSnapshot?
            for snapshot in story {
                guard let self else { return }
                self.githubProbeSnapshot = snapshot
                self.handleGitHubRound(snapshot, GitHubEvents.between(previous, snapshot))
                previous = snapshot
                try? await Task.sleep(for: .seconds(3))
            }
            try? await Task.sleep(for: .seconds(30))
            self?.githubProbeSnapshot = nil
            self?.publishGitHubPanel()
        }
    }
    #endif
```

- [ ] **Step 3: Wiring.**
  1. In `start()`, in the 0.25 s timer's `MainActor.assumeIsolated` block, after `self?.showPendingUpdate()` add `self?.refreshGitHub()`.
  2. In `start()`, after `updateTimers = [firstCheck, daily]` add:
     ```swift
             // GitHub asks at once on wake (2026-10-22).
             wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
                 forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
             ) { [weak self] _ in
                 MainActor.assumeIsolated { self?.github.checkNow() }
             }
     ```
  3. In `stop()`, after `checkTask = nil` add:
     ```swift
             if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
             wakeObserver = nil
             githubConnecting?.cancel()
             githubConnecting = nil
             github.stop()
     ```
  4. In `applySettings()`, at the end add:
     ```swift
             // GitHub (2026-10-22): connect when switched on, stop when off;
             // a switch for a moment applies from the next round, and at once
             // to the running item and the panel.
             if settings.githubConnected {
                 if !github.isRunning, githubConnecting == nil, !githubNeedsToken { startGitHub() }
             } else if github.isRunning || githubConnecting != nil || githubNeedsToken {
                 stopGitHub()
             }
             publishGitHubPanel()
     ```
  5. In `publish()`, in the `NotchController.ActivityDisplay(...)` call, after `lines: record.lines` add `, badge: record.badge` (so the line reads `lines: record.lines,` then `badge: record.badge`).
  6. In `previewContent()`, add `pullRequest: githubSnapshot?.mine.first` as the last argument of the `PreviewContent(...)` it builds.
  7. In the media handler, change `if settings.showsSongCaption, !presenter.controller.isCalendarLeading, !presenter.controller.isUpdateLeading {` to `if settings.showsSongCaption, !presenter.controller.isCalendarLeading, !presenter.controller.isUpdateLeading, !presenter.controller.isGitHubLeading {`.
  8. In `openURL(_:)`, next to the existing `/update` probe, add (inside the same `#if DEBUG` region the other probes use, or wrapped in its own `#if DEBUG … #endif`):
     ```swift
             if url.scheme == "ledge", url.host() == "probe", url.path() == "/github" {
                 Self.log.notice("probe: github story")
                 playGitHubStory()
                 return
             }
     ```

- [ ] **Step 4: Build and test.** `make build` → builds with no new warnings in `AppModel.swift`. `make test` → only the two known failures.

- [ ] **Step 5: Commit.**

```bash
git add Sources/Ledge/AppModel.swift
git commit -m "connect to github with a pasted token or gh's, show each round as one blip and the running item, list it all in the panel, and keep it off the lock screen

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log -1 --stat
```

---

### Task 7: The GitHub pane, and the docs

**Files:** Create `Sources/Ledge/GitHubSettings.swift`; modify `Sources/Ledge/SettingsWindow.swift`, `Sources/Ledge/SettingsPanes.swift`, `README.md`, `docs/superpowers/specs/2026-09-25-notch-companion-design.md`, `docs/manual-checks.md`.

**Interfaces — Consumes:** Task 6's `AppModel` members; Task 5's settings and scenes.

- [ ] **Step 1: Share the toggle.** In `Sources/Ledge/SettingsPanes.swift`, change `private func playing(` (preceded by `@MainActor`) to `func playing(`, so the new pane can use it.

- [ ] **Step 2: The pane.** Create `Sources/Ledge/GitHubSettings.swift`:

```swift
import AppKit
import SwiftUI
import GitHubService
import LedgeSettings
import SettingsKit

/// Settings › GitHub (2026-10-22): the connection, then one switch for each
/// moment the island tells, with the preview strip.
struct GitHubSettings: View {
    let settings: AppSettings
    let model: AppModel
    private var _director: State<PreviewDirector>
    private var director: PreviewDirector { _director.wrappedValue }
    private var _token: State<String>
    private var token: String {
        get { _token.wrappedValue }
        nonmutating set { _token.wrappedValue = newValue }
    }
    private var _wantsToken: State<Bool>
    private var wantsToken: Bool {
        get { _wantsToken.wrappedValue }
        nonmutating set { _wantsToken.wrappedValue = newValue }
    }

    init(settings: AppSettings, model: AppModel) {
        self.settings = settings
        self.model = model
        _director = State(initialValue: PreviewDirector(
            scenes: [.githubRunning, .githubChecks, .githubReviews, .githubMerges, .githubRequests, .githubRuns],
            isOn: { $0.isOn(in: settings) }
        ))
        _token = State(initialValue: "")
        _wantsToken = State(initialValue: false)
    }

    var body: some View {
        Form {
            Section {
                PreviewStrip(director: director, height: PreviewStrip.shortHeight) { model.previewContent() }
                    .asPaneHeader()
            }
            Section {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    GitHubConnectionRow(settings: settings, model: model, wantsToken: Binding(
                        get: { wantsToken }, set: { wantsToken = $0 }
                    ))
                }
                if model.githubNeedsToken || wantsToken {
                    SettingsRow("Token", detail: "A token with the repo and read:org scopes, from github.com › Settings › Developer settings.",
                                symbol: "key.fill", color: Color(nsColor: .systemYellow)) {
                        HStack(spacing: 8) {
                            SecureField("Token", text: Binding(get: { token }, set: { token = $0 }))
                                .labelsHidden()
                                .frame(width: 180)
                            Button("Save") {
                                model.saveGitHubToken(token)
                                token = ""
                                wantsToken = false
                            }
                            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            } header: {
                Text("Connection")
            } footer: {
                Text("While connected, Ledge asks api.github.com every minute, or every 20 seconds while something runs. Your token stays with gh or in your Keychain.")
            }
            Section {
                moment("Checks running", "An amber ring and a clock while checks run on your PRs.",
                       symbol: "circle.dotted", color: .systemYellow, \.githubChecksRunning, .githubRunning)
                moment("Checks finished", "Passed or failed, once for each commit.",
                       symbol: "checkmark.circle.fill", color: .systemGreen, \.githubChecksFinished, .githubChecks)
                moment("Reviews and comments", "Approvals, change requests and comments on your PRs, bots included.",
                       symbol: "bubble.left.fill", color: .systemOrange, \.githubReviews, .githubReviews)
                moment("Merges and closes", "When someone else merges or closes one of your PRs.",
                       symbol: "arrow.triangle.merge", color: .systemPurple, \.githubMerges, .githubMerges)
                moment("Review requests", "When someone asks for your review.",
                       symbol: "eye.fill", color: .systemBlue, \.githubReviewRequests, .githubRequests)
                moment("Your runs outside PRs", "Workflow runs you start with a push, a tag or a deploy.",
                       symbol: "play.circle.fill", color: .systemGray, \.githubMyRuns, .githubRuns)
            } header: {
                Text("Tell me when")
            }
        }
    }

    private func moment(_ title: String, _ detail: String, symbol: String, color: NSColor,
                        _ keyPath: ReferenceWritableKeyPath<AppSettings, Bool>, _ scene: PreviewScene) -> some View {
        SettingsRow(title, detail: detail, symbol: symbol, color: Color(nsColor: color), scene: scene, director: director) {
            Toggle(title, isOn: playing(keyPath, scene, settings: settings, director: director))
                .labelsHidden()
        }
    }
}

/// What the connection is doing, and the buttons for it.
struct GitHubConnectionRow: View {
    let settings: AppSettings
    let model: AppModel
    let wantsToken: Binding<Bool>

    var body: some View {
        SettingsRow(title, detail: detail, symbol: "arrow.triangle.branch", color: Color(white: 0.2)) {
            HStack(spacing: 8) {
                if !settings.githubConnected {
                    Button("Use a token") { wantsToken.wrappedValue = true }
                    Button("Connect") { model.connectGitHub() }
                } else {
                    if model.githubNeedsToken || model.githubStatus == .signInAgain {
                        Button("Try again") { model.checkGitHubNow() }
                    } else if model.githubStatus != .checking {
                        Button("Check now") { model.checkGitHubNow() }
                    }
                    Button("Disconnect") { model.disconnectGitHub() }
                }
            }
        }
    }

    private var title: String {
        guard settings.githubConnected else { return "Not connected" }
        if model.githubNeedsToken { return "No GitHub login found" }
        switch model.githubStatus {
        case .off, .checking:
            return "Connecting…"
        case .signInAgain:
            return "Sign in again"
        case .ok, .failed, .rateLimited:
            let via = model.githubSource == .gh ? "from gh" : "with a token"
            return model.githubLogin.map { "Connected as \($0) (\(via))" } ?? "Connected (\(via))"
        }
    }

    private var detail: String? {
        guard settings.githubConnected else { return "Ledge uses your gh login, or a token you paste here." }
        if model.githubNeedsToken { return "Log in with gh auth login in Terminal, or paste a token, then Try again." }
        var lines: [String] = []
        switch model.githubStatus {
        case .ok(let at): lines.append("Last checked at \(time(at)).")
        case .failed: lines.append("Could not reach GitHub just now. Ledge tries again shortly.")
        case .rateLimited(let until): lines.append("GitHub asked Ledge to wait until \(time(until)).")
        case .signInAgain: lines.append("GitHub no longer takes this login. Log in again with gh auth login, or paste a new token, then Try again.")
        case .off, .checking: break
        }
        if model.githubHidesOrganisations {
            lines.append("Some organisations hide their PRs from this token; authorise it for them on GitHub.")
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
```

- [ ] **Step 3: The sidebar.** In `Sources/Ledge/SettingsWindow.swift`:
  - in `SettingsSection`, change `case general, island, media, calendar, permissions, about` to `case general, island, media, calendar, github, permissions, about`;
  - in `title` add `case .github:      return "GitHub"`; in `symbol` add `case .github:      return "arrow.triangle.branch"`; in `tile` add `case .github:      return Color(white: 0.2)`;
  - replace `.badge(section == .permissions ? issueCount : (section == .about && model.hasUpdate ? 1 : 0))` with `.badge(badge(for: section, issues: issueCount))`, and add to the same view:
    ```swift
        /// Permissions count what is missing; About an update; GitHub a
        /// login it no longer takes (2026-10-22).
        private func badge(for section: SettingsSection, issues: Int) -> Int {
            switch section {
            case .permissions: return issues
            case .about:       return model.hasUpdate ? 1 : 0
            case .github:      return model.githubNeedsAttention ? 1 : 0
            default:           return 0
            }
        }
    ```
  - in the detail `switch`, after `case .calendar:` add `case .github:      GitHubSettings(settings: settings, model: model)`.

- [ ] **Step 4: The README.** In `README.md`:
  - after the Install paragraph that begins "Once a day Ledge asks GitHub whether a newer version is out", add a new paragraph:
    `Connecting GitHub in Settings › GitHub adds one more kind of request: while connected, Ledge asks api.github.com about your own PRs and runs every minute, or every 20 seconds while something runs. Until you connect, it asks nothing.`
  - in the "What it shows" table, after the Clock timer row, add:
    `| GitHub, once connected in Settings › GitHub | checks running on your PRs: an amber ring and a clock; checks passed or failed, a review, a comment, a merge, a review request, or a run of yours finishing: a blip, with what and where under the hole; click to open it on GitHub. Hover for the list of your PRs. Never on the lock screen |`
  - in the Settings paragraph, change `Permissions (each grant, what it` to `GitHub (connect with your gh login or a token, and which moments the island tells you about), Permissions (each grant, what it`.

- [ ] **Step 5: The specs and the manual checks.** Append to `docs/superpowers/specs/2026-09-25-notch-companion-design.md`:

```markdown

## GitHub on the island (2026-10-22)

**What.** Once the user connects GitHub (Settings › GitHub; off by default),
the island tells them about their own work across all their repos: checks
running on their PRs (a sticky amber ring and a clock, `ActivityKind.githubRun`,
priority 18), and as a blip (`ActivityKind.github`, priority 38, 8 s) checks
passing or failing, reviews, comments, merges and closes by someone else, review
requests, and runs they started outside a PR finishing. A round's news is one
blip, the most important with "+N more". The open island has a GitHub panel.
Nothing GitHub shows on the lock screen; what was missed shows once after
unlock. Full design: `2026-10-22-github-island-design.md`.

**How.** `GitHubService`: one GraphQL query a round plus the user's runs in
repos pushed to today (ETags), compared with the last good round; every 60 s,
every 20 s while something runs, backing off on failure. The login is a pasted
token from the Keychain, else `gh auth token`. This lifts the "one network
request" line: a second destination, only while connected.
```

Append to `docs/manual-checks.md`:

```markdown

## GitHub on the island (2026-10-22)

Pending until the user reports them:

1. Settings › GitHub › Connect with `gh` logged in: "Connected as <login> (from gh)" within a few seconds, then "Last checked at".
2. A push to a PR of the user's: the amber ring and clock while checks run; a green or red blip when they finish; a click opens the PR or the failed check.
3. A review or comment from someone else (a bot counts): the blip, its caption, the link.
4. Hovering the running item opens the GitHub panel; a swipe on the empty peek does too; rows open on GitHub.
5. Locked while something lands: nothing on the lock screen; one blip after unlock.
6. Disconnect: the ring, blip and panel go, and no further requests.
7. A pasted token (with `gh` logged out): connects "with a token"; a revoked token shows "Sign in again" and the sidebar badge.
```

- [ ] **Step 6: Build and test.** `make build` → builds. `make test` → only the two known failures.

- [ ] **Step 7: Commit.**

```bash
git add Sources/Ledge/GitHubSettings.swift Sources/Ledge/SettingsWindow.swift Sources/Ledge/SettingsPanes.swift README.md docs/superpowers/specs/2026-09-25-notch-companion-design.md docs/manual-checks.md
git commit -m "add a github pane to settings with the connection and a switch for each moment, and describe it in the readme and the specs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log -1 --stat
```

---

## After the tasks (controller)

1. Whole-branch review, then fixes.
2. Live, on a debug build (`make dev`): `open -a "$PWD/dist/Ledge.app" "ledge://probe/github"` and capture the island at each step (running, failed, comment, approved, merged, review requested), then hover for the panel. Then connect for real in Settings › GitHub and check this repo's PRs show.
3. Put the installed copy back: `make stop; open /Applications/Ledge.app`.
4. Push the branch and open the PR; merge only when the user says merge.
