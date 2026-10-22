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
        // While anything holds the mic, read again each time: CoreAudio
        // doesn't announce an app letting go when its process stays (a
        // browser tab closing), nor one leaving while another keeps the mic
        // running. Idle, the source's own notifications are enough.
        if holders.holderPIDs?.isEmpty == false { holders.refresh() }
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

        var states = devices.states()
        if wantsMute {
            // A mic that starts while muted (AirPods connecting) is muted too.
            let plan = InputMutePlan.mute(states, changes: changes)
            if !plan.actions.isEmpty {
                devices.perform(plan.actions)
                states = devices.states()
            }
            if plan.changes != changes { changes = plan.changes }
        }
        return CallUpdate(state: state, isMuted: InputMutePlan.isMuted(states, changes: changes),
                          canMute: InputMutePlan.canMute(states), micName: InputMutePlan.micName(states))
    }

    public func toggleMute() {
        let states = devices.states()
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

    private func restoreMute() {
        if !changes.isEmpty {
            devices.perform(InputMutePlan.restore(devices.states(), changes: changes))
            changes = []
        }
        wantsMute = false
    }

    private func restoreSavedRecord() {
        guard changes.isEmpty, let data = defaults.data(forKey: Self.recordKey) else { return }
        if let saved = try? JSONDecoder().decode([MuteChange].self, from: data) {
            devices.perform(InputMutePlan.restore(devices.states(), changes: saved))
        }
        defaults.removeObject(forKey: Self.recordKey)
    }

    private func save() {
        if changes.isEmpty {
            defaults.removeObject(forKey: Self.recordKey)
        } else if let data = try? JSONEncoder().encode(changes) {
            defaults.set(data, forKey: Self.recordKey)
        }
    }
}
