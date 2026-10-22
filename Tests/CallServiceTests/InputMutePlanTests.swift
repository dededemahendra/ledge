import Testing
@testable import CallService

private func mic(_ uid: String, name: String = "Mic", running: Bool = true, canMute: Bool = true, muted: Bool = false,
                 canSetVolume: Bool = true, volume: Float32 = 0.5) -> InputDeviceState {
    InputDeviceState(uid: uid, name: name, isRunning: running, canMute: canMute, isMuted: muted,
                     canSetVolume: canSetVolume, volume: volume)
}

@Test func muteUsesTheMuteFlagWhereItCan() {
    let plan = InputMutePlan.mute([mic("a")], changes: [])
    #expect(plan.actions == [.setMute(uid: "a", true)])
    #expect(plan.changes == [MuteChange(uid: "a", kind: .mute)])
}

@Test func muteFallsBackToVolumeZeroAndRemembersIt() {
    let plan = InputMutePlan.mute([mic("a", canMute: false, volume: 0.7)], changes: [])
    #expect(plan.actions == [.setVolume(uid: "a", 0)])
    #expect(plan.changes == [MuteChange(uid: "a", kind: .volume(previous: 0.7))])
}

@Test func aDeviceThatCanDoNeitherIsLeftAndReported() {
    let devices = [mic("a", canMute: false, canSetVolume: false)]
    #expect(InputMutePlan.mute(devices, changes: []).actions.isEmpty)
    #expect(InputMutePlan.canMute(devices) == false)
}

@Test func onlyRunningDevicesAreMuted() {
    let plan = InputMutePlan.mute([mic("a"), mic("b", running: false)], changes: [])
    #expect(plan.actions == [.setMute(uid: "a", true)])
}

/// Someone pressing unmute on a call wants to be heard, whoever muted it.
@Test func unmuteClearsAnOutsideMuteToo() {
    #expect(InputMutePlan.unmute([mic("a", muted: true)], changes: []) == [.setMute(uid: "a", false)])
}

/// The call ending undoes only Ledge's own mute.
@Test func restoreLeavesAnOutsideMuteAlone() {
    #expect(InputMutePlan.restore([mic("a", muted: true)], changes: []).isEmpty)
}

@Test func restorePutsBackExactlyWhatLedgeChanged() {
    let devices = [mic("a", muted: true), mic("b", canMute: false, volume: 0)]
    let changes = [MuteChange(uid: "a", kind: .mute), MuteChange(uid: "b", kind: .volume(previous: 0.7))]
    #expect(InputMutePlan.restore(devices, changes: changes) == [.setMute(uid: "a", false), .setVolume(uid: "b", 0.7)])
}

@Test func restoreSkipsADeviceTheUserChangedSince() {
    let devices = [mic("b", canMute: false, volume: 0.4)]
    #expect(InputMutePlan.restore(devices, changes: [MuteChange(uid: "b", kind: .volume(previous: 0.7))]).isEmpty)
}

@Test func mutedMeansEveryRunningMicIsMuted() {
    #expect(InputMutePlan.isMuted([mic("a", muted: true), mic("b")], changes: []) == false)
    #expect(InputMutePlan.isMuted([mic("a", muted: true), mic("b", muted: true)], changes: []) == true)
    #expect(InputMutePlan.isMuted([mic("a", running: false, muted: true)], changes: []) == false)
    #expect(InputMutePlan.isMuted([mic("b", canMute: false, volume: 0)],
                                  changes: [MuteChange(uid: "b", kind: .volume(previous: 0.7))]) == true)
}

@Test func theMicNameIsOneNameOrACount() {
    #expect(InputMutePlan.micName([mic("a", name: "MacBook Air Microphone"), mic("b", running: false)])
            == "MacBook Air Microphone")
    #expect(InputMutePlan.micName([mic("a"), mic("b")]) == "2 mics")
    #expect(InputMutePlan.micName([mic("a", running: false)]) == nil)
}

/// Turning the input back up in System Settings unmutes, as far as the
/// island can tell (review, 2026-10-22).
@Test func aVolumeRaisedElsewhereIsNoLongerMuted() {
    let devices = [mic("b", canMute: false, volume: 0.4)]
    #expect(InputMutePlan.isMuted(devices, changes: [MuteChange(uid: "b", kind: .volume(previous: 0.7))]) == false)
}

@Test func stillHeldDropsWhatTheUserUndidElsewhere() {
    let devices = [mic("a"), mic("b", canMute: false, volume: 0)]
    let changes = [MuteChange(uid: "a", kind: .mute), MuteChange(uid: "b", kind: .volume(previous: 0.7))]
    #expect(InputMutePlan.stillHeld(devices, changes: changes) == [MuteChange(uid: "b", kind: .volume(previous: 0.7))])
}

@Test func absentListsTheChangesOnDevicesThatAreGone() {
    let changes = [MuteChange(uid: "a", kind: .mute), MuteChange(uid: "x", kind: .mute)]
    #expect(InputMutePlan.absent([mic("a")], changes: changes) == [MuteChange(uid: "x", kind: .mute)])
}
