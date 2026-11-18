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
