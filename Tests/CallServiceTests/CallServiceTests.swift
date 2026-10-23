import ActivityKit
import Foundation
import Testing
@testable import CallService

private let t0 = Date(timeIntervalSince1970: 1_000)
private let zoom = CallAppInfo(bundleID: "us.zoom.xos", name: "zoom.us", pid: 100)
private let chrome = CallAppInfo(bundleID: "com.google.Chrome", name: "Google Chrome", pid: 300)

@MainActor
private final class FakeCamera: CameraSource {
    var isCameraOn = false
    private(set) var reads = 0
    func refresh() { reads += 1 }
}

/// A call app's own mute, made up (2026-10-23).
@MainActor
private final class FakeAppMute: AppMuteSource {
    var muted: Bool?
    private(set) var updatedFor: [String?] = []
    private(set) var presses = 0
    func update(for app: CallAppInfo?) { updatedFor.append(app?.bundleID) }
    func setMuted(_ target: Bool) -> Bool {
        guard let current = muted else { return false }
        if current != target {
            presses += 1
            muted = target
        }
        return true
    }
}

/// A calendar event `start` to `end` minutes from `t0`.
private func event(_ id: String, start: Double, end: Double, url: String = "https://meet.google.com/abc-defg-hij",
                   title: String = "Design review") -> MeetingCandidate {
    MeetingCandidate(id: id, title: title, start: t0.addingTimeInterval(start * 60), end: t0.addingTimeInterval(end * 60),
                     joinURL: URL(string: url))
}

/// Input devices that take Ledge's actions as a real one would.
@MainActor
private final class FakeDevices: InputDeviceIO {
    var devices: [InputDeviceState]
    init(_ devices: [InputDeviceState]) { self.devices = devices }

    func states() -> [InputDeviceState] { devices }

    func perform(_ actions: [MuteAction]) {
        for action in actions {
            switch action {
            case .setMute(let uid, let muted): update(uid) { (muted: muted, volume: $0.volume) }
            case .setVolume(let uid, let volume): update(uid) { (muted: $0.isMuted, volume: volume) }
            }
        }
    }

    func device(_ uid: String) -> InputDeviceState { devices.first { $0.uid == uid }! }

    func unplug(_ uid: String) -> InputDeviceState {
        let gone = device(uid)
        devices.removeAll { $0.uid == uid }
        return gone
    }

    func plug(_ device: InputDeviceState) { devices.append(device) }

    func setRunning(_ uid: String, _ running: Bool) {
        update(uid, running: running) { (muted: $0.isMuted, volume: $0.volume) }
    }

    private func update(_ uid: String, running: Bool? = nil, _ change: (InputDeviceState) -> (muted: Bool, volume: Float32)) {
        guard let index = devices.firstIndex(where: { $0.uid == uid }) else { return }
        let old = devices[index]
        let new = change(old)
        devices[index] = InputDeviceState(uid: old.uid, name: old.name, isRunning: running ?? old.isRunning,
                                          canMute: old.canMute, isMuted: new.muted,
                                          canSetVolume: old.canSetVolume, volume: new.volume)
    }
}

private func mic(_ uid: String, name: String = "MacBook Pro Microphone", running: Bool = true, canMute: Bool = true,
                 muted: Bool = false, volume: Float32 = 0.5) -> InputDeviceState {
    InputDeviceState(uid: uid, name: name, isRunning: running, canMute: canMute, isMuted: muted,
                     canSetVolume: true, volume: volume)
}

/// Who holds the mic, the way CoreAudio tells it: a change reaches
/// `holderPIDs` only when announced or when the service reads again
/// (`refresh()`). A browser tab closing is never announced: its audio
/// process stays and only stops using the mic (2026-10-22).
@MainActor
private final class FakeHolders: MicHolderSource {
    var truth: [pid_t]?
    private(set) var holderPIDs: [pid_t]?
    var isMicRunning = false
    var inputDeviceUIDs: Set<String> = []
    init(_ pids: [pid_t]?) { truth = pids; holderPIDs = pids }
    func start() {}
    func stop() {}
    func refresh() { holderPIDs = truth }
    func announce() { holderPIDs = truth }
}

