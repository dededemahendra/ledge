# GitHub on the Island: Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make GitHub on the island look finished: a hero card in the panel, a segmented check ring, avatars and colour discs on the blips, and an account card in Settings.

**Architecture:** `GitHubService` learns each check's state (segments) and people's avatar addresses, fetches avatars through a new `GitHubAvatars` store, picks the panel's hero, and words the new captions. `ActivityKit`/`NotchKit` carry segments and the hero to new views (`CheckRing`, `SegmentBar`, `GitHubBlipGlyph`, the hero card) and bold captions up to their first separator. `AppModel` loads avatars and passes everything through; Settings gets the account and welcome cards.

**Tech Stack:** Swift 6.4, Swift 6 language mode, SwiftPM only, swift-testing, SwiftUI with AppKit, macOS 27.

**Spec:** `docs/superpowers/specs/2026-10-22-github-island-polish-design.md` (polishing `docs/superpowers/specs/2026-10-22-github-island-design.md`).

## Global Constraints

- Branch `github-island` (the open PR); commit on it, never on main.
- Avatars only from `https://*.githubusercontent.com`, with no token and no cookies, only while connected; at most 64 kept in memory, none on disk. A blip waits at most 1 s for its avatar, then shows its disc.
- Segments: passed (CheckRun COMPLETED with SUCCESS, NEUTRAL, SKIPPED or STALE; StatusContext SUCCESS), failed (CheckRun FAILURE, TIMED_OUT, STARTUP_FAILURE, CANCELLED, ACTION_REQUIRED; StatusContext FAILURE, ERROR), running (anything else); ordered passed, failed, running. Past 12 segments, draw one smooth fill (fraction done; red once any failed).
- Hero order: running (earliest start, nil last) > failed > review requested > none. Under a hero 2 rows; alone 5 rows, or 4 and "N more on GitHub".
- Captions: `<title> · <who or what> · <repo>`, missing parts left out, title shortened past 40 characters; the island bolds a caption up to its FIRST " · ".
- Disc glyphs: passed/approved `checkmark`, failed `xmark`, changes `exclamationmark`, comment `bubble.left.fill`, merged `arrow.triangle.merge`, closed `xmark`, review `eye.fill`. Tints as before (green, red, orange, none, purple, gray, blue).
- Run tests with `make test` / `make test FILTER=<name>`; never bare `swift test`. Only `brightnessTargetsTheBuiltInDisplay` and `bridgeLoadsAndReadsARealBrightnessValue` may fail. `make build` builds without launching; `make build CONF=release` builds release.
- `@State` cannot be used as a macro: spelled-out `State` as elsewhere.
- Text people read: Australian English, no em or en dashes, no exclamation marks, sentence case.
- Comments: plain sentences, dated `(2026-10-22)`. Commits: one lowercase sentence, blank line, `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; `git add` only the task's files, never `.superpowers`; confirm with `git log -1 --stat`.
- Implementers do not launch, install or stop the app, call GitHub, run `gh` or touch the Keychain.

## Review Focus

1. A check state GitHub adds later (an unknown conclusion): counts as running, not a crash (Task 1, `checksAreSegmentedFinishedFirst` covers unknowns via QUEUED and the default branch).
2. An avatar address on another host: refused unasked (Task 1, `avatarsComeOnlyFromGitHubsImageServerWithNoToken`).
3. A PR with no checks running but checks finished long ago: no stale hero clock (Task 2: `startedAt` only for running heroes, `theHeroIsWhatIsMostWorthWatching`).
4. A song title with " · " in it: bolded only up to the first separator, which reads fine (Task 3, `aCaptionIsBoldUpToItsFirstSeparator` pins the width maths both draw from).
5. A blip whose avatar never loads: shows the disc after one second (Task 4; checked live, the probe has no avatars).

---

### Task 1: Segments, avatar addresses and the avatar store

**Files:** Modify `Sources/GitHubService/GitHubModels.swift`, `GitHubQuery.swift`, `GitHubClient.swift`, `Tests/GitHubServiceTests/Fixtures.swift`, `Tests/GitHubServiceTests/GitHubClientTests.swift`; create `Sources/GitHubService/GitHubAvatars.swift`.

**Interfaces — Produces:** `public enum CheckSegment: String { passed, failed, running }`; `GitHubChecks.segments: [CheckSegment]` (init param `segments: [CheckSegment] = []`, last); `GitHubReview.avatarURL`, `GitHubComment.avatarURL` (init param `avatarURL: URL? = nil`, last); `GitHubPR.authorAvatarURL` (init param `authorAvatarURL: URL? = nil`, right after `author`); `GitHubDeparture.byAvatarURL` (init param `byAvatarURL: URL? = nil`, last); `GitHubSnapshot.avatarURL` (init param `avatarURL: URL? = nil`, last); `public actor GitHubAvatars` (`static let limit = 64`, `init(fetch: GitHubClient.Fetch = GitHubClient.session)`, `func image(at: URL) async -> Data?`).

- [ ] **Step 1: Fixtures.** In `Tests/GitHubServiceTests/Fixtures.swift`, in `mineReply`: change `"me":{"login":"dede","repositories"` to `"me":{"login":"dede","avatarUrl":"https://avatars.githubusercontent.com/u/1?v=4","repositories"`; change both `"author":{"login":"coderabbitai"}` to `"author":{"login":"coderabbitai","avatarUrl":"https://avatars.githubusercontent.com/in/347564?v=4"}`; change `"author":{"login":"gede"}` to `"author":{"login":"gede","avatarUrl":"https://avatars.githubusercontent.com/u/2?v=4"}`. In `departuresReply`, change `"mergedBy":{"login":"octocat"}` to `"mergedBy":{"login":"octocat","avatarUrl":"https://avatars.githubusercontent.com/u/583231?v=4"}`.

- [ ] **Step 2: Failing tests.** In `Tests/GitHubServiceTests/GitHubClientTests.swift`:
  - in `aRoundReadsTheUsersPRsChecksReviewsAndRuns`, change the `failed.reviews == [GitHubReview(...)]` expectation's `GitHubReview(...)` to add `avatarURL: URL(string: "https://avatars.githubusercontent.com/in/347564?v=4")` after its `url:` argument, and add before its last line:
    ```swift
        #expect(failed.checks?.segments == [.passed, .failed])
        #expect(running.checks?.segments == [.running, .running])
        #expect(snapshot.avatarURL?.absoluteString == "https://avatars.githubusercontent.com/u/1?v=4")
        #expect(failed.comments.first?.avatarURL != nil && failed.comments.last?.avatarURL == nil, "a deleted account has no picture")
        #expect(snapshot.requested.first?.authorAvatarURL?.absoluteString == "https://avatars.githubusercontent.com/u/2?v=4")
    ```
  - in `aPRThatLeftTheListIsLookedUp`, change the expectation to `#expect(snapshot.departed == [GitHubDeparture(pr: gone, merged: true, by: "octocat", byAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/583231?v=4"))])`;
  - append:
    ```swift
    /// Review Focus 1.
    @Test func checksAreSegmentedFinishedFirst() throws {
        let rollup = try JSONDecoder().decode(GitHubQuery.Wire.Rollup.self, from: Data(#"""
        {"state":"PENDING","contexts":{"nodes":[
          {"__typename":"CheckRun","name":"a","status":"IN_PROGRESS","conclusion":null},
          {"__typename":"StatusContext","context":"b","state":"ERROR"},
          {"__typename":"CheckRun","name":"c","status":"COMPLETED","conclusion":"SKIPPED"},
          {"__typename":"CheckRun","name":"d","status":"COMPLETED","conclusion":"CANCELLED"},
          {"__typename":"StatusContext","context":"e","state":"SUCCESS"},
          {"__typename":"CheckRun","name":"f","status":"QUEUED","conclusion":null}]}}
        """#.utf8))
        #expect(GitHubQuery.checks(rollup)?.segments == [.passed, .passed, .failed, .failed, .running, .running])
    }

    /// Review Focus 2.
    @Test func avatarsComeOnlyFromGitHubsImageServerWithNoToken() async {
        let seen = Seen()
        let avatars = GitHubAvatars(fetch: fetch(seen) { _ in (200, [:], "PNG") })
        let url = URL(string: "https://avatars.githubusercontent.com/u/1?v=4")!
        #expect(await avatars.image(at: url) == Data("PNG".utf8))
        #expect(await avatars.image(at: url) == Data("PNG".utf8))
        #expect(seen.all.count == 1, "the second comes from memory")
        #expect(seen.all.first?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(await avatars.image(at: URL(string: "https://example.com/me.png")!) == nil)
        #expect(seen.all.count == 1, "nothing is asked of anywhere else")
        let broken = GitHubAvatars(fetch: fetch { _ in (404, [:], "") })
        #expect(await broken.image(at: url) == nil)
    }

    @Test func avatarsKeepOnlyTheLast64() async {
        let seen = Seen()
        let avatars = GitHubAvatars(fetch: fetch(seen) { _ in (200, [:], "PNG") })
        for n in 0...GitHubAvatars.limit {
            _ = await avatars.image(at: URL(string: "https://avatars.githubusercontent.com/u/\(n)")!)
        }
        _ = await avatars.image(at: URL(string: "https://avatars.githubusercontent.com/u/0")!)
        #expect(seen.all.count == GitHubAvatars.limit + 2, "the first was dropped, so it is asked for again")
    }
    ```

- [ ] **Step 3: Run them to see them fail.** `make test FILTER=GitHubServiceTests` → does not build.

- [ ] **Step 4: The values.** In `Sources/GitHubService/GitHubModels.swift`:
  - after `enum CheckState`, add:
    ```swift
    /// One check's state on a PR's latest commit (2026-10-22): a segment of
    /// the island's ring and the panel's bar.
    public enum CheckSegment: String, Sendable, Equatable {
        case passed, failed, running
    }
    ```
  - `GitHubChecks`: add `/// Every check, finished first: passed, failed, then still going (2026-10-22).` and `public let segments: [CheckSegment]`; init param `segments: [CheckSegment] = []` last; assign it.
  - `GitHubReview` and `GitHubComment`: add `/// Their picture on GitHub's image server (2026-10-22).` and `public let avatarURL: URL?`; init param `avatarURL: URL? = nil` last; assign it.
  - `GitHubPR`: add `public let authorAvatarURL: URL?` after `author` (doc: `/// The author's picture (2026-10-22).`); init param `authorAvatarURL: URL? = nil` right after `author: String? = nil`; assign it.
  - `GitHubDeparture`: add `public let byAvatarURL: URL?` (doc: `/// Their picture (2026-10-22).`); init param `byAvatarURL: URL? = nil` last; assign it.
  - `GitHubSnapshot`: add `public let avatarURL: URL?` (doc: `/// The user's own picture, for Settings (2026-10-22).`); init param `avatarURL: URL? = nil` last; assign it.

- [ ] **Step 5: The query.** In `Sources/GitHubService/GitHubQuery.swift`:
  - in `text`: `me: viewer {` is followed by `login`; make that line `login avatarUrl(size: 96)`. Replace every `author { login }` (three: the PR's, reviews', comments') with `author { login avatarUrl(size: 64) }`.
  - in `departuresText`: `mergedBy { login }` → `mergedBy { login avatarUrl(size: 64) }`; `actor { login }` → `actor { login avatarUrl(size: 64) }`.
  - `Answer`: add `let avatarURL: URL?`; in `decode`, pass `avatarURL: me.avatarUrl.flatMap(URL.init(string:))`.
  - `Outcome`: add `let byAvatarURL: URL?`; in `decodeDepartures`, `Outcome(merged: true, by: node.mergedBy?.login, byAvatarURL: node.mergedBy?.avatarUrl.flatMap(URL.init(string:)))` and for CLOSED take the last actor once (`let actor = node.timelineItems?.nodes?.compactMap { $0 }.last?.actor`) and use `Outcome(merged: false, by: actor?.login, byAvatarURL: actor?.avatarUrl.flatMap(URL.init(string:)))`.
  - `Wire.Login`: `struct Login: Decodable { let login: String?; let avatarUrl: String? }`; `Wire.Me`: `struct Me: Decodable { let login: String; let avatarUrl: String?; let repositories: Nodes<Repo>? }`.
  - `Wire.PR.pr`: pass `authorAvatarURL: author?.avatarUrl.flatMap(URL.init(string:))` after `author:`; reviews and comments pass `avatarURL: review.author?.avatarUrl.flatMap(URL.init(string:))` / `avatarURL: comment.author?.avatarUrl.flatMap(URL.init(string:))`.
  - in `checks(_:)`, before the `return`, add:
    ```swift
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
    ```
    and pass `segments: segments.filter { $0 == .passed } + segments.filter { $0 == .failed } + segments.filter { $0 == .running }` as the last argument of the returned `GitHubChecks(...)`.

- [ ] **Step 6: The client.** In `Sources/GitHubService/GitHubClient.swift`: the departures map becomes `GitHubDeparture(pr: pr, merged: $0.merged, by: $0.by, byAvatarURL: $0.byAvatarURL)`; the returned `GitHubSnapshot(...)` gets `avatarURL: answer.avatarURL` as its last argument.

- [ ] **Step 7: The avatar store.** Create `Sources/GitHubService/GitHubAvatars.swift`:

```swift
import Foundation

/// People's pictures for the island and Settings (2026-10-22): fetched from
/// GitHub's image server with no token and no cookies, the last 64 kept in
/// memory, none on disk. An address anywhere else is refused unasked.
public actor GitHubAvatars {
    public static let limit = 64

    private let fetch: GitHubClient.Fetch
    private var cache: [URL: Data] = [:]
    private var order: [URL] = []

    public init(fetch: @escaping GitHubClient.Fetch = GitHubClient.session) {
        self.fetch = fetch
    }

    /// The picture at `url`, from memory or GitHub's image server; `nil`
    /// when it cannot be had.
    public func image(at url: URL) async -> Data? {
        if let data = cache[url] { return data }
        guard url.scheme == "https", url.host()?.hasSuffix(".githubusercontent.com") == true else { return nil }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        guard let (data, response) = try? await fetch(request),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        if cache[url] == nil { order.append(url) }
        cache[url] = data
        if order.count > Self.limit { cache[order.removeFirst()] = nil }
        return data
    }
}
```

- [ ] **Step 8: Run the tests.** `make test FILTER=GitHubServiceTests` → all pass. `make build`.

- [ ] **Step 9: Commit.**

```bash
git add Sources/GitHubService Tests/GitHubServiceTests
git commit -m "read each check's state and people's pictures from github, and fetch the pictures only from github's image server

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log -1 --stat
```

---

### Task 2: The hero, the new captions and the glyphs

**Files:** Modify `Sources/GitHubService/GitHubEvents.swift`, `GitHubNotice.swift`, `GitHubPanelRows.swift`, `GitHubSample.swift`, `Tests/GitHubServiceTests/GitHubEventsTests.swift`.

**Interfaces — Consumes:** Task 1's values. **Produces:** `GitHubEvent.merged(GitHubDeparture)`, `.closed(GitHubDeparture)`; `GitHubRunning.segments: [CheckSegment]` (init param `segments: [CheckSegment] = []`, last); `GitHubBlip.avatarURL: URL?` (last memberwise field); `public struct GitHubHero` (`enum Kind { running, failed, review }`, `id`, `kind`, `tag`, `title`, `detail`, `segments`, `startedAt: Date?`, `avatarURL: URL?`, `url`); `GitHubPanelList.hero: GitHubHero?`; `GitHubPanelRows.rowsUnderHero = 2`, `rowsAlone = 5`; `GitHubSample.panelSnapshot(login:now:) -> GitHubSnapshot`.

- [ ] **Step 1: Failing tests.** In `Tests/GitHubServiceTests/GitHubEventsTests.swift`:
  - replace the `pr(...)` helper with:
    ```swift
    private func pr(_ id: String = "PR_1", number: Int = 4, sha: String = "aaa", checks: CheckState? = nil, failed: String? = nil,
                    segments: [CheckSegment] = [], started: Date? = nil,
                    reviews: [GitHubReview] = [], comments: [GitHubComment] = []) -> GitHubPR {
        GitHubPR(id: id, number: number, title: "update notice", url: URL(string: "https://github.com/dede/ledge/pull/\(number)")!,
                 repo: "ledge", author: "dede", headSHA: sha,
                 checks: checks.map { GitHubChecks(state: $0, startedAt: started, failedName: failed, segments: segments) },
                 reviews: reviews, comments: comments)
    }
    ```
  - in `mergesAndClosesBySomeoneElseAreNews`, the expectation becomes `#expect(GitHubEvents.between(open, after) == [.merged(after.departed[0]), .closed(after.departed[1])])`;
  - in `whatIsRunningNow`, append `#expect(GitHubEvents.running(in: snap(0, mine: [pr(checks: .pending, segments: [.passed, .running])])).first?.segments == [.passed, .running])`;
  - replace `eachEventHasItsLook` with:
    ```swift
    @Test func eachEventHasItsLook() {
        let p = pr(checks: .failed, failed: "test (macos)")
        #expect(GitHubNotice.blip(for: .checksFailed(p)) == GitHubBlip(
            title: "Checks failed", symbolName: "xmark", word: "Failed", tintName: "red",
            caption: "update notice · test (macos) · ledge", url: p.url, avatarURL: nil))
        #expect(GitHubNotice.blip(for: .checksPassed(p)).caption == "update notice · ledge")
        #expect(GitHubNotice.blip(for: .checksPassed(p)).symbolName == "checkmark")
        let face = URL(string: "https://avatars.githubusercontent.com/u/9")!
        let approved = GitHubNotice.blip(for: .reviewed(p, GitHubReview(id: "R1", author: "coderabbitai", state: .approved,
                                                                      at: nil, url: nil, avatarURL: face)))
        #expect(approved.caption == "update notice · coderabbitai · ledge" && approved.word == "Approved")
        #expect(approved.symbolName == "checkmark" && approved.avatarURL == face)
        let changes = GitHubNotice.blip(for: .reviewed(p, review("R2", "sam", .changesRequested)))
        #expect(changes.word == "Changes" && changes.tintName == "orange" && changes.symbolName == "exclamationmark")
        let said = GitHubNotice.blip(for: .commented(p, comment("C1", "sam")))
        #expect(said.word == "Comment" && said.tintName == nil && said.symbolName == "bubble.left.fill")
        let merged = GitHubNotice.blip(for: .merged(GitHubDeparture(pr: p, merged: true, by: "sam", byAvatarURL: face)))
        #expect(merged.symbolName == "arrow.triangle.merge" && merged.tintName == "purple" && merged.avatarURL == face)
        #expect(merged.caption == "update notice · sam · ledge")
        #expect(GitHubNotice.blip(for: .closed(GitHubDeparture(pr: p, merged: false, by: nil))).caption == "update notice · ledge")
        let asked = GitHubNotice.blip(for: .reviewRequested(pr("PR_9", number: 12)))
        #expect(asked.caption == "update notice · dede · ledge" && asked.word == "Review")
        #expect(asked.tintName == "blue" && asked.symbolName == "eye.fill")
        #expect(GitHubNotice.blip(for: .runFailed(run(1, .failed))).caption == "Deploy · web")
        #expect(GitHubNotice.blip(for: .runPassed(run(1, .passed))).symbolName == "checkmark")
    }
    ```
  - in `aBurstIsOneBlip`, the caption expectation becomes `#expect(blip?.caption == "update notice · sam · ledge · +2 more")` and the single one `#expect(GitHubNotice.burst([.checksPassed(p)])?.caption == "update notice · ledge")`;
  - in `aLongTitleIsShortenedInTheCaption`, the expectation becomes `#expect(GitHubNotice.blip(for: .merged(GitHubDeparture(pr: long, merged: true, by: nil))).caption == String(repeating: "a", count: 39) + "… · ledge")`;
  - replace `thePanelListsRunsThenPRsThenRequests` with:
    ```swift
    /// Review Focus 3.
    @Test func theHeroIsWhatIsMostWorthWatching() {
        let s = snap(0, mine: [pr("PR_1", number: 4, checks: .passed),
                               pr("PR_2", number: 5, checks: .failed, failed: "test (macos)"),
                               pr("PR_3", number: 6, sha: "ccc", checks: .pending, segments: [.passed, .failed, .running, .running],
                                  started: t0.addingTimeInterval(60))],
                     requested: [pr("PR_9", number: 12)])
        let list = GitHubPanelRows.make(s)
        #expect(list.hero?.kind == .running && list.hero?.id == "PR_3" && list.hero?.tag == "Checks running")
        #expect(list.hero?.detail == "ledge #6 · 2 of 4 checks · 1 failed")
        #expect(list.hero?.segments == [.passed, .failed, .running, .running])
        #expect(list.hero?.startedAt == t0.addingTimeInterval(60))
        #expect(list.rows.map(\.id) == ["PR_2", "PR_1"], "two rows under the hero, failed first")
        #expect(list.more == 1, "the review request did not fit")

        let failed = GitHubPanelRows.make(snap(0, mine: [pr("PR_1", number: 4, checks: .passed),
                                                        pr("PR_2", number: 5, checks: .failed, failed: "test (macos)")]))
        #expect(failed.hero?.kind == .failed && failed.hero?.detail == "ledge #5 · test (macos) failed")
        #expect(failed.hero?.startedAt == nil, "a finished hero has no clock")
        #expect(failed.rows.map(\.id) == ["PR_1"] && failed.more == 0)

        let review = GitHubPanelRows.make(snap(0, mine: [pr(checks: .passed)], requested: [pr("PR_9", number: 12)]))
        #expect(review.hero?.kind == .review && review.hero?.detail == "ledge #12 · dede asks for your review")
        #expect(review.hero?.id == "asked:PR_9" && review.rows.map(\.id) == ["PR_1"])

        let quiet = GitHubPanelRows.make(snap(0, mine: (1...7).map { pr("PR_\($0)", number: $0, checks: .passed) }))
        #expect(quiet.hero == nil && quiet.rows.count == 4 && quiet.more == 3, "alone: four rows and the rest counted")
        #expect(quiet.rows.first?.mark == .passed && quiet.rows.first?.title == "#1 update notice")
        #expect(GitHubPanelRows.make(snap(0)).hero == nil && GitHubPanelRows.make(snap(0)).rows.isEmpty)
    }

    @Test func aRunOfTheUsersCanBeTheHero() {
        let hero = GitHubPanelRows.make(snap(0, mine: [pr(checks: .passed)], runs: [run(1, .running)])).hero
        #expect(hero?.kind == .running && hero?.tag == "Run going" && hero?.detail == "web · your run")
        #expect(hero?.segments == [] && hero?.startedAt == t0.addingTimeInterval(30))
    }
    ```
  - in `theProbesStoryTellsEveryMoment`, add `#expect(GitHubPanelRows.make(GitHubSample.panelSnapshot(login: "you", now: t0)).hero?.kind == .running)`.

- [ ] **Step 2: Run them to see them fail.** `make test FILTER=GitHubServiceTests` → does not build.

- [ ] **Step 3: Events.** In `Sources/GitHubService/GitHubEvents.swift`:
  - `case merged(GitHubPR)` → `case merged(GitHubDeparture)`; `case closed(GitHubPR)` → `case closed(GitHubDeparture)` (doc above them: `/// Who merged or closed it, and their picture, ride along (2026-10-22).`);
  - in `between`, `events.append(departure.merged ? .merged(departure.pr) : .closed(departure.pr))` → `events.append(departure.merged ? .merged(departure) : .closed(departure))`;
  - `GitHubRunning`: add `public let segments: [CheckSegment]` (doc: `/// The PR's checks, for the ring; none for a run (2026-10-22).`), init param `segments: [CheckSegment] = []` last; in `running(in:)` pass `segments: state.segments` for the PR items.

- [ ] **Step 4: The look.** In `Sources/GitHubService/GitHubNotice.swift`:
  - `GitHubBlip`: add `/// Who did it, when a person did (2026-10-22).` and `public let avatarURL: URL?` as the last field;
  - replace `blip(for:)` with:
    ```swift
        /// The glyph sits on a disc in the event's colour, or as a badge on
        /// the person's avatar (2026-10-22).
        public static func blip(for event: GitHubEvent) -> GitHubBlip {
            switch event {
            case .checksPassed(let pr):
                return GitHubBlip(title: "Checks passed", symbolName: "checkmark", word: "Passed", tintName: "green",
                                  caption: caption(pr.title, pr.repo), url: pr.url, avatarURL: nil)
            case .checksFailed(let pr):
                return GitHubBlip(title: "Checks failed", symbolName: "xmark", word: "Failed", tintName: "red",
                                  caption: caption(pr.title, pr.checks?.failedName, pr.repo),
                                  url: pr.checks?.failedURL ?? pr.url, avatarURL: nil)
            case .reviewed(let pr, let review):
                let url = review.url ?? pr.url
                let by = caption(pr.title, review.author, pr.repo)
                switch review.state {
                case .approved:
                    return GitHubBlip(title: "Approved", symbolName: "checkmark", word: "Approved", tintName: "green",
                                      caption: by, url: url, avatarURL: review.avatarURL)
                case .changesRequested:
                    return GitHubBlip(title: "Changes requested", symbolName: "exclamationmark", word: "Changes",
                                      tintName: "orange", caption: by, url: url, avatarURL: review.avatarURL)
                case .commented, .other:
                    return GitHubBlip(title: "Comment", symbolName: "bubble.left.fill", word: "Comment", tintName: nil,
                                      caption: by, url: url, avatarURL: review.avatarURL)
                }
            case .commented(let pr, let comment):
                return GitHubBlip(title: "Comment", symbolName: "bubble.left.fill", word: "Comment", tintName: nil,
                                  caption: caption(pr.title, comment.author, pr.repo), url: comment.url ?? pr.url,
                                  avatarURL: comment.avatarURL)
            case .merged(let departure):
                return GitHubBlip(title: "Merged", symbolName: "arrow.triangle.merge", word: "Merged", tintName: "purple",
                                  caption: caption(departure.pr.title, departure.by, departure.pr.repo), url: departure.pr.url,
                                  avatarURL: departure.byAvatarURL)
            case .closed(let departure):
                return GitHubBlip(title: "Closed", symbolName: "xmark", word: "Closed", tintName: "gray",
                                  caption: caption(departure.pr.title, departure.by, departure.pr.repo), url: departure.pr.url,
                                  avatarURL: departure.byAvatarURL)
            case .reviewRequested(let pr):
                return GitHubBlip(title: "Review requested", symbolName: "eye.fill", word: "Review", tintName: "blue",
                                  caption: caption(pr.title, pr.author, pr.repo), url: pr.url, avatarURL: pr.authorAvatarURL)
            case .runPassed(let run):
                return GitHubBlip(title: "Run passed", symbolName: "checkmark", word: "Passed", tintName: "green",
                                  caption: caption(run.workflow, run.repo), url: run.url, avatarURL: nil)
            case .runFailed(let run):
                return GitHubBlip(title: "Run failed", symbolName: "xmark", word: "Failed", tintName: "red",
                                  caption: caption(run.workflow, run.repo), url: run.url, avatarURL: nil)
            }
        }
    ```
  - in `burst`, the rebuilt `GitHubBlip(...)` passes `avatarURL: blip.avatarURL` as its last argument;
  - add, next to `prCaption`:
    ```swift
        /// "Fix the date picker · sam · web" (2026-10-22): the title first, which
        /// the island sets in bold up to the first separator, then who or what,
        /// then where; a missing part is left out.
        static func caption(_ title: String, _ parts: String?...) -> String {
            ([short(title)] + parts.compactMap { $0 }).joined(separator: " · ")
        }
    ```
  - remove `byCaption` (now unused); keep `prCaption`, `runCaption` and `short`.

- [ ] **Step 5: The panel's list.** Replace `Sources/GitHubService/GitHubPanelRows.swift` with:

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
```

- [ ] **Step 6: The sample.** In `Sources/GitHubService/GitHubSample.swift`:
  - `pr`'s checks become `GitHubChecks(state: .failed, failedName: "test (macos)", segments: [.passed, .passed, .passed, .failed])`;
  - in `story`, the pending checks become `GitHubChecks(state: .pending, startedAt: at(1), segments: [.passed, .passed, .running, .running])` and `failed` becomes `GitHubChecks(state: .failed, failedName: "test (macos)", segments: [.passed, .passed, .passed, .failed])`;
  - add:
    ```swift
        /// A panel worth a screenshot (2026-10-22): checks running on one PR
        /// with one already failed, a failed PR, a passed one, and a review
        /// request.
        public static func panelSnapshot(login: String, now: Date) -> GitHubSnapshot {
            let running = GitHubPR(id: "SAMPLE_3", number: 5, title: "GitHub on the island", url: link, repo: "ledge",
                                   author: login, headSHA: "c3",
                                   checks: GitHubChecks(state: .pending, startedAt: now.addingTimeInterval(-134),
                                                        segments: [.passed, .passed, .passed, .failed, .running, .running]))
            let failed = GitHubPR(id: "SAMPLE_4", number: 4, title: "Update notice", url: link, repo: "ledge", author: login,
                                  headSHA: "c4", checks: GitHubChecks(state: .failed, failedName: "test (macos)",
                                                                       segments: [.passed, .failed]))
            let passed = GitHubPR(id: "SAMPLE_5", number: 12, title: "Fix the date picker", url: link, repo: "web",
                                  author: login, headSHA: "c5", checks: GitHubChecks(state: .passed, segments: [.passed, .passed]))
            return GitHubSnapshot(login: login, takenAt: now, mine: [running, failed, passed], requested: [request])
        }
    ```

- [ ] **Step 7: Run the tests.** `make test FILTER=GitHubServiceTests` → all pass. `make build` will fail in `SettingsKit` (`PreviewStage` still calls `.merged(GitHubPR)`) — fix that one call now, minimally, so the build stays green: in `Sources/SettingsKit/PreviewStage.swift`, `showGitHub(c, .merged(content.pullRequest ?? GitHubSample.pr))` → `showGitHub(c, .merged(GitHubDeparture(pr: content.pullRequest ?? GitHubSample.pr, merged: true, by: GitHubSample.reviewer)))`. Also update `Tests/SettingsKitTests/PreviewStageTests.swift` `theGitHubScenesShowTheirMoments` to the new captions, so no test stays red between tasks: `"#12 Fix the date picker · test (macos)"` → `"Fix the date picker · test (macos) · web"`, `"sam asks for your review · #7 site"` → `"Tidy the footer · sam · site"`, `"#4 update notice · ledge"` → `"update notice · sam · ledge"`. Then `make build` and the full `make test` (only the two known failures).

- [ ] **Step 8: Commit.**

```bash
git add Sources/GitHubService Tests/GitHubServiceTests Sources/SettingsKit/PreviewStage.swift Tests/SettingsKitTests/PreviewStageTests.swift
git commit -m "pick the panel's hero, word the blips title first with who did it, and put each moment's glyph on a disc or a picture

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log -1 --stat
```

---

### Task 3: The island draws it

**Files:** Modify `Sources/ActivityKit/ActivityRecord.swift`, `Sources/NotchKit/NotchController.swift`, `Sources/NotchKit/NotchPresenter.swift`, `Sources/NotchKit/NotchRootView.swift`, `Sources/NotchKit/GitHubPanel.swift`; replace `Sources/NotchKit/GitHubPanelView.swift`; test `Tests/ActivityKitTests/ActivityQueueTests.swift`, `Tests/NotchKitTests/NotchControllerTests.swift`.

**Interfaces — Produces:** `public enum ActivitySegment: String { passed, failed, running }`; `public enum IslandCheck { passed, failed, running }` (top level in NotchKit, so nothing main-actor isolated touches it); `ActivityRecord.segments: [ActivitySegment]?` and `ActivityDisplay.segments: [IslandCheck]?`, each a last init parameter `segments: ... = nil`; `NotchController.githubAvatarImage: NSImage?`; DEBUG-only `NotchController.debugOpen(_:)` and `NotchPresenter.debugOpen(_:)`; `GitHubPanelData.Hero` (`enum Kind { running, failed, review }`, `id`, `kind`, `tag`, `title`, `detail`, `segments: [IslandCheck]`, `since: Date?`, `avatar: Data?`, `url`; public init in that order) and `GitHubPanelData.hero` (init param `hero: Hero? = nil`, first).

- [ ] **Step 1: Failing tests.** Append to `Tests/ActivityKitTests/ActivityQueueTests.swift`:

```swift
@Test func aRecordCarriesItsSegments() {
    let record = ActivityRecord(id: "github-run", kind: .githubRun, insertedAt: Date(), ttl: nil, title: "Checks running",
                                segments: [.passed, .running])
    #expect(record.segments == [.passed, .running])
}
```

Append to `Tests/NotchKitTests/NotchControllerTests.swift`:

```swift
/// Review Focus 4: the width maths the caption row draws from.
@MainActor
@Test func aCaptionIsBoldUpToItsFirstSeparator() {
    let c = makeController()
    let bold = NSAttributedString(string: "Fix the date picker", attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).size().width
    let rest = NSAttributedString(string: " · sam · web", attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .regular)]).size().width
    #expect(c.captionWidth("Fix the date picker · sam · web") == ceil(bold + rest) + 2 * 14 + 16)
}

@MainActor
@Test func aGitHubBlipBringsItsAvatarAndTheRingItsSegments() {
    let c = makeController()
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let png = rep.representation(using: .png, properties: [:])!
    c.setActivities([.init(id: NotchController.githubActivityID, title: "Approved", compactText: "Approved",
                           symbolName: "checkmark", artwork: png)], overflow: 0)
    #expect(c.githubAvatarImage != nil)
    c.setActivities([.init(id: NotchController.githubRunActivityID, title: "Checks running", compactText: "0:42",
                           segments: [.passed, .failed, .running])], overflow: 0)
    #expect(c.githubAvatarImage == nil, "gone with its blip")
    #expect(c.activities.first?.segments == [.passed, .failed, .running])
}

@MainActor
@Test func thePanelCarriesItsHeroAndADebugProbeCanPinItOpen() {
    let c = makeController()
    let hero = GitHubPanelData.Hero(id: "PR_5", kind: .running, tag: "Checks running", title: "GitHub on the island",
                                    detail: "ledge #5 · 4 of 6 checks · 1 failed", segments: [.passed, .failed, .running],
                                    since: Date(), avatar: nil, url: URL(string: "https://github.com/dede/ledge/pull/5")!)
    c.setGitHubPanel(GitHubPanelData(hero: hero, rows: []))
    #expect(c.githubPanel?.hero?.title == "GitHub on the island")
    #if DEBUG
    c.debugOpen(.github)
    #expect(c.state == .expanded && c.panel == .github)
    #endif
}
```

- [ ] **Step 2: Run them to see them fail.** `make test FILTER=ActivityKitTests`, `make test FILTER=NotchKitTests` → do not build.

- [ ] **Step 3: ActivityKit.** In `Sources/ActivityKit/ActivityRecord.swift`, before `public struct ActivityRecord`, add:

```swift
/// One check's state, for the GitHub running item's ring (2026-10-22).
public enum ActivitySegment: String, Sendable, Equatable {
    case passed, failed, running
}
```

and in `ActivityRecord`, after `badge`, add `/// The ring's segments, a check each (2026-10-22); \`nil\` draws none.` and `public let segments: [ActivitySegment]?`, init param `segments: [ActivitySegment]? = nil` last, assigned last.

- [ ] **Step 4: NotchController.** In `Sources/NotchKit/NotchController.swift`:
  1. In `ActivityDisplay`, after `badge`, add:
     ```swift
             /// The GitHub ring's segments, a check each (2026-10-22).
             public let segments: [IslandCheck]?
     ```
     with init param `segments: [IslandCheck]? = nil` last, assigned last. (`IslandCheck` is defined in Step 6.)
  2. In `captionWidth(_:)`, change the comment to `// Split where \`captionRow\` splits it, at the first separator (2026-10-22): the title in bold, the rest dim.` and `caption.range(of: " · ", options: .backwards)` to `caption.range(of: " · ")`.
  3. After `public private(set) var awayCrestImage: NSImage?`, add:
     ```swift
         /// A GitHub blip's avatar (2026-10-22), decoded once per change like
         /// the crests; `nil` when no GitHub blip leads or it has none.
         public private(set) var githubAvatarImage: NSImage?
         private var githubAvatarData: Data?
     ```
     and in `setActivities(_:overflow:)`, after the two crest updates, add:
     ```swift
             let avatar = activities.first.flatMap { $0.id == Self.githubActivityID ? $0.artwork : nil }
             if avatar != githubAvatarData {
                 githubAvatarData = avatar
                 githubAvatarImage = avatar.flatMap(NSImage.init(data:))
             }
     ```
  4. After `setGitHubPanel(_:)`, add:
     ```swift
         #if DEBUG
         /// Debug probes only (2026-10-22): pins `panel` open for a screenshot,
         /// the way a click pins the now-playing card.
         public func debugOpen(_ panel: Panel) {
             guard metrics.notchRect.width > 0 else { return }
             self.panel = panel
             isPinnedOpen = true
             state = .expanded
         }
         #endif
     ```

- [ ] **Step 5: NotchPresenter.** After `setGitHubPanel(_:)`, add:

```swift
    #if DEBUG
    /// Debug probes only (2026-10-22): see `NotchController.debugOpen(_:)`.
    public func debugOpen(_ panel: NotchController.Panel) {
        controller.debugOpen(panel)
        syncWindowToVisibility()
    }
    #endif
```

- [ ] **Step 6: The panel's data.** In `Sources/NotchKit/GitHubPanel.swift`, before `public struct GitHubPanelData`, add:

```swift
/// One check's state, for the GitHub ring and the hero's bar (2026-10-22).
/// Top level, not nested in the main-actor island controller, so plain
/// values can carry it anywhere.
public enum IslandCheck: Sendable, Equatable {
    case passed, failed, running
}
```

Then, inside `GitHubPanelData`, add:

```swift
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
```

and change the init to `public init(hero: Hero? = nil, rows: [Row], more: Int = 0, moreURL: URL = URL(string: "https://github.com/pulls")!)`, assigning `self.hero = hero`.

- [ ] **Step 7: The views.** Replace `Sources/NotchKit/GitHubPanelView.swift` with:

```swift
import SwiftUI

/// GitHub's colours on the island (2026-10-22): the system's own.
enum GitHubColors {
    static var passed: Color { Color(nsColor: .systemGreen) }
    static var failed: Color { Color(nsColor: .systemRed) }
    static var running: Color { Color(nsColor: .systemYellow) }
    static var review: Color { Color(nsColor: .systemBlue) }

    static func segment(_ segment: IslandCheck) -> Color {
        switch segment {
        case .passed: passed
        case .failed: failed
        case .running: running
        }
    }
}

/// The GitHub panel of the open island (2026-10-22, the user's pick of
/// three): what is most worth watching as a card (checks running with a
/// bar of them, checks failed, a review waiting), then the rest as rows,
/// each with its status symbol, its title, and its repo dim at the end. A
/// click opens it on GitHub; the last line says how many more there are.
/// The reveal follows `CalendarPanelView`.
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

    /// Rows are a touch shorter under a card, so two and the "more" line fit.
    private var rowHeight: CGFloat { data.hero == nil ? 20 : 19 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let hero = data.hero {
                reveal(heroCard(hero), order: 0)
                if !data.rows.isEmpty || data.more > 0 {
                    reveal(Rectangle()
                        .fill(contentColor.opacity(0.12))
                        .frame(height: 0.5)
                        .padding(.top, 6)
                        .padding(.bottom, 3), order: 1)
                }
            } else {
                reveal(Text("GITHUB")
                    .font(.system(size: 9.5, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(contentColor.opacity(0.5))
                    .frame(height: 14), order: 0)
            }
            ForEach(Array(data.rows.enumerated()), id: \.element.id) { index, row in
                reveal(button(row.url) { label(row) }, order: 2 + index)
            }
            if data.more > 0 {
                reveal(button(data.moreURL) {
                    Text("\(data.more) more on GitHub")
                        .font(.system(size: 10.5))
                        .foregroundStyle(contentColor.opacity(0.5))
                        .padding(.leading, 19)
                }, order: 2 + data.rows.count)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.top, 6)
        .foregroundStyle(contentColor)
        .onAppear { revealed = true }
    }

    private func heroCard(_ hero: GitHubPanelData.Hero) -> some View {
        Button {
            emit(.open(hero.url))
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    if let avatar = hero.avatar.flatMap(NSImage.init(data:)) {
                        Image(nsImage: avatar)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFill()
                            .frame(width: 14, height: 14)
                            .clipShape(Circle())
                    }
                    Text(hero.tag.uppercased())
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(accent(hero.kind))
                    Spacer(minLength: 4)
                    if hero.kind == .running, let since = hero.since {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Self.clock(context.date.timeIntervalSince(since)))
                                .font(.system(size: 9.5, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(accent(hero.kind))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(contentColor.opacity(0.1)))
                        }
                    }
                }
                .frame(height: 16)
                Text(hero.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(contentColor)
                    .lineLimit(1)
                    .padding(.top, 2)
                Text(hero.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(contentColor.opacity(0.55))
                    .lineLimit(1)
                    .padding(.top, 1)
                if !hero.segments.isEmpty {
                    SegmentBar(segments: hero.segments, reduceMotion: reduceMotion)
                        .padding(.top, 7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ListRowButtonStyle(reduceMotion: reduceMotion))
    }

    private func accent(_ kind: GitHubPanelData.Hero.Kind) -> Color {
        switch kind {
        case .running: GitHubColors.running
        case .failed: GitHubColors.failed
        case .review: GitHubColors.review
        }
    }

    /// "2:14" under an hour, "1:02" (hours:minutes) from an hour up, as the
    /// island's own clock reads.
    static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 3600 { return String(format: "%d:%02d", total / 60, total % 60) }
        return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
    }

    private func button<Label: View>(_ url: URL, @ViewBuilder label: () -> Label) -> some View {
        Button {
            emit(.open(url))
        } label: {
            label()
                .frame(height: rowHeight)
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

    /// The row's status as a symbol in GitHub's colours, in a 13 pt column
    /// so the titles line up.
    private func mark(_ mark: GitHubPanelData.Row.Mark) -> some View {
        Group {
            switch mark {
            case .review:
                Image(systemName: "eye.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(GitHubColors.review)
            case .running:
                Image(systemName: "circle.dotted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GitHubColors.running)
            case .passed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(GitHubColors.passed)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(GitHubColors.failed)
            case .none:
                Image(systemName: "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(contentColor.opacity(0.35))
            }
        }
        .frame(width: 13)
    }
}

/// The hero's checks (2026-10-22): a segment each, finished first, the ones
/// still going faint and breathing; past twelve, one bar filling.
struct SegmentBar: View {
    let segments: [IslandCheck]
    let reduceMotion: Bool

    private var _breathing: State<Bool> = State(initialValue: false)
    private var breathing: Bool {
        get { _breathing.wrappedValue }
        nonmutating set { _breathing.wrappedValue = newValue }
    }

    var body: some View {
        Group {
            if segments.count <= CheckRing.maxSegments {
                HStack(spacing: 3) {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        Capsule()
                            .fill(GitHubColors.segment(segment))
                            .opacity(segment == .running ? (breathing ? 0.7 : 0.35) : 1)
                    }
                }
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(GitHubColors.running.opacity(0.25))
                        Capsule()
                            .fill(segments.contains(.failed) ? GitHubColors.failed : GitHubColors.running)
                            .frame(width: proxy.size.width * CheckRing.doneFraction(segments))
                    }
                }
            }
        }
        .frame(height: 4)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}

/// The running item's ring (2026-10-22, the user's pick): the hero's bar bent
/// into a circle, a segment per check from the top clockwise, finished first.
/// Past twelve the segments would be specks, so it fills smoothly instead,
/// red once one has failed.
struct CheckRing: View {
    static let maxSegments = 12

    let segments: [IslandCheck]
    let reduceMotion: Bool

    private var _breathing: State<Bool> = State(initialValue: false)
    private var breathing: Bool {
        get { _breathing.wrappedValue }
        nonmutating set { _breathing.wrappedValue = newValue }
    }

    static func doneFraction(_ segments: [IslandCheck]) -> Double {
        segments.isEmpty ? 0 : Double(segments.filter { $0 != .running }.count) / Double(segments.count)
    }

    var body: some View {
        ZStack {
            if segments.count <= Self.maxSegments {
                let slice = 1 / Double(max(segments.count, 1))
                let gap = segments.count > 1 ? min(0.05, slice * 0.3) : 0
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    Circle()
                        .trim(from: Double(index) * slice + gap / 2, to: Double(index + 1) * slice - gap / 2)
                        .stroke(GitHubColors.segment(segment), style: StrokeStyle(lineWidth: 2.2, lineCap: .butt))
                        .opacity(segment == .running ? (breathing ? 0.75 : 0.35) : 1)
                }
            } else {
                Circle()
                    .stroke(GitHubColors.running.opacity(0.25), lineWidth: 2.2)
                Circle()
                    .trim(from: 0, to: Self.doneFraction(segments))
                    .stroke(segments.contains(.failed) ? GitHubColors.failed : GitHubColors.running,
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
        }
        .rotationEffect(.degrees(-90))
        .frame(width: 14, height: 14)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { breathing = true }
        }
    }
}

/// A GitHub blip's leading glyph (2026-10-22, the user's pick): the person's
/// avatar with a small badge for what they did, or, for checks and runs,
/// the glyph on a disc in the event's colour.
struct GitHubBlipGlyph: View {
    let avatar: NSImage?
    let symbol: String
    let color: Color

    var body: some View {
        if let avatar {
            Image(nsImage: avatar)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 20, height: 20)
                .clipShape(Circle())
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: symbol)
                        .font(.system(size: 5.5, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 11, height: 11)
                        .background(Circle().fill(color))
                        .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                        .offset(x: 3, y: 2)
                }
        } else {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(color))
        }
    }
}

/// The running item's glyph for a run outside a PR, which has no per-check
/// detail (2026-10-22): an arc turning once every 1.2 s, and the count of
/// what runs when more than one does. Still under Reduce Motion.
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

(`GitHubRunRing` is the existing one, kept as it is apart from its doc comment; if its current body differs from the above, keep the current body.)

- [ ] **Step 8: The root view.** In `Sources/NotchKit/NotchRootView.swift`:
  1. In `captionRow(_:)`, `caption.range(of: " · ", options: .backwards)` → `caption.range(of: " · ")`, with a comment above it: `// Bold up to the first separator, the rest dim (2026-10-22): "Title · Artist", "Fix the date picker · sam · web".`
  2. In `leadingEar`, immediately before the branch whose condition reads `} else if let activity = controller.activities.first,` followed by `let data = activity.artwork, let image = NSImage(data: data) {`, insert:
     ```swift
             } else if let activity = controller.activities.first, activity.id == NotchController.githubActivityID {
                 // A GitHub blip (2026-10-22): who did it, or what happened.
                 // Before the product-render branch, which would draw the
                 // avatar square and unbadged.
                 GitHubBlipGlyph(avatar: controller.githubAvatarImage, symbol: activity.symbolName ?? "circle.fill",
                                 color: tintColor(for: activity.tint) ?? Color(nsColor: .systemGray))
                     .id(activity.title)
                     .transition(.blurReplace)
                     .animation(NotchAnimation.textAnimation(reduceMotion: controller.reduceMotion), value: activity.title)
     ```
  3. Replace the `githubRunActivityID` branch's body (the `GitHubRunRing(...)` call) with:
     ```swift
                 // A segment per check of the leading PR (2026-10-22); a run
                 // outside a PR has none and keeps the turning arc.
                 if let segments = activity.segments, !segments.isEmpty {
                     CheckRing(segments: segments, reduceMotion: controller.reduceMotion)
                 } else {
                     GitHubRunRing(color: tintColor(for: activity.tint) ?? contentColor, count: activity.badge,
                                   reduceMotion: controller.reduceMotion)
                 }
     ```
     keeping the branch's existing comment.
  4. In `trailingEar`, where `isTicking` is computed, add `let isGitHub = activity.id == NotchController.githubActivityID` and change the call to `compactValue(compact, bump: !isTicking, color: (isTicking || isGitHub) ? tintColor(for: activity.tint) : nil)`, with a comment line `// …and a GitHub blip's word, in its event's colour (2026-10-22).`

- [ ] **Step 9: Run the tests.** `make test FILTER=ActivityKitTests`, `make test FILTER=NotchKitTests` (including NotchRenderTests and NotchWindowTests) → pass; `make build` (the app target may need nothing yet; if `AppModel.publish()` fails to build, it will not, since both new parameters default to `nil`); the full `make test`.

- [ ] **Step 10: Commit.**

```bash
git add Sources/ActivityKit Sources/NotchKit Tests/ActivityKitTests Tests/NotchKitTests
git commit -m "draw github blips with an avatar or a colour disc, the running ring a segment per check, and the panel's hero card with its bar and clock

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log -1 --stat
```

---

### Task 4: The app loads the pictures and passes it all through

**Files:** Modify `Sources/Ledge/AppModel.swift`, `Sources/SettingsKit/PreviewStage.swift`, `Tests/SettingsKitTests/PreviewStageTests.swift`.

**Interfaces — Consumes:** Tasks 1 to 3. **Produces (for Task 5):** `AppModel.githubAvatar: Data?`; `AppModel.GitHubStats` (`open`, `failing`, `running`, `waiting`: `Int`) and `AppModel.githubStats: GitHubStats?`.

- [ ] **Step 1: Scenes.** In `Sources/SettingsKit/PreviewStage.swift`, `.githubRunning`'s `ActivityDisplay` gets `segments: [.passed, .passed, .passed, .failed, .running, .running]` after `tint:`. In `Tests/SettingsKitTests/PreviewStageTests.swift`, `theGitHubScenesShowTheirMoments` becomes:

```swift
@MainActor
@Test func theGitHubScenesShowTheirMoments() {
    let c = island()
    let checks = PreviewStage.apply(.githubChecks, content: PreviewContent(), to: c)
    #expect(checks.text == "Checks finished · Sample: not connected")
    #expect(c.activities.first?.id == NotchController.githubActivityID)
    #expect(c.activities.first?.compactText == "Failed")
    #expect(c.activities.first?.symbolName == "xmark")
    #expect(c.captionText == "Fix the date picker · test (macos) · web")
    _ = PreviewStage.apply(.githubRunning, content: PreviewContent(), to: c)
    #expect(c.activities.first?.id == NotchController.githubRunActivityID)
    #expect(c.activities.first?.compactText == "2:14")
    #expect(c.activities.first?.segments?.count == 6)
    _ = PreviewStage.apply(.githubRequests, content: PreviewContent(), to: c)
    #expect(c.captionText == "Tidy the footer · sam · site")
    _ = PreviewStage.apply(.githubRuns, content: PreviewContent(), to: c)
    #expect(c.captionText == "Deploy · web")
    let mine = GitHubPR(id: "PR_1", number: 4, title: "update notice", url: URL(string: "https://github.com/dede/ledge/pull/4")!, repo: "ledge")
    let real = PreviewStage.apply(.githubMerges, content: PreviewContent(pullRequest: mine), to: c)
    #expect(real.sampleReason == nil)
    #expect(c.captionText == "update notice · sam · ledge")
}
```

Run `make test FILTER=SettingsKitTests` → passes.

- [ ] **Step 2: Avatars in the app.** In `Sources/Ledge/AppModel.swift`, GitHub section:
  1. After `private static let githubKeychain = …`, add:
     ```swift
         private let githubAvatars = GitHubAvatars()
         /// Pictures already fetched, for drawing at once (2026-10-22).
         private var githubAvatarImages: [URL: Data] = [:]
         private var githubAvatarLoading: Set<URL> = []
     ```
  2. After `var githubNeedsAttention`, add:
     ```swift
         /// The account card's picture, once it has loaded (2026-10-22).
         var githubAvatar: Data? { github.snapshot?.avatarURL.flatMap { githubAvatarImages[$0] } }

         /// The account card's line: open PRs, failing, running, waiting for
         /// the user's review (2026-10-22).
         struct GitHubStats: Equatable {
             let open: Int
             let failing: Int
             let running: Int
             let waiting: Int
         }

         var githubStats: GitHubStats? {
             guard let snapshot = githubSnapshot else { return nil }
             return GitHubStats(open: snapshot.mineTotal,
                                failing: snapshot.mine.filter { $0.checks?.state == .failed }.count,
                                running: GitHubEvents.running(in: snapshot).count,
                                waiting: snapshot.requestedTotal)
         }
     ```
  3. In `stopGitHub()`, after `githubClock = RunningClock()`, add `githubAvatarImages = [:]`.
  4. In `handleGitHubRound`, as its first line, add `if let url = snapshot.avatarURL { loadGitHubAvatar(url) }`.
  5. Replace `showGitHub(_:)` with:
     ```swift
         /// A blip waits at most a second for its person's picture, then shows
         /// its disc (2026-10-22).
         private func showGitHub(_ blip: GitHubBlip) {
             Task { @MainActor [weak self] in
                 let avatar = await self?.githubAvatar(blip.avatarURL, within: 1)
                 // Locked while the picture came: no GitHub on the lock screen.
                 guard let self, !self.presenter.isLocked else { return }
                 self.queue.insert(ActivityRecord(
                     id: NotchController.githubActivityID, kind: .github, insertedAt: Date(),
                     ttl: ActivityKind.github.defaultTTL, title: blip.title, compactText: blip.word,
                     symbolName: blip.symbolName, artwork: avatar, tint: blip.tintName.map { .system($0) }, url: blip.url
                 ))
                 self.publish()
                 self.showCaption(blip.caption, for: ActivityKind.github.defaultTTL ?? NotchController.captionDuration)
             }
         }

         /// A picture from memory, else from GitHub's image server within
         /// `seconds`; `nil` if it has not come by then (2026-10-22).
         private func githubAvatar(_ url: URL?, within seconds: Double) async -> Data? {
             guard let url else { return nil }
             if let data = githubAvatarImages[url] { return data }
             let avatars = githubAvatars
             let data = await withTaskGroup(of: Data?.self) { group in
                 group.addTask { await avatars.image(at: url) }
                 group.addTask {
                     try? await Task.sleep(for: .seconds(seconds))
                     return nil
                 }
                 let first = await group.next() ?? nil
                 group.cancelAll()
                 return first
             }
             if let data { githubAvatarImages[url] = data }
             return data
         }

         /// Fetches a picture in the background, then redraws the panel;
         /// Settings reads it from memory (2026-10-22).
         private func loadGitHubAvatar(_ url: URL) {
             guard githubAvatarImages[url] == nil, !githubAvatarLoading.contains(url) else { return }
             githubAvatarLoading.insert(url)
             Task { @MainActor [weak self] in
                 _ = await self?.githubAvatar(url, within: 10)
                 self?.githubAvatarLoading.remove(url)
                 self?.publishGitHubPanel()
             }
         }
     ```
  6. In `refreshGitHub()`, the running `ActivityRecord(...)` gets `segments: lead.item.segments.map(Self.activitySegment)` after `badge:`, and the republish condition gets `|| record.segments != githubRunShown?.segments`.
  7. In `publishGitHubPanel()`, replace the body of `if !presenter.isLocked, let snapshot = githubSnapshot { … }` with:
     ```swift
                 let list = GitHubPanelRows.make(snapshot)
                 if list.hero != nil || !list.rows.isEmpty {
                     data = GitHubPanelData(
                         hero: list.hero.map { hero in
                             GitHubPanelData.Hero(
                                 id: hero.id, kind: Self.heroKind(hero.kind), tag: hero.tag, title: hero.title,
                                 detail: hero.detail, segments: hero.segments.map(Self.heroSegment), since: hero.startedAt,
                                 avatar: hero.avatarURL.flatMap { githubAvatarImages[$0] }, url: hero.url
                             )
                         },
                         rows: list.rows.map { GitHubPanelData.Row(id: $0.id, mark: Self.panelMark($0.mark), title: $0.title, repo: $0.repo, url: $0.url) },
                         more: list.more, moreURL: GitHubPanelRows.moreURL
                     )
                     if let url = list.hero?.avatarURL { loadGitHubAvatar(url) }
                 }
     ```
  8. After `panelMark(_:)`, add:
     ```swift
         private static func heroKind(_ kind: GitHubHero.Kind) -> GitHubPanelData.Hero.Kind {
             switch kind {
             case .running: .running
             case .failed:  .failed
             case .review:  .review
             }
         }

         private static func heroSegment(_ segment: CheckSegment) -> IslandCheck {
             switch segment {
             case .passed:  .passed
             case .failed:  .failed
             case .running: .running
             }
         }

         private static func activitySegment(_ segment: CheckSegment) -> ActivitySegment {
             switch segment {
             case .passed:  .passed
             case .failed:  .failed
             case .running: .running
             }
         }

         private static func displaySegment(_ segment: ActivitySegment) -> IslandCheck {
             switch segment {
             case .passed:  .passed
             case .failed:  .failed
             case .running: .running
             }
         }
     ```
  9. In `publish()`, the `ActivityDisplay(...)` call gets `segments: record.segments?.map(Self.displaySegment)` after `badge: record.badge`.

- [ ] **Step 3: The panel probe.** After `playGitHubStory()` (inside the same `#if DEBUG`), add:

```swift
    /// `ledge://probe/github-panel`, debug builds only (2026-10-22): pins the
    /// GitHub panel open on `GitHubSample.panelSnapshot` for twenty seconds,
    /// for screenshots, with no network.
    private func openGitHubPanelProbe() {
        githubProbeSnapshot = GitHubSample.panelSnapshot(login: "you", now: Date())
        publishGitHubPanel()
        presenter.debugOpen(.github)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            self?.presenter.controller.dismiss()
            self?.githubProbeSnapshot = nil
            self?.publishGitHubPanel()
        }
    }
