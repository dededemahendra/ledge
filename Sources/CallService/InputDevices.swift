import CoreAudio
import Foundation
import os

/// Reads and changes the input devices (2026-10-22). A protocol so the
/// service can be tested on made-up devices.
@MainActor
public protocol InputDeviceIO {
    func states() -> [InputDeviceState]
    func perform(_ actions: [MuteAction])
}

/// The real input devices: every CoreAudio device with input streams, its
/// mute flag and volume on the input scope's main element.
@MainActor
public final class CoreAudioInputDevices: InputDeviceIO {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "call")
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    public init() {}

    public func states() -> [InputDeviceState] {
        Self.inputDevices().compactMap { id in
            guard let uid = Self.string(id, Self.address(kAudioDevicePropertyDeviceUID)) else { return nil }
            let mute = Self.address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput)
            let volume = Self.address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput)
            return InputDeviceState(
                uid: uid,
                name: Self.string(id, Self.address(kAudioObjectPropertyName)) ?? uid,
                isRunning: (Self.value(id, Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere), UInt32(0)) ?? 0) != 0,
                canMute: Self.isSettable(id, mute),
                isMuted: (Self.value(id, mute, UInt32(0)) ?? 0) != 0,
                canSetVolume: Self.isSettable(id, volume),
                volume: Self.value(id, volume, Float32(0)) ?? 0
            )
        }
    }

    public func perform(_ actions: [MuteAction]) {
        let ids = Dictionary(Self.inputDevices().compactMap { id in
            Self.string(id, Self.address(kAudioDevicePropertyDeviceUID)).map { ($0, id) }
        }, uniquingKeysWith: { first, _ in first })
        for action in actions {
            switch action {
            case .setMute(let uid, let muted):
                guard let id = ids[uid] else { continue }
                Self.write(id, Self.address(kAudioDevicePropertyMute, kAudioObjectPropertyScopeInput), UInt32(muted ? 1 : 0))
            case .setVolume(let uid, let volume):
                guard let id = ids[uid] else { continue }
                Self.write(id, Self.address(kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyScopeInput), volume)
            }
        }
    }

    // MARK: - CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func inputDevices() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { id in
            var streams = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
            var streamSize: UInt32 = 0
            return AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr && streamSize > 0
        }
    }

    private static func value<T: BitwiseCopyable>(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, _ zero: T) -> T? {
        var addr = address
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var value = zero
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    private static func string(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        var addr = address
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func isSettable(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var addr = address
        guard AudioObjectHasProperty(id, &addr) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(id, &addr, &settable) == noErr && settable.boolValue
    }

    private static func write<T: BitwiseCopyable>(_ id: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: T) {
        var addr = address
        var value = value
        let status = AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<T>.size), &value)
        if status != noErr { log.error("input device write failed: \(status)") }
    }
}