/// A service on fake devices, a fake process table where 100 is Zoom, and
/// a defaults suite of its own. Setting `holders` changes who holds the
/// mic without announcing it.
@MainActor
private final class Rig {
    let source: FakeHolders
    var holders: [pid_t]? {
        get { source.truth }
        set { source.truth = newValue }
    }
    let devices: FakeDevices
    let camera = FakeCamera()
    let appMute = FakeAppMute()
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    lazy var service = CallService(
        holders: source,
        devices: devices,
        camera: camera,
        appMute: appMute,
        lookup: ProcessLookup(regularApp: { [100: zoom, 300: chrome][$0] }, responsiblePID: { _ in nil },
                              parentPID: { _ in nil }),
        defaults: defaults,
        ownPID: 9
    )

    init(_ devices: [InputDeviceState] = [mic("a")], holders: [pid_t]? = [100]) {
        self.devices = FakeDevices(devices)
        self.source = FakeHolders(holders)
    }

    /// Refreshes every quarter second over `seconds` after `t0`, returning
    /// the last update.
    @discardableResult
    func refresh(from: Double = 0, to: Double, hidden: Set<String> = [], meetings: [MeetingCandidate] = []) -> CallUpdate {
        var update = service.refresh(at: t0.addingTimeInterval(from), hidden: hidden, meetings: meetings)
        var t = from + 0.25
        while t <= to + 0.0001 {
            update = service.refresh(at: t0.addingTimeInterval(t), hidden: hidden, meetings: meetings)
            t += 0.25
        }
        return update
    }

    /// Refreshes once a second over `from` to `to` minutes after `t0`.
    @discardableResult
    func minutes(from: Double = 0, to: Double, hidden: Set<String> = [], meetings: [MeetingCandidate] = []) -> CallUpdate {
        var update = service.refresh(at: t0.addingTimeInterval(from * 60), hidden: hidden, meetings: meetings)
        var t = from * 60 + 1
        while t <= to * 60 + 0.0001 {
            update = service.refresh(at: t0.addingTimeInterval(t), hidden: hidden, meetings: meetings)
            t += 1
        }
        return update
    }

    var savedRecord: Data? { defaults.data(forKey: CallService.recordKey) }
}

@MainActor @Test func aCallShowsAfterTwoSecondsWithTheMicName() {
    let rig = Rig()
    let update = rig.refresh(to: 2)
    #expect(update.state == .live(app: zoom, since: t0))
    #expect(update.micName == "MacBook Pro Microphone")
    #expect(update.canMute)
}

@MainActor @Test func toggleMuteMutesAndReportsIt() {
    let rig = Rig()
    rig.refresh(to: 2)
    rig.service.toggleMute()
    #expect(rig.devices.device("a").isMuted)
    #expect(rig.refresh(from: 2.25, to: 2.25).isMuted)
    #expect(rig.savedRecord != nil, "what Ledge changed is saved as it changes")
}

/// A mic switch mid-call: the new mic starts running while muted.
@MainActor @Test func aDeviceThatStartsWhileMutedIsMuted() {
    let rig = Rig([mic("a"), mic("b", running: false)])
    rig.refresh(to: 2)
    rig.service.toggleMute()
    rig.devices.setRunning("b", true)
    rig.refresh(from: 2.25, to: 2.25)
    #expect(rig.devices.device("b").isMuted)
}

@MainActor @Test func theCallEndingRestoresLedgesMute() {
    let rig = Rig()
    rig.refresh(to: 10)
    rig.service.toggleMute()
    rig.holders = []
    var states: [CallState] = []
    var t = 10.25
    while t <= 14 {
        states.append(rig.service.refresh(at: t0.addingTimeInterval(t), hidden: []).state)
        t += 0.25
    }
    #expect(states.contains(.ended(app: zoom, length: 10)))
    #expect(!rig.devices.device("a").isMuted)
    #expect(rig.savedRecord == nil)
}

@MainActor @Test func hidingWhileMutedRestores() {
    let rig = Rig()
    rig.refresh(to: 10)
    rig.service.toggleMute()
    let update = rig.refresh(from: 10.25, to: 10.25, hidden: [zoom.bundleID])
    #expect(update.state == .idle)
    #expect(!rig.devices.device("a").isMuted)
}

@MainActor @Test func stoppingRestoresLedgesMute() {
    let rig = Rig()
    rig.service.start()
    rig.refresh(to: 10)
    rig.service.toggleMute()
    rig.service.stop()
    #expect(!rig.devices.device("a").isMuted)
    #expect(rig.savedRecord == nil)
}