```

and in `openURL(_:)`, next to the `/github` probe (inside the DEBUG region), add:

```swift
        if url.scheme == "ledge", url.host() == "probe", url.path() == "/github-panel" {
            Self.log.notice("probe: github panel")
            openGitHubPanelProbe()
            return
        }
```

- [ ] **Step 4: Build and test.** `make build` (no new warnings in `AppModel.swift`), `make build CONF=release`, the full `make test`.

- [ ] **Step 5: Commit.**

```bash
git add Sources/Ledge/AppModel.swift Sources/SettingsKit/PreviewStage.swift Tests/SettingsKitTests/PreviewStageTests.swift
git commit -m "load people's pictures for the blips and the panel, give the ring its segments, and add a probe that pins the panel open

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log -1 --stat
```

---

### Task 5: Settings › GitHub, and the docs

**Files:** Replace `Sources/Ledge/GitHubSettings.swift`; modify `README.md`, `docs/superpowers/specs/2026-09-25-notch-companion-design.md`, `docs/manual-checks.md`.

**Interfaces — Consumes:** `AppModel.githubAvatar`, `githubStats`, `githubStatus`, `githubLogin`, `githubSource`, `githubNeedsToken`, `githubHidesOrganisations`, `connectGitHub()`, `disconnectGitHub()`, `saveGitHubToken(_:)`, `checkGitHubNow()`; `playing(_:_:settings:director:)` from `SettingsPanes.swift`.

- [ ] **Step 1: The pane.** Replace `Sources/Ledge/GitHubSettings.swift` with:

```swift
import AppKit
import SwiftUI
import GitHubService
import LedgeSettings
import SettingsKit

