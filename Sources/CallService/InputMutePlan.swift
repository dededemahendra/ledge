import Foundation

/// One input device as the mute planner sees it (2026-10-22).
public struct InputDeviceState: Sendable, Equatable {
    public let uid: String
    public let name: String
    public let isRunning: Bool
    public let canMute: Bool
    public let isMuted: Bool
    public let canSetVolume: Bool
    public let volume: Float32

    public init(uid: String, name: String, isRunning: Bool, canMute: Bool, isMuted: Bool,
                canSetVolume: Bool, volume: Float32) {
        self.uid = uid
        self.name = name
        self.isRunning = isRunning
        self.canMute = canMute
        self.isMuted = isMuted
        self.canSetVolume = canSetVolume
        self.volume = volume
    }
}

/// What Ledge changed on one device to mute it, kept (and saved) so exactly
/// that can be undone.
public struct MuteChange: Codable, Sendable, Equatable {
    public enum Kind: Codable, Sendable, Equatable {
        case mute
        case volume(previous: Float32)
    }

    public let uid: String
    public let kind: Kind

    public init(uid: String, kind: Kind) {
        self.uid = uid
        self.kind = kind
    }
}

public enum MuteAction: Sendable, Equatable {
    case setMute(uid: String, Bool)
    case setVolume(uid: String, Float32)
}

/// Muting from the island (2026-10-22), as pure decisions. Muting covers
/// every running mic, so a call app on a non-default mic is muted too: the
/// mute flag where a device has one, else its volume to zero with the old
/// volume remembered. Unmute clears anyone's mute — pressing it means
/// wanting to be heard — but restoring at the end of a call undoes only
/// Ledge's own changes, and only where the device is still as Ledge left it.
public enum InputMutePlan {
    public static func mute(_ devices: [InputDeviceState], changes: [MuteChange])
        -> (actions: [MuteAction], changes: [MuteChange]) {
        var actions: [MuteAction] = []
        var merged = changes
        for device in devices where device.isRunning && !device.isMuted && !merged.contains(where: { $0.uid == device.uid }) {
            if device.canMute {
                actions.append(.setMute(uid: device.uid, true))
                merged.append(MuteChange(uid: device.uid, kind: .mute))
            } else if device.canSetVolume {
                actions.append(.setVolume(uid: device.uid, 0))
                merged.append(MuteChange(uid: device.uid, kind: .volume(previous: device.volume)))
            }
        }
        return (actions, merged)
    }

    public static func unmute(_ devices: [InputDeviceState], changes: [MuteChange]) -> [MuteAction] {
        devices.flatMap { device -> [MuteAction] in
            let change = changes.first { $0.uid == device.uid }
            var actions: [MuteAction] = []
            if device.isMuted, device.isRunning || change?.kind == .mute {
                actions.append(.setMute(uid: device.uid, false))
            }
            if case .volume(let previous) = change?.kind {
                actions.append(.setVolume(uid: device.uid, previous))
            }
            return actions
        }
    }

    public static func restore(_ devices: [InputDeviceState], changes: [MuteChange]) -> [MuteAction] {
        changes.compactMap { change in
            guard let device = devices.first(where: { $0.uid == change.uid }) else { return nil }
            switch change.kind {
            case .mute:
                return device.isMuted ? .setMute(uid: device.uid, false) : nil
            case .volume(let previous):
                return device.volume == 0 ? .setVolume(uid: device.uid, previous) : nil
            }
        }
    }

    public static func isMuted(_ devices: [InputDeviceState], changes: [MuteChange]) -> Bool {
        let running = devices.filter(\.isRunning)
        // Read back from the device: a volume Ledge zeroed counts only while
        // it is still zero (turned back up elsewhere, the mic is live).
        return !running.isEmpty && running.allSatisfy { device in
            device.isMuted || (device.volume == 0 && changes.contains { change in
                if case .volume = change.kind { return change.uid == device.uid }
                return false
            })
        }
    }

    /// Ledge's changes that still stand: the device is still muted, or its
    /// volume still zero. One undone elsewhere is Ledge's no longer.
    public static func stillHeld(_ devices: [InputDeviceState], changes: [MuteChange]) -> [MuteChange] {
        changes.filter { change in
            guard let device = devices.first(where: { $0.uid == change.uid }) else { return false }
            switch change.kind {
            case .mute: return device.isMuted
            case .volume: return device.volume == 0
            }
        }
    }

    /// Changes on devices that aren't there (a headset unplugged), still
    /// owed a restore when they come back.
    public static func absent(_ devices: [InputDeviceState], changes: [MuteChange]) -> [MuteChange] {
        changes.filter { change in !devices.contains { $0.uid == change.uid } }
    }

    public static func canMute(_ devices: [InputDeviceState]) -> Bool {
        devices.contains { $0.isRunning && ($0.canMute || $0.canSetVolume) }
    }

    public static func micName(_ devices: [InputDeviceState]) -> String? {
        let running = devices.filter(\.isRunning)
        switch running.count {
        case 0: return nil
        case 1: return running[0].name
        default: return "\(running.count) mics"
        }
    }
}
