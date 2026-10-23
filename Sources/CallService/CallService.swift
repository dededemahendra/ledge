import ActivityKit
import Darwin
import Foundation

/// What the island needs from a call, each refresh (2026-10-22).
public struct CallUpdate: Sendable, Equatable {
    public let state: CallState
    public let isMuted: Bool
    public let canMute: Bool
    public let micName: String?
    /// The calendar meeting this call is, when it is one (2026-10-22).
    public let meeting: CallMeeting?
    public let isCameraOn: Bool
    /// The call app's own mute, when Ledge can read it (Zoom, Meet;
    /// 2026-10-23). `isMuted` is true when this is, or Ledge's system mute.
    public let appMuted: Bool?

    public init(state: CallState, isMuted: Bool, canMute: Bool, micName: String?, meeting: CallMeeting? = nil,
                isCameraOn: Bool = false, appMuted: Bool? = nil) {
        self.state = state
        self.isMuted = isMuted
        self.canMute = canMute
        self.micName = micName
        self.meeting = meeting
        self.isCameraOn = isCameraOn
        self.appMuted = appMuted
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
    private let camera: CameraSource
    private let appMute: AppMuteSource
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

    /// The live call's meeting, the app it was matched for, and a hidden
    /// app kept showing for as long as that match lasts (2026-10-22).
    private var matched: CallMeeting?
    private var matchedApp: String?
    private var exemptApp: String?
    /// Meetings the user marked "Not a call", as "bundle id|meeting id".
    private var dismissed: Set<String> = []

    /// How long past its meeting's end a hidden app shown as that meeting
    /// stays (review, 2026-10-22): a real meeting can overrun; a forgotten
    /// tab after a skipped one shouldn't stay for good.
    public static let hiddenOverrun: TimeInterval = 30 * 60

    public init(holders: MicHolderSource? = nil, devices: InputDeviceIO = CoreAudioInputDevices(),
                camera: CameraSource? = nil, appMute: AppMuteSource? = nil, lookup: ProcessLookup = .live,
                defaults: UserDefaults = .standard,
                ownPID: pid_t = getpid()) {
        self.holders = holders ?? MicHolders()
        self.devices = devices
        self.camera = camera ?? CameraWatcher()
        self.appMute = appMute ?? AXAppMuteControls()
        self.lookup = lookup
        self.defaults = defaults
        self.ownPID = ownPID
    }

    /// Idempotent. Undoes a mute a crashed or relaunched Ledge left behind.
    public func start() {
        restoreSavedRecord()
        holders.start()
        // CoreMediaIO's first read takes tens of milliseconds: pay it here,
        // not on the frame a call's pill animates in.
        camera.refresh()
    }

    public func stop() {
        restoreMute()
        holders.stop()
        tracker = CallTracker()
        isLive = false
    }

    public func refresh(at now: Date, hidden: Set<String>, meetings: [MeetingCandidate] = []) -> CallUpdate {
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
            appMute.update(for: nil)
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
        // A hidden app still shows while it is a meeting under way and no
        // visible app holds the mic, and then for as long as that match
        // lasts, up to half an hour past its end — read whether or not it
        // holds the mic this tick, so a mic switch doesn't drop it.
        var exempt = Set<String>()
        if let kept = exemptApp, let meeting = matched, now < meeting.end.addingTimeInterval(Self.hiddenOverrun),
           !dismissed.contains("\(kept)|\(meeting.id)") {
            exempt.insert(kept)
        }
        if !apps.contains(where: { !hidden.contains($0.bundleID) }) {
            for app in apps where hidden.contains(app.bundleID) {
                if let meeting = CallMeetingMatcher.match(bundleID: app.bundleID, at: now, in: meetings, requireUnderWay: true),
                   !dismissed.contains("\(app.bundleID)|\(meeting.id)") {
                    exempt.insert(app.bundleID)
                }
            }
        }
        let state = tracker.update(now: now, holders: apps, hidden: hidden.subtracting(exempt))
        let live = if case .live = state { true } else { false }
        if isLive, !live { restoreMute() }
        isLive = live
        guard case .live(let app, _) = state else {
            matched = nil
            matchedApp = nil
            exemptApp = nil
            appMute.update(for: nil)
            return CallUpdate(state: state, isMuted: false, canMute: false, micName: nil)
        }
        updateMeeting(for: app.bundleID, at: now, in: meetings, isHidden: hidden.contains(app.bundleID))
        camera.refresh()
        appMute.update(for: app)
        let appMuted = appMute.muted

        var states = micStates()
        // Ledge's own system mute, while it holds, covers a mic that starts
        // (AirPods connecting) — with or without the app's own control: a
        // tap with the control known clears it, so it never stacks.
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
        return CallUpdate(state: state, isMuted: appMuted == true || InputMutePlan.isMuted(states, changes: changes),
                          canMute: appMuted != nil || InputMutePlan.canMute(states), micName: InputMutePlan.micName(states),
                          meeting: matched, isCameraOn: camera.isCameraOn, appMuted: appMuted)
    }

    /// Keeps the live call's meeting (2026-10-22): matched afresh for a new
    /// app; looked for again on every refresh until it has one (a call
    /// joined early takes its meeting when the window opens); once matched,
    /// kept past its end, re-read by link and title so an edit shows; and
    /// once ended, given up for the next meeting in its window (back to
    /// back in the same app).
    private func updateMeeting(for bundleID: String, at now: Date, in meetings: [MeetingCandidate], isHidden: Bool) {
        func fresh() -> CallMeeting? {
            CallMeetingMatcher.match(bundleID: bundleID, at: now, in: meetings, requireUnderWay: isHidden)
        }
        if matchedApp != bundleID || matched == nil {
            matched = fresh()
        } else if let current = matched {
            var kept = current
            // The same occurrence, or an edited copy that could be this
            // meeting now — never a later occurrence of a recurring series,
            // which shares its link and title.
            let edited = meetings.first { $0.id == current.id } ?? meetings.first {
                $0.joinURL == current.joinURL && $0.title == current.title
                    && $0.start.addingTimeInterval(-CallMeetingMatcher.lead) <= now
            }
            if let edited {
                kept = CallMeeting(id: edited.id, title: edited.title, start: edited.start, end: edited.end,
                                   joinURL: current.joinURL, service: current.service)
            }
            if kept.end <= now, let next = fresh(), next.id != kept.id {
                kept = next
            }
            matched = kept
        }
        matchedApp = bundleID
        exemptApp = isHidden && matched != nil ? bundleID : nil
    }

    /// "Not a call" on the live call's meeting (review, 2026-10-22): no
    /// longer shown as that meeting, so hiding its app takes it away.
    public func dismissCurrent() {
        guard let app = matchedApp, let meeting = matched else { return }
        dismissed.insert("\(app)|\(meeting.id)")
        if exemptApp == app { exemptApp = nil }
    }

    public func toggleMute() {
        // Zoom's or Meet's own mute when Ledge can reach it (2026-10-23):
        // Ledge's system mute is undone first, so the two never stack, and
        // the app's control is pressed only if it isn't already as wanted.
        if let appMuted = appMute.muted {
            let all = devices.states()
            let held = InputMutePlan.stillHeld(all, changes: changes)
            let states = micStates(all)
            let systemMuted = InputMutePlan.isMuted(states, changes: held)
            let target = !(appMuted || systemMuted)
            if systemMuted {
                // Whoever muted the mic — Ledge, a headset's button — a tap
                // meaning "unmute" clears it, as without the app's control.
                owed += InputMutePlan.absent(all, changes: changes)
                devices.perform(InputMutePlan.unmute(states, changes: held))
                changes = []
                wantsMute = false
            } else {
                restoreMute()
            }
            _ = appMute.setMuted(target)
            return
        }
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