/// Ledge crashed or was relaunched while muted.
@MainActor @Test func aSavedRecordIsRestoredOnStart() throws {
    let rig = Rig([mic("a", muted: true)])
    rig.defaults.set(try JSONEncoder().encode([MuteChange(uid: "a", kind: .mute)]), forKey: CallService.recordKey)
    rig.service.start()
    #expect(!rig.devices.device("a").isMuted)
    #expect(rig.savedRecord == nil)
}

@MainActor @Test func aSavedRecordLeavesADeviceTheUserChanged() throws {
    let rig = Rig([mic("b", canMute: false, volume: 0.4)])
    rig.defaults.set(try JSONEncoder().encode([MuteChange(uid: "b", kind: .volume(previous: 0.7))]),
                     forKey: CallService.recordKey)
    rig.service.start()
    #expect(rig.devices.device("b").volume == 0.4)
    #expect(rig.savedRecord == nil)
}

@MainActor @Test func anUnreadableProcessListIsUnavailable() {
    let rig = Rig()
    rig.holders = nil
    let update = rig.refresh(to: 3)
    #expect(update.state == .idle)
    #expect(rig.service.availability == .unavailable(reason: "can't read which apps use the microphone"))
}

/// Closing the Meet tab: the browser's audio process stays and stops using
/// the mic, and CoreAudio announces nothing. The call still ends.
@MainActor @Test func aReleaseCoreAudioNeverAnnouncesStillEndsTheCall() {
    let rig = Rig()
    rig.refresh(to: 30)
    rig.holders = []
    var states: [CallState] = []
    var t = 30.25
    while t <= 34 {
        states.append(rig.service.refresh(at: t0.addingTimeInterval(t), hidden: []).state)
        t += 0.25
    }
    #expect(states.contains(.ended(app: zoom, length: 30)))
}

/// One read landing in a mic switch's gap must not stop the re-reads: the
/// app comes back on a device that is already running, unannounced
/// (review, 2026-10-22).
@MainActor @Test func aGapReadMidCallDoesNotEndIt() {
    let rig = Rig()
    rig.refresh(to: 10)
    rig.holders = []
    rig.source.announce()
    _ = rig.service.refresh(at: t0.addingTimeInterval(10.25), hidden: [])
    rig.holders = [100]
    var states: [CallState] = []
    var t = 10.5
    while t <= 16 {
        states.append(rig.service.refresh(at: t0.addingTimeInterval(t), hidden: []).state)
        t += 0.25
    }
    #expect(states.allSatisfy { $0 == .live(app: zoom, since: t0) })
}

/// Joining a call on a headset already playing audio: the mic was running,
/// so nothing is announced; the call still shows.
@MainActor @Test func aCallOnAMicAlreadyRunningIsSeen() {
    let rig = Rig(holders: [])
    rig.source.isMicRunning = true
    rig.holders = [100]
    #expect(rig.refresh(to: 3).state == .live(app: zoom, since: t0))
}

/// Muted from the card, unmuted from System Settings: the card's button
/// mutes again rather than doing nothing.
@MainActor @Test func muteWorksAgainAfterAnOutsideUnmute() {
    let rig = Rig()
    rig.refresh(to: 2)
    rig.service.toggleMute()
    rig.devices.perform([.setMute(uid: "a", false)])
    #expect(!rig.refresh(from: 2.25, to: 2.25).isMuted)
    rig.service.toggleMute()
    #expect(rig.devices.device("a").isMuted)
}

/// A headset muted from the card and unplugged before the call ends is
/// unmuted when it comes back, not left muted for the next call.
@MainActor @Test func aMuteOnAnAbsentDeviceIsRestoredWhenItReturns() {
    let rig = Rig([mic("a"), mic("b")])
    rig.refresh(to: 10)
    rig.service.toggleMute()
    let headset = rig.devices.unplug("b")
    rig.holders = []
    rig.refresh(from: 10.25, to: 14)
    #expect(rig.savedRecord != nil, "the headset's mute is still owed")
    rig.devices.plug(headset)
    rig.refresh(from: 14.25, to: 16)
    #expect(!rig.devices.device("b").isMuted)
    #expect(rig.savedRecord == nil)
}

/// A headset only playing the call's sound is not the call's mic: muting
/// the mic that is used reads as muted.
@MainActor @Test func anOutputOnlyHeadsetIsNotTheCallsMic() {
    let rig = Rig([mic("a", name: "MacBook Air Microphone"),
                   InputDeviceState(uid: "h", name: "Headset", isRunning: true, canMute: false, isMuted: false,
                                    canSetVolume: false, volume: 0.5)])
    rig.source.inputDeviceUIDs = ["a"]
    rig.refresh(to: 2)
    rig.service.toggleMute()
    let update = rig.refresh(from: 2.25, to: 2.25)
    #expect(update.isMuted)
    #expect(update.micName == "MacBook Air Microphone")
}

