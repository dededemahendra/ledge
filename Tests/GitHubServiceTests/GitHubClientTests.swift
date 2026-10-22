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
                                            url: URL(string: "https://github.com/dede/ledge/pull/4#pullrequestreview-1"),
                                            avatarURL: URL(string: "https://avatars.githubusercontent.com/in/347564?v=4"))])
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
    #expect(failed.checks?.segments == [.passed, .failed])
    #expect(running.checks?.segments == [.running, .running])
    #expect(snapshot.avatarURL?.absoluteString == "https://avatars.githubusercontent.com/u/1?v=4")
    #expect(failed.comments.first?.avatarURL != nil && failed.comments.last?.avatarURL == nil, "a deleted account has no picture")
    #expect(snapshot.requested.first?.authorAvatarURL?.absoluteString == "https://avatars.githubusercontent.com/u/2?v=4")
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
    #expect(await failure(200, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1792641600"])
            == .rateLimited(until: Date(timeIntervalSince1970: 1792641600)), "GraphQL keeps a 200 when the limit is spent")
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
    #expect(snapshot.departed == [GitHubDeparture(pr: gone, merged: true, by: "octocat", byAvatarURL: URL(string: "https://avatars.githubusercontent.com/u/583231?v=4"))])
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
    #expect(seen.all.first?.httpShouldHandleCookies == false)
    for refused in ["http://avatars.githubusercontent.com/u/1", "https://evilgithubusercontent.com/u/1", "https://githubusercontent.com/u/1"] {
        #expect(await avatars.image(at: URL(string: refused)!) == nil, "\(refused)")
    }
    #expect(seen.all.count == 1, "none of those is asked for")
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

@Test func anAvatarThatEndsUpElsewhereOrIsHugeIsDropped() async {
    let url = URL(string: "https://avatars.githubusercontent.com/u/1")!
    let moved = GitHubAvatars(fetch: { _ in
        (Data("PNG".utf8), HTTPURLResponse(url: URL(string: "https://example.com/me.png")!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
    #expect(await moved.image(at: url) == nil)
    let huge = GitHubAvatars(fetch: fetch { _ in (200, [:], String(repeating: "x", count: GitHubAvatars.maximumBytes + 1)) })
    #expect(await huge.image(at: url) == nil)
    #expect(GitHubAvatars.isGitHubImage(url) && !GitHubAvatars.isGitHubImage(URL(string: "https://example.com/x")!))
}
