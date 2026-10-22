import Testing
import Foundation
@testable import UpdateService

private let reply = #"""
{"tag_name":"v0.1.2","html_url":"https://github.com/dededemahendra/ledge/releases/tag/v0.1.2","draft":false,"prerelease":false,
 "assets":[{"name":"Ledge-0.1.2.dmg","browser_download_url":"https://github.com/dededemahendra/ledge/releases/download/v0.1.2/Ledge-0.1.2.dmg"}]}
"""#

@Test func versionsCompareNumberByNumber() {
    #expect(AppVersion("v0.1.2")! == AppVersion("0.1.2")!)
    #expect(AppVersion("0.1.10")! > AppVersion("0.1.9")!)
    #expect(AppVersion("1.0")! == AppVersion("1.0.0")!)
    #expect(AppVersion("0.2")! > AppVersion("0.1.9")!)
    #expect(AppVersion("0.1.2")!.description == "0.1.2")
    for junk in ["latest", "nightly", "", "1..2", "v", "1.2.x"] {
        #expect(AppVersion(junk) == nil, "\(junk) is not a version")
    }
}

@Test func aReleaseIsReadFromGitHubsReply() {
    let release = ReleaseInfo.decode(Data(reply.utf8))
    #expect(release?.version == AppVersion("0.1.2"))
    #expect(release?.pageURL.absoluteString == "https://github.com/dededemahendra/ledge/releases/tag/v0.1.2")
    #expect(release?.downloadURL?.lastPathComponent == "Ledge-0.1.2.dmg")
}

/// Review Focus 1.
@Test func aTagThatIsNotAVersionIsNotARelease() {
    let nightly = reply.replacingOccurrences(of: "v0.1.2\",\"html", with: "nightly\",\"html")
    #expect(ReleaseInfo.decode(Data(nightly.utf8)) == nil)
    #expect(ReleaseInfo.decode(Data("not json".utf8)) == nil)
    #expect(ReleaseInfo.decode(Data(#"{"message":"Not Found"}"#.utf8)) == nil)
    let pre = reply.replacingOccurrences(of: "\"prerelease\":false", with: "\"prerelease\":true")
    #expect(ReleaseInfo.decode(Data(pre.utf8)) == nil, "a pre-release never shows")
}

/// Review Focus 1.
@Test func aReleaseWithoutADiskImageStillCounts() {
    let bare = #"{"tag_name":"v0.1.2","html_url":"https://github.com/dededemahendra/ledge/releases/tag/v0.1.2","assets":[]}"#
    let release = ReleaseInfo.decode(Data(bare.utf8))
    #expect(release?.version == AppVersion("0.1.2") && release?.downloadURL == nil)
}

/// Review Focus 3.
@Test func aVersionIsAnnouncedOnce() {
    let latest = ReleaseInfo.decode(Data(reply.utf8))!
    #expect(UpdateDecision.evaluate(current: AppVersion("0.1.1")!, latest: latest, lastAnnounced: nil)
            == .available(latest, announce: true))
    #expect(UpdateDecision.evaluate(current: AppVersion("0.1.1")!, latest: latest, lastAnnounced: AppVersion("0.1.2"))
            == .available(latest, announce: false), "found again: still available, not announced")
    #expect(UpdateDecision.evaluate(current: AppVersion("0.1.2")!, latest: latest, lastAnnounced: nil) == .upToDate)
    #expect(UpdateDecision.evaluate(current: AppVersion("0.2")!, latest: latest, lastAnnounced: nil) == .upToDate)
}

private final class Seen: @unchecked Sendable { var request: URLRequest? }

private func answering(_ status: Int, _ body: String, seen: Seen? = nil) -> UpdateChecker.Fetch {
    { request in
        seen?.request = request
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }
}

@Test func theCheckAsksGitHubPolitely() async {
    let seen = Seen()
    let checker = UpdateChecker(currentVersion: AppVersion("0.1.1")!, fetch: answering(200, reply, seen: seen))
    #expect(await checker.check(lastAnnounced: nil) == .available(ReleaseInfo.decode(Data(reply.utf8))!, announce: true))
    #expect(seen.request?.url == UpdateChecker.latestReleaseURL)
    #expect(seen.request?.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
    #expect(seen.request?.value(forHTTPHeaderField: "User-Agent") == "Ledge/0.1.1")
    #expect(seen.request?.timeoutInterval == 15)
}

/// Review Focus 2.
@Test func anythingButAReadable200IsCouldNotCheck() async {
    let current = AppVersion("0.1.1")!
    #expect(await UpdateChecker(currentVersion: current, fetch: answering(403, #"{"message":"rate limit"}"#)).check(lastAnnounced: nil) == nil)
    #expect(await UpdateChecker(currentVersion: current, fetch: answering(500, "")).check(lastAnnounced: nil) == nil)
    #expect(await UpdateChecker(currentVersion: current, fetch: answering(200, "garbage")).check(lastAnnounced: nil) == nil)
    let offline: UpdateChecker.Fetch = { _ in throw URLError(.notConnectedToInternet) }
    #expect(await UpdateChecker(currentVersion: current, fetch: offline).check(lastAnnounced: nil) == nil)
}

@Test func theNoticeReadsTheSameEverywhere() {
    #expect(UpdateNotice.symbolName == "arrow.down.circle.fill")
    #expect(UpdateNotice.title("0.1.2") == "Ledge 0.1.2 is available")
    #expect(UpdateNotice.caption("0.1.2") == "Ledge 0.1.2 is available · Download")
}
