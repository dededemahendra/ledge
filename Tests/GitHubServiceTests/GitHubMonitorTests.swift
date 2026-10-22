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
