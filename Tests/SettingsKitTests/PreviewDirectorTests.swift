import Testing
import Foundation
@testable import SettingsKit

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

@MainActor
@Test func atRestItCyclesOnlyThroughTheScenesSwitchedOn() {
    let d = PreviewDirector(scenes: [.volume, .capsLock, .battery], isOn: { $0 != .capsLock }, now: t0)
    #expect(d.scene == .volume)
    d.tick(at: t0)
    d.tick(at: t0 + 2.4)
    #expect(d.scene == .volume, "not yet")
    d.tick(at: t0 + 2.5)
    #expect(d.scene == .battery, "Caps Lock is off, so it is skipped")
    d.tick(at: t0 + 5.0)
    #expect(d.scene == .volume, "and round again")
}

@MainActor
@Test func pointingShowsThatRowEvenWhenOffAndLeavingResumesTheCycle() {
    let d = PreviewDirector(scenes: [.volume, .capsLock], isOn: { $0 != .capsLock }, now: t0)
    d.point(at: .capsLock, now: t0 + 1)
    #expect(d.scene == .capsLock && d.isShowingOff)
    d.tick(at: t0 + 10)
    #expect(d.scene == .capsLock, "pointing holds it, however long")
    d.leave(.capsLock, now: t0 + 11)
    #expect(d.scene == .volume && !d.isShowingOff)
}

/// Review Focus 1: moving down a pane, the next row's enter can come
/// before the last row's leave.
@MainActor
@Test func aLeaveThatArrivesAfterTheNextRowsEnterIsIgnored() {
    let d = PreviewDirector(scenes: [.volume, .battery], isOn: { _ in true }, now: t0)
    d.point(at: .volume, now: t0)
    d.point(at: .battery, now: t0)
    d.leave(.volume, now: t0)
    #expect(d.scene == .battery)
}

@MainActor
@Test func aSwitchTurnedOnPlaysOnceThenTheCycleResumes() {
    let d = PreviewDirector(scenes: [.volume, .battery], isOn: { _ in true }, now: t0)
    d.switchedOn(.battery, now: t0)
    #expect(d.scene == .battery)
    d.tick(at: t0 + PreviewDirector.playDuration - 0.1)
    #expect(d.scene == .battery)
    d.tick(at: t0 + PreviewDirector.playDuration)
    #expect(d.scene == .volume)
}

/// Review Focus 3.
@MainActor
@Test func pointingWinsOverAScenePlaying() {
    let d = PreviewDirector(scenes: [.volume, .battery], isOn: { _ in true }, now: t0)
    d.switchedOn(.battery, now: t0)
    d.point(at: .volume, now: t0 + 0.5)
    #expect(d.scene == .volume)
}

/// Review Focus 4.
@MainActor
@Test func withNothingSwitchedOnTheStripIsEmpty() {
    let d = PreviewDirector(scenes: [.volume, .battery], isOn: { _ in false }, now: t0)
    #expect(d.scene == nil && d.staged == nil)
    d.tick(at: t0 + 10)
    #expect(d.scene == nil && d.staged == nil)
}

/// The hover scene is two steps: now playing for the hover delay, then the card.
@MainActor
@Test func theHoverSceneShowsNowPlayingForTheHoverDelayThenTheCard() {
    let d = PreviewDirector(scenes: [.songCaption, .hoverCard], isOn: { _ in true }, now: t0)
    d.hoverDwell = 0.5
    d.point(at: .hoverCard, now: t0 + 1)
    #expect(d.scene == .hoverCard && d.staged == .nowPlaying)
    d.tick(at: t0 + 1.4)
    #expect(d.staged == .nowPlaying)
    d.tick(at: t0 + 1.5)
    #expect(d.staged == .hoverCard)
}

/// Flipping the switch of the row the pointer rests on replays its scene,
/// two-step hover included.
@MainActor
@Test func aSwitchTurnedOnForTheSceneShowingPlaysItAgainFromTheStart() {
    let d = PreviewDirector(scenes: [.songCaption, .hoverCard], isOn: { _ in true }, now: t0)
    d.hoverDwell = 0.5
    d.point(at: .hoverCard, now: t0)
    d.tick(at: t0 + 2)
    #expect(d.staged == .hoverCard && d.replays == 0)
    d.switchedOn(.hoverCard, now: t0 + 2)
    #expect(d.replays == 1, "the strip is told to play it again")
    #expect(d.staged == .nowPlaying, "the hover starts over with its pause")
    d.tick(at: t0 + 2.5)
    #expect(d.staged == .hoverCard)
    d.switchedOn(.songCaption, now: t0 + 3)
    #expect(d.replays == 1, "a different scene is a scene change, not a replay")
}
