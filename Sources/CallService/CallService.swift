import ActivityKit
import Darwin
import Foundation

/// What the island needs from a call, each refresh (2026-10-22).
public struct CallUpdate: Sendable, Equatable {
    public let state: CallState
    public let isMuted: Bool
    public let canMute: Bool
    public let micName: String?

    public init(state: CallState, isMuted: Bool, canMute: Bool, micName: String?) {
        self.state = state
        self.isMuted = isMuted
        self.canMute = canMute
        self.micName = micName
    }
}

/// Calls on the island (2026-10-22): which app holds the mic, for how long,
/// and the island's mute. Asked from the app's quarter-second tick.
///
/// Every mute Ledge applies is undone when the call ends, when its app is
/// marked "Not a call", on `stop()` (Calls switched off, Ledge quitting),
/// and — from the record saved as it changes — on the next `start()` after
/// a crash or a relaunch.
@MainActor
public final class CallService {
    /// Where what Ledge changed to mute is saved, as JSON `[MuteChange]`.
    public static let recordKey = "callMuteChanges"

    public private(set) var availability: ServiceAvailability = .available

    private let holders: MicHolderSource
    private let devices: InputDeviceIO
    private let lookup: ProcessLookup
    private let defaults: UserDefaults
    private let ownPID: pid_t

    private var tracker = CallTracker()
    private var isLive = false
    private var wantsMute = false
    private var changes: [MuteChange] = [] {
        didSet { save() }
    }
    /// Ledge's changes on devices that were gone when they were due to be
    /// undone (a headset unplugged while muted), undone when they return.
    private var owed: [MuteChange] = [] {
        didSet { save() }
    }
    private var lastIdleRead = Date.distantPast
    private var lastOwedTry = Date.distantPast

    public init(holders: MicHolderSource? = nil, devices: InputDeviceIO = CoreAudioInputDevices(),
                lookup: ProcessLookup = .live, defaults: UserDefaults = .standard, ownPID: pid_t = getpid()) {
        self.holders = holders ?? MicHolders()
        self.devices = devices
        self.lookup = lookup
        self.defaults = defaults
        self.ownPID = ownPID
    }

    /// Idempotent. Undoes a mute a crashed or relaunched Ledge left behind.
    public func start() {
        restoreSavedRecord()
        holders.start()
    }

    public func stop() {
        restoreMute()
        holders.stop()
        tracker = CallTracker()
        isLive = false
    }

    public func refresh(at now: Date, hidden: Set<String>) -> CallUpdate {
        // Read again each time while a call is on (its grace included),
        // while anything holds the mic, or while the list couldn't be read:
        // CoreAudio doesn't announce an app letting go when its process
        // stays (a browser tab closing), nor one coming back on a mic that
        // is already running. Idle, once a second while a mic runs, since a
        // call can start on it unannounced; else notifications are enough.
        if isLive || holders.holderPIDs?.isEmpty != true {
            holders.refresh()
        } else if holders.isMicRunning, now.timeIntervalSince(lastIdleRead) >= 1 {
            lastIdleRead = now
            holders.refresh()
        }
        if !owed.isEmpty, now.timeIntervalSince(lastOwedTry) >= 1 {
            lastOwedTry = now
            settleOwed()
        }
        guard let pids = holders.holderPIDs else {
            availability = .unavailable(reason: "can't read which apps use the microphone")
            if isLive { restoreMute() }
            isLive = false
            tracker = CallTracker()
            return CallUpdate(state: .idle, isMuted: false, canMute: false, micName: nil)
        }
        availability = .available

        var seen = Set<String>()
        let apps = pids
            .compactMap { CallApp.resolve($0, ownPID: ownPID, lookup: lookup) }
            .filter { seen.insert($0.bundleID).inserted }
        let state = tracker.update(now: now, holders: apps, hidden: hidden)
        let live = if case .live = state { true } else { false }
        if isLive, !live { restoreMute() }
        isLive = live
        guard live else { return CallUpdate(state: state, isMuted: false, canMute: false, micName: nil) }

        var states = micStates()
        if wantsMute {
            // A mic that starts while muted (AirPods connecting) is muted too.
            // One unmuted elsewhere stays as the user left it.
            let plan = InputMutePlan.mute(states, changes: changes)
            if !plan.actions.isEmpty {
                devices.perform(plan.actions)
                states = micStates()
            }
            if plan.changes != changes { changes = plan.changes }
        }
        return CallUpdate(state: state, isMuted: InputMutePlan.isMuted(states, changes: changes),
                          canMute: InputMutePlan.canMute(states), micName: InputMutePlan.micName(states))
    }

    public func toggleMute() {
        // Plan against what still stands: a mute undone elsewhere is no
        // longer Ledge's to skip.
        let all = devices.states()
        owed += InputMutePlan.absent(all, changes: changes)
        changes = InputMutePlan.stillHeld(all, changes: changes)
        let states = micStates(all)
        if InputMutePlan.isMuted(states, changes: changes) {
            devices.perform(InputMutePlan.unmute(states, changes: changes))
            changes = []
            wantsMute = false
        } else {
            let plan = InputMutePlan.mute(states, changes: changes)
            devices.perform(plan.actions)
            changes = plan.changes
            wantsMute = true
        }
    }

    /// The input devices, with "running" narrowed to the mics the holders
    /// actually use when CoreAudio says which: a headset only playing the
    /// call's sound is not the call's mic.
    private func micStates(_ all: [InputDeviceState]? = nil) -> [InputDeviceState] {
        let all = all ?? devices.states()
        let used = holders.inputDeviceUIDs
        guard !used.isEmpty else { return all }
        return all.map { device in
            InputDeviceState(uid: device.uid, name: device.name, isRunning: device.isRunning && used.contains(device.uid),
                             canMute: device.canMute, isMuted: device.isMuted, canSetVolume: device.canSetVolume,
                             volume: device.volume)
        }
    }

    private func restoreMute() {
        if !changes.isEmpty {
            let states = devices.states()
            devices.perform(InputMutePlan.restore(states, changes: changes))
            owed += InputMutePlan.absent(states, changes: changes)
            changes = []
        }
        wantsMute = false
    }

    /// Undoes what is owed on the devices that are back; keeps the rest.
    private func settleOwed() {
        let states = devices.states()
        devices.perform(InputMutePlan.restore(states, changes: owed))
        owed = InputMutePlan.absent(states, changes: owed)
    }

    private func restoreSavedRecord() {
        guard changes.isEmpty, owed.isEmpty, let data = defaults.data(forKey: Self.recordKey) else { return }
        defaults.removeObject(forKey: Self.recordKey)
        guard let saved = try? JSONDecoder().decode([MuteChange].self, from: data) else { return }
        owed = saved
        settleOwed()
    }

    /// The record holds both what Ledge has changed and what it still owes.
    private func save() {
        let record = changes + owed
        if record.isEmpty {
            defaults.removeObject(forKey: Self.recordKey)
        } else if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: Self.recordKey)
        }
    }
}