/// Settings › GitHub (2026-10-22; polished the same day at the user's
/// call): the preview strip, an account card (or a welcome card before
/// connecting), then the moments in two groups.
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
        let wantsTokenBinding = Binding(get: { wantsToken }, set: { wantsToken = $0 })
        return Form {
            Section {
                PreviewStrip(director: director, height: PreviewStrip.shortHeight) { model.previewContent() }
                    .asPaneHeader()
            }
            Section {
                TimelineView(.periodic(from: .now, by: 2)) { _ in
                    if settings.githubConnected {
                        GitHubAccountCard(model: model, wantsToken: wantsTokenBinding)
                    } else {
                        GitHubWelcomeCard(model: model, wantsToken: wantsTokenBinding)
                    }
                }
                if model.githubNeedsToken || wantsToken || model.githubStatus == .signInAgain {
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
            } footer: {
                Text("While connected, Ledge asks api.github.com every minute, or every 20 seconds while something runs, and fetches people's pictures from GitHub's image server. Your token stays with gh or in your Keychain.")
            }
            Section {
                moment("Checks running", "A ring that fills check by check, and a clock.",
                       symbol: "circle.dotted", color: .systemYellow, \.githubChecksRunning, .githubRunning)
                moment("Checks finished", "Passed or failed, once for each commit.",
                       symbol: "checkmark.circle.fill", color: .systemGreen, \.githubChecksFinished, .githubChecks)
                moment("Reviews and comments", "Approvals, change requests and comments, bots included.",
                       symbol: "bubble.left.fill", color: .systemOrange, \.githubReviews, .githubReviews)
                moment("Merges and closes", "When someone else merges or closes one.",
                       symbol: "arrow.triangle.merge", color: .systemPurple, \.githubMerges, .githubMerges)
            } header: {
                Text("Your pull requests")
            }
            .opacity(settings.githubConnected ? 1 : 0.55)
            Section {
                moment("Review requests", "When someone asks for your review.",
                       symbol: "eye.fill", color: .systemBlue, \.githubReviewRequests, .githubRequests)
                moment("Your runs outside PRs", "Runs you start with a push, a tag or a deploy.",
                       symbol: "play.circle.fill", color: .systemGray, \.githubMyRuns, .githubRuns)
            } header: {
                Text("Around you")
            }
            .opacity(settings.githubConnected ? 1 : 0.55)
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

/// Before connecting (2026-10-22): what this is, and the two ways in.
struct GitHubWelcomeCard: View {
    let model: AppModel
    let wantsToken: Binding<Bool>

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color(white: 0.22)))
            Text("Your pull requests on the island")
                .font(.headline)
                .padding(.top, 2)
            Text("Checks as they run and finish, reviews, merges and review requests, across all your repos. Ledge asks GitHub only once you connect.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            HStack(spacing: 10) {
                Button("Connect with gh") { model.connectGitHub() }
                    .buttonStyle(.borderedProminent)
                Button("Use a token…") { wantsToken.wrappedValue = true }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
}

/// Once connected (2026-10-22): who, how, when last checked, and the
/// buttons; then the line of what is going on, or what is wrong.
struct GitHubAccountCard: View {
    let model: AppModel
    let wantsToken: Binding<Bool>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                picture
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    if model.githubSource == .gh, model.githubStatus != .signInAgain, !wantsToken.wrappedValue {
                        Button("Use a token") { wantsToken.wrappedValue = true }
                    }
                    if model.githubNeedsToken || model.githubStatus == .signInAgain {
                        Button("Try again") { model.checkGitHubNow() }
                    } else if model.githubStatus != .checking {
                        Button("Check now") { model.checkGitHubNow() }
                    }
                    Button("Disconnect") { model.disconnectGitHub() }
                }
            }
            if case .ok = model.githubStatus, let stats = model.githubStats {
                HStack(spacing: 14) {
                    stat(stats.open, stats.open == 1 ? "open PR" : "open PRs", nil)
                    stat(stats.failing, "failing", .systemRed)
                    stat(stats.running, "running", .systemYellow)
                    stat(stats.waiting, "waiting for your review", .systemBlue)
                }
                .font(.callout)
                .padding(.leading, 46)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var picture: some View {
        if let image = model.githubAvatar.flatMap(NSImage.init(data:)) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 34, height: 34)
                .clipShape(Circle())
        } else {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(white: 0.22)))
        }
    }

    private func stat(_ value: Int, _ label: String, _ color: NSColor?) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(color.map { Color(nsColor: $0) } ?? .primary)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        if model.githubNeedsToken { return "No GitHub login found" }
        switch model.githubStatus {
        case .off, .checking: return "Connecting…"
        case .signInAgain: return "Sign in again"
        case .ok, .failed, .rateLimited: return model.githubLogin ?? "Could not reach GitHub"
        }
    }

    private var subtitle: String {
        if model.githubNeedsToken { return "Log in with gh auth login in Terminal, or paste a token, then Try again." }
        let via = model.githubSource == .gh ? "Connected through gh" : "Connected with a token"
        var lines: [String] = []
        switch model.githubStatus {
        case .ok(let at): lines.append("\(via) · checked at \(time(at))")
        case .failed: lines.append("Could not reach GitHub just now. Ledge tries again shortly.")
        case .rateLimited(let until): lines.append("GitHub asked Ledge to wait until \(time(until)).")
        case .signInAgain: lines.append("GitHub no longer takes this login. Log in again with gh auth login, or paste a new token, then Try again.")
        case .off, .checking: lines.append(via)
        }
        if model.githubHidesOrganisations {
            lines.append("Some organisations hide their PRs from this token; authorise it for them on GitHub.")
        }
        return lines.joined(separator: " ")
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
```

- [ ] **Step 2: The README.** In `README.md`:
  - in the Install paragraph about connecting GitHub, change `Ledge asks api.github.com about your own PRs and runs every minute, or every 20 seconds while something runs.` to `Ledge asks api.github.com about your own PRs and runs every minute, or every 20 seconds while something runs, and fetches the pictures of the people in them from GitHub's image server.` (if the sentence reads slightly differently, keep its words and add the clause);
  - in the "What it shows" GitHub row, change the cell after `| GitHub, once connected in Settings › GitHub |` to: `checks running on your PRs: a ring with a segment per check, and a clock; checks passed or failed, a review, a comment, a merge, a review request, or a run of yours finishing: a blip with who did it (their picture) or what happened, the PR's title under the hole; click to open it on GitHub. Hover for a card of what is running, with a bar of its checks, then your PRs and review requests. Never on the lock screen |`.

- [ ] **Step 3: The specs and the manual checks.** Append to the "GitHub on the island (2026-10-22)" section of `docs/superpowers/specs/2026-09-25-notch-companion-design.md`:

```markdown

**Polish (2026-10-22, later).** The user found the first cut basic and chose,
from mockups: a panel with a hero card (what is running, else failed, else a
review request, with a segmented bar of its checks and a clock) over two rows;
a running ring with a segment per check; blips with the person's avatar and a
badge, or a colour disc for checks and runs, and captions that lead with the
PR's title (the island now bolds a caption up to its first separator); and an
account card in Settings. Avatars come from GitHub's image server, no token,
memory only. Design: `2026-10-22-github-island-polish-design.md`.
```

Append to `docs/manual-checks.md`, at the end of the "GitHub on the island (2026-10-22)" list:

```markdown
8. The panel's hero card: checks running with the segmented bar and a ticking clock; checks failed; a review request with the asker's picture. A debug build's `ledge://probe/github-panel` pins it open on a sample.
9. A blip from a person (a review, a comment) shows their picture with a badge; checks and runs show a colour disc.
10. Settings › GitHub: the account card with your picture and the line of counts; before connecting, the welcome card.
```

- [ ] **Step 4: Build and test.** `make build` (no new warnings in `GitHubSettings.swift`), `make build CONF=release`, the full `make test`. Check new text for em or en dashes: `grep -nP '[\x{2013}\x{2014}]'` over the lines you added.

- [ ] **Step 5: Commit.**

```bash
git add Sources/Ledge/GitHubSettings.swift README.md docs/superpowers/specs/2026-09-25-notch-companion-design.md docs/manual-checks.md
git commit -m "give settings an account card and a welcome card with the moments in two groups, and describe the polish in the readme and the specs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git log -1 --stat
```

---

## After the tasks (controller)

1. Whole-branch review of the polish range, then one fix wave.
2. Live, debug build: `ledge://probe/github` (each step, with the segmented ring) and `ledge://probe/github-panel` (the hero card), captured.
3. Put the installed copy back: `make stop; open /Applications/Ledge.app`.
4. Push; the PR updates. Merge only when the user says merge.