// MARK: - Meetings (2026-10-22)

@MainActor @Test func withNoMeetingsTheCallIsUnchanged() {
    let update = Rig().refresh(to: 3)
    #expect(update.state == .live(app: zoom, since: t0))
    #expect(update.meeting == nil)
}

@MainActor @Test func aMatchSticksPastTheEnd() {
    let rig = Rig(holders: [300])
    #expect(rig.minutes(to: 35, meetings: [event("m", start: 0, end: 30)]).meeting?.id == "m")
}

/// Joining 15 minutes early: "On a call" until the meeting's window opens.
@MainActor @Test func aCallJoinedEarlyMatchesWhenTheWindowOpens() {
    let rig = Rig(holders: [300])
    let meetings = [event("m", start: 15, end: 45)]
    #expect(rig.minutes(to: 4, meetings: meetings).meeting == nil)
    #expect(rig.minutes(from: 4 + 1.0 / 60, to: 5, meetings: meetings).meeting?.id == "m")
}

@MainActor @Test func backToBackMovesToTheNextOnceTheFirstHasEnded() {
    let rig = Rig(holders: [300])
    let meetings = [event("a", start: 0, end: 30), event("b", start: 30, end: 60, url: "https://meet.google.com/bbb-bbbb-bbb")]
    #expect(rig.minutes(to: 29, meetings: meetings).meeting?.id == "a")
    #expect(rig.minutes(from: 29 + 1.0 / 60, to: 31, meetings: meetings).meeting?.id == "b")
}

@MainActor @Test func whileTheFirstIsUnderWayTheNextNeverTakesOver() {
    let rig = Rig(holders: [300])
    let meetings = [event("a", start: 0, end: 40), event("b", start: 30, end: 60, url: "https://meet.google.com/bbb-bbbb-bbb")]
    #expect(rig.minutes(to: 35, meetings: meetings).meeting?.id == "a")
}

@MainActor @Test func anExtendedMeetingUpdatesItsEnd() {
    let rig = Rig(holders: [300])
    rig.minutes(to: 1, meetings: [event("a", start: 0, end: 30)])
    let update = rig.minutes(from: 1 + 1.0 / 60, to: 2, meetings: [event("a2", start: 0, end: 45)])
    #expect(update.meeting?.end == t0.addingTimeInterval(45 * 60))
}

@MainActor @Test func aDeletedMeetingKeepsItsLastCopy() {
    let rig = Rig(holders: [300])
    rig.minutes(to: 1, meetings: [event("a", start: 0, end: 30)])
    #expect(rig.minutes(from: 1 + 1.0 / 60, to: 2, meetings: []).meeting?.id == "a")
}

@MainActor @Test func aHandOverMatchesAgain() {
    let rig = Rig(holders: [100])
    // A browser fits both links; the Meet starts nearer the hand-over.
    let meetings = [event("z", start: 0, end: 30, url: "https://us02web.zoom.us/j/1"), event("m", start: 1, end: 30)]
    #expect(rig.minutes(to: 1, meetings: meetings).meeting?.service == .zoom)
    rig.holders = [300]
    #expect(rig.minutes(from: 1 + 1.0 / 60, to: 2, meetings: meetings).meeting?.service == .meet)
}

/// A browser hidden for a forgotten tab shows during a meeting, not before.
@MainActor @Test func aHiddenBrowserShowsOnceAMeetIsUnderWay() {
    let rig = Rig(holders: [300])
    let hidden: Set<String> = [chrome.bundleID]
    let meetings = [event("m", start: 5, end: 30)]
    #expect(rig.minutes(to: 4.9, hidden: hidden, meetings: meetings).state == .idle)
    #expect(rig.minutes(from: 4.9 + 1.0 / 60, to: 5.1, hidden: hidden, meetings: meetings).meeting?.id == "m")
    let alone = Rig(holders: [300])
    #expect(alone.minutes(to: 6, hidden: hidden).state == .idle)
}

@MainActor @Test func aHiddenBrowserStaysThroughTheMeetingsEnd() {
    let rig = Rig(holders: [300])
    let update = rig.minutes(to: 33, hidden: [chrome.bundleID], meetings: [event("m", start: 0, end: 30)])
    #expect(update.state == .live(app: chrome, since: t0))
}

