import ActivityKit
import Foundation
import Testing
@testable import CallService

private let t0 = Date(timeIntervalSince1970: 1_000)
private let zoom = CallAppInfo(bundleID: "us.zoom.xos", name: "zoom.us", pid: 100)

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
    let source = FakeHolders([100])
    var holders: [pid_t]? {
        get { source.truth }
        set { source.truth = newValue }
    }
    let devices: FakeDevices
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    lazy var service = CallService(
        holders: source,
        devices: devices,
        lookup: ProcessLookup(regularApp: { $0 == 100 ? zoom : nil }, responsiblePID: { _ in nil }, parentPID: { _ in nil }),
        defaults: defaults,
        ownPID: 9
    )

    init(_ devices: [InputDeviceState] = [mic("a")]) { self.devices = FakeDevices(devices) }

    /// Refreshes every quarter second over `seconds` after `t0`, returning
    /// the last update.
    @discardableResult
    func refresh(from: Double = 0, to: Double, hidden: Set<String> = []) -> CallUpdate {
        var update = service.refresh(at: t0.addingTimeInterval(from), hidden: hidden)
        var t = from + 0.25
        while t <= to + 0.0001 {
            update = service.refresh(at: t0.addingTimeInterval(t), hidden: hidden)
            t += 0.25
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
