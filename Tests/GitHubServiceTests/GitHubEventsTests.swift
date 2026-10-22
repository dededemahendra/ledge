import Testing
import Foundation
@testable import GitHubService

private let t0 = date("2026-10-22T03:00:00Z")
private let link = URL(string: "https://github.com/dede/ledge")!

private func pr(_ id: String = "PR_1", number: Int = 4, sha: String = "aaa", checks: CheckState? = nil, failed: String? = nil,
                segments: [CheckSegment] = [], started: Date? = nil,
                reviews: [GitHubReview] = [], comments: [GitHubComment] = []) -> GitHubPR {
    GitHubPR(id: id, number: number, title: "update notice", url: URL(string: "https://github.com/dede/ledge/pull/\(number)")!,
             repo: "ledge", author: "dede", headSHA: sha,
             checks: checks.map { GitHubChecks(state: $0, startedAt: started, failedName: failed, segments: segments) },
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

@Test func aPassIsToldOncePerCommitAndAFailureEachTime() {
    var passed: Set<String> = []
    var previous: GitHubSnapshot?
    var told: [String] = []
    for round in [snap(0, mine: [pr(checks: .pending)]), snap(1, mine: [pr(checks: .passed)]),
                  snap(2, mine: [pr(checks: .pending)]), snap(3, mine: [pr(checks: .passed)]),
                  snap(4, mine: [pr(checks: .failed)]), snap(5, mine: [pr(checks: .pending)]),
                  snap(6, mine: [pr(checks: .failed)]), snap(6.5, mine: [pr(checks: .passed)]), snap(7, mine: [pr(sha: "bbb", checks: .pending)]),
                  snap(8, mine: [pr(sha: "bbb", checks: .passed)])] {
        told += GitHubEvents.between(previous, round, passed: &passed).map(name)
        previous = round
    }
    #expect(told == ["checksPassed", "checksFailed", "checksFailed", "checksPassed", "checksPassed"],
            "a late check passing again is quiet; a re-run failing again is told, and so is one passing after a failure; a new commit's pass is told")
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
    #expect(GitHubEvents.between(open, after) == [.merged(after.departed[0]), .closed(after.departed[1])])
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
    #expect(GitHubEvents.running(in: snap(0, mine: [pr(checks: .pending, segments: [.passed, .running])])).first?.segments == [.passed, .running])
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

@Test func aBurstIsOneBlip() {
    let p = pr(checks: .passed)
    let events: [GitHubEvent] = [.commented(p, comment("C1", "sam")), .checksPassed(p), .reviewed(p, review("R1", "sam", .changesRequested))]
    let blip = GitHubNotice.burst(events)
    #expect(blip?.word == "Changes")
    #expect(blip?.caption == "update notice · sam · ledge · +2 more")
    #expect(GitHubNotice.burst([]) == nil)
    #expect(GitHubNotice.burst([.checksPassed(p)])?.caption == "update notice · ledge")
}

/// Review Focus 1.
@Test func aLongTitleIsShortenedInTheCaption() {
    let long = GitHubPR(id: "x", number: 9, title: String(repeating: "a", count: 60), url: link, repo: "ledge")
    #expect(GitHubNotice.blip(for: .merged(GitHubDeparture(pr: long, merged: true, by: nil))).caption == String(repeating: "a", count: 39) + "… · ledge")
}

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

@Test func theProbesStoryTellsEveryMoment() {
    let story = GitHubSample.story(login: "you", start: t0)
    let pairs = zip([nil] + story.map(Optional.some), story)
    let told = pairs.map { old, new in GitHubEvents.between(old, new).map(name) }
    #expect(told == [[], [], ["checksFailed"], ["commented"], ["reviewed"], ["merged"], ["reviewRequested"]])
    #expect(GitHubEvents.running(in: story[1]).count == 1)
    #expect(!GitHubPanelRows.make(story[6]).rows.isEmpty)
    #expect(GitHubPanelRows.make(GitHubSample.panelSnapshot(login: "you", now: t0)).hero?.kind == .running)
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