@MainActor @Test func theCameraComesThrough() {
    let rig = Rig()
    rig.camera.isCameraOn = true
    #expect(rig.refresh(to: 3).isCameraOn)
}

// MARK: - Review fixes (2026-10-22)

/// A daily standup that overruns: tomorrow's occurrence, same link and
/// title, must not become this call's meeting.
@MainActor @Test func anOverrunningRecurringMeetingKeepsTodaysEnd() {
    let rig = Rig(holders: [300])
    rig.minutes(to: 14, meetings: [event("s@0", start: 0, end: 15)])
    let update = rig.minutes(from: 14 + 1.0 / 60, to: 17, meetings: [event("s@1440", start: 1440, end: 1455)])
    #expect(update.meeting?.end == t0.addingTimeInterval(15 * 60))
}

@MainActor @Test func afterAnOverrunningRecurringMeetingTheNextStillTakesOver() {
    let rig = Rig(holders: [300])
    rig.minutes(to: 14, meetings: [event("s@0", start: 0, end: 15)])
    let later = [event("s@1440", start: 1440, end: 1455), event("b", start: 15, end: 45, url: "https://meet.google.com/bbb-bbbb-bbb")]
    #expect(rig.minutes(from: 14 + 1.0 / 60, to: 17, meetings: later).meeting?.id == "b")
}

/// A mic switch during a meeting in a hidden browser: the call and the
/// user's mute carry on.
@MainActor @Test func aGapReadInAHiddenMeetingKeepsTheCallAndTheMute() {
    let rig = Rig(holders: [300])
    let hidden: Set<String> = [chrome.bundleID]
    let meetings = [event("m", start: 0, end: 30)]
    rig.minutes(to: 5, hidden: hidden, meetings: meetings)
    rig.service.toggleMute()
    rig.holders = []
    rig.source.announce()
    _ = rig.service.refresh(at: t0.addingTimeInterval(5 * 60 + 0.5), hidden: hidden, meetings: meetings)
    rig.holders = [300]
    let update = rig.minutes(from: 5 + 1.0 / 60, to: 6, hidden: hidden, meetings: meetings)
    #expect(update.state == .live(app: chrome, since: t0))
    #expect(rig.devices.device("a").isMuted)
}

@MainActor @Test func pastTheEndAGapReadDoesNotLoseAHiddenMeeting() {
    let rig = Rig(holders: [300])
    let hidden: Set<String> = [chrome.bundleID]
    let meetings = [event("m", start: 0, end: 30)]
    rig.minutes(to: 35, hidden: hidden, meetings: meetings)
    rig.holders = []
    rig.source.announce()
    _ = rig.service.refresh(at: t0.addingTimeInterval(35 * 60 + 0.5), hidden: hidden, meetings: meetings)
    rig.holders = [300]
    #expect(rig.minutes(from: 35 + 1.0 / 60, to: 36, hidden: hidden, meetings: meetings).state != .idle)
}

/// A forgotten tab in a hidden browser never takes over a real call in
/// the meeting's own app.
@MainActor @Test func aHiddenBrowserNeverTakesOverAVisibleAppsCall() {
    let rig = Rig(holders: [300])
    let hidden: Set<String> = [chrome.bundleID]
    let meetings = [event("z", start: 10, end: 40, url: "https://us02web.zoom.us/j/1")]
    rig.minutes(to: 5, hidden: hidden, meetings: meetings)
    rig.holders = [300, 100]
    #expect(rig.minutes(from: 5 + 1.0 / 60, to: 12, hidden: hidden, meetings: meetings).state == .live(app: zoom, since: t0.addingTimeInterval(5 * 60 + 1)))
}

/// Past the meeting's end, a hidden browser shown as the meeting goes
/// after half an hour rather than staying for good.
@MainActor @Test func aHiddenBrowsersMeetingGoesHalfAnHourAfterItsEnd() {
    let rig = Rig(holders: [300])
    let hidden: Set<String> = [chrome.bundleID]
    let meetings = [event("m", start: 0, end: 30)]
    #expect(rig.minutes(to: 59, hidden: hidden, meetings: meetings).state != .idle)
    #expect(rig.minutes(from: 59 + 1.0 / 60, to: 61, hidden: hidden, meetings: meetings).state == .idle)
}

