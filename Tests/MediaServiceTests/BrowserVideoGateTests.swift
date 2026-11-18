import Testing
import Foundation
@testable import MediaService

private func video(playing: Bool, duration: Double?) -> MediaPayload {
    var p = MediaPayload()
    p.bundleIdentifier = "com.google.Chrome"
    p.title = "A video"
    p.playing = playing
    p.duration = duration
    return p
}

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

@Test func aPlayingBrowserVideoGetsIn() {
    #expect(BrowserVideoGate.admits(video(playing: true, duration: 600), isShowing: false, pausedSince: nil, onCall: false, now: t0))
}

@Test func aBrowserWithoutALengthNeverGetsIn() {
    for duration in [nil, 0, Double.infinity] as [Double?] {
        #expect(!BrowserVideoGate.admits(video(playing: true, duration: duration), isShowing: false, pausedSince: nil, onCall: false, now: t0),
                "a live stream or a call: \(String(describing: duration))")
    }
}

@Test func aPausedBrowserNeverBringsTheCardUp() {
    #expect(!BrowserVideoGate.admits(video(playing: false, duration: 600), isShowing: false, pausedSince: t0, onCall: false, now: t0))
}

@Test func aShownBrowserVideoHoldsTwoMinutesWhilePaused() {
    let paused = video(playing: false, duration: 600)
    #expect(BrowserVideoGate.pausedHold == 120)
    #expect(BrowserVideoGate.admits(paused, isShowing: true, pausedSince: t0, onCall: false, now: t0.addingTimeInterval(119)))
    #expect(!BrowserVideoGate.admits(paused, isShowing: true, pausedSince: t0, onCall: false, now: t0.addingTimeInterval(120)))
    #expect(!BrowserVideoGate.admits(paused, isShowing: true, pausedSince: nil, onCall: false, now: t0))
}

@Test func aCallKeepsTheBrowserOut() {
    #expect(!BrowserVideoGate.admits(video(playing: true, duration: 600), isShowing: true, pausedSince: nil, onCall: true, now: t0))
}

@Test func theHoldIsCheckedAgainOnceItHasSurelyRunOut() {
    // The app re-decides after `recheckDelay`; a wake a hair early must
    // still land past the hold, or a paused card would never be asked again.
    #expect(BrowserVideoGate.recheckDelay > BrowserVideoGate.pausedHold)
    let paused = video(playing: false, duration: 600)
    #expect(!BrowserVideoGate.admits(paused, isShowing: true, pausedSince: t0, onCall: false,
                                      now: t0.addingTimeInterval(BrowserVideoGate.recheckDelay - 0.5)))
}

private func dia(playing: Bool) -> MediaPayload {
    var p = MediaPayload()
    p.bundleIdentifier = "company.thebrowser.dia"
    p.title = "A video"
    p.playing = playing
    return p   // Dia reports its length as infinity, which the adapter drops
}

@Test func diaGetsInWithoutALengthBecauseItNeverReportsOne() {
    #expect(BrowserVideoGate.admits(dia(playing: true), isShowing: false, pausedSince: nil, onCall: false, now: t0))
}

@Test func diaStillNeedsToBePlayingAndNoCall() {
    #expect(!BrowserVideoGate.admits(dia(playing: false), isShowing: false, pausedSince: nil, onCall: false, now: t0))
    #expect(!BrowserVideoGate.admits(dia(playing: true), isShowing: true, pausedSince: nil, onCall: true, now: t0))
    #expect(BrowserVideoGate.admits(dia(playing: false), isShowing: true, pausedSince: t0, onCall: false, now: t0.addingTimeInterval(60)),
            "its pause hold is the same two minutes")
}

@Test func otherBrowsersStillNeedALength() {
    var chrome = dia(playing: true)
    chrome.bundleIdentifier = "com.google.Chrome"
    #expect(!BrowserVideoGate.admits(chrome, isShowing: false, pausedSince: nil, onCall: false, now: t0))
}