/// "Not a call" on a matched meeting takes the pill away.
@MainActor @Test func notACallOnAMatchedMeetingTakesItAway() {
    let rig = Rig(holders: [300])
    let meetings = [event("m", start: 0, end: 30)]
    rig.minutes(to: 10, meetings: meetings)
    rig.service.dismissCurrent()
    #expect(rig.minutes(from: 10 + 1.0 / 60, to: 11, hidden: [chrome.bundleID], meetings: meetings).state == .idle)
}

@MainActor @Test func notACallOnAHiddenBrowsersMeetingTakesItAway() {
    let rig = Rig(holders: [300])
    let hidden: Set<String> = [chrome.bundleID]
    let meetings = [event("m", start: 0, end: 30)]
    rig.minutes(to: 10, hidden: hidden, meetings: meetings)
    rig.service.dismissCurrent()
    #expect(rig.minutes(from: 10 + 1.0 / 60, to: 20, hidden: hidden, meetings: meetings).state == .idle)
}

/// CoreMediaIO's first read takes tens of milliseconds; done at start, it
/// never lands on the frame a call's pill animates in (tidy-up, 2026-10-22).
@MainActor @Test func startWarmsTheCamera() {
    let rig = Rig()
    rig.service.start()
    #expect(rig.camera.reads == 1)
}

// MARK: - The meeting's own mute (2026-10-23)

@MainActor @Test func muteUsesTheAppsOwnMuteWhenItHasOne() {
    let rig = Rig()
    rig.appMute.muted = false
    rig.refresh(to: 2)
    rig.service.toggleMute()
    #expect(rig.appMute.presses == 1)
    #expect(!rig.devices.device("a").isMuted)
}

@MainActor @Test func withoutAControlTheSystemMuteIsUsed() {
    let rig = Rig()
    rig.refresh(to: 2)
    rig.service.toggleMute()
    #expect(rig.devices.device("a").isMuted)
    #expect(rig.appMute.presses == 0)
}

/// Muting from Zoom's or Meet's own window shows on the island.
@MainActor @Test func theAppsOwnStateIsWhatTheIslandShows() {
    let rig = Rig()
    rig.appMute.muted = true
    let update = rig.refresh(to: 2)
    #expect(update.isMuted)
    #expect(update.appMuted == true)
    #expect(!rig.devices.device("a").isMuted)
}

/// A system mute from before the app's control was found is undone, never
/// stacked with the app's own.
@MainActor @Test func aSystemMuteIsUndoneWhenTheAppsOwnTakesOver() {
    let rig = Rig()
    rig.refresh(to: 2)
    rig.service.toggleMute()
    #expect(rig.devices.device("a").isMuted)
    rig.appMute.muted = false
    rig.refresh(from: 2.25, to: 2.25)
    rig.service.toggleMute()
    #expect(!rig.devices.device("a").isMuted)
    #expect(rig.appMute.presses == 0)
    #expect(!rig.refresh(from: 2.5, to: 2.5).isMuted)
}

@MainActor @Test func theLiveAppIsHandedToTheControl() {
    let rig = Rig()
    rig.refresh(to: 2)
    #expect(rig.appMute.updatedFor.last == "us.zoom.xos")
    rig.holders = []
    rig.refresh(from: 2.25, to: 6)
    #expect(rig.appMute.updatedFor.last == .some(nil))
}

/// A mic muted outside Ledge (a headset's button): the tap still unmutes
/// (review, 2026-10-23).
@MainActor @Test func aTapUnmutesAMicMutedOutsideLedge() {
    let rig = Rig([mic("a", muted: true)])
    rig.appMute.muted = false
    #expect(rig.refresh(to: 2).isMuted)
    rig.service.toggleMute()
    #expect(!rig.devices.device("a").isMuted)
    #expect(rig.appMute.presses == 0)
    #expect(!rig.refresh(from: 2.25, to: 2.25).isMuted)
}

/// Ledge's own mute keeps covering a mic that starts after the app's
/// control was found (AirPods connecting).
@MainActor @Test func ledgesMuteStillCoversANewMicOnceTheAppsControlIsFound() {
    let rig = Rig([mic("a"), mic("b", running: false)])
    rig.refresh(to: 2)
    rig.service.toggleMute()
    rig.appMute.muted = false
    rig.devices.setRunning("b", true)
    let update = rig.refresh(from: 2.25, to: 2.5)
    #expect(rig.devices.device("b").isMuted)
    #expect(update.isMuted)
}
