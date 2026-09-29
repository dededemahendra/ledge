import Foundation
import CoreAudio
// kAudioHardwareServiceDeviceProperty_VirtualMainVolume lives in AudioToolbox's
// AudioHardwareService.h, not CoreAudio — the Bluetooth/aggregate-device fallback
// (Review Focus 2) needs this import to resolve.
import AudioToolbox
import ActivityKit
import OSLog

public struct VolumeReading: Sendable, Equatable {
    public let level: Double
    public let muted: Bool

    public init(level: Double, muted: Bool) {
        self.level = min(1, max(0, level))
        self.muted = muted
    }
}

/// Which CoreAudio property actually carries this device's volume.
public enum VolumeStrategy: Sendable, Equatable {
    case perChannelScalar
    case virtualMainVolume
    case unavailable
}

/// Observes the default output device's volume *by value*, so no permission is
/// needed and menu bar / Control Centre changes are caught as well as key presses.
///
/// Rebinds when the default output device changes — otherwise the listener stays
/// attached to a device nobody is using any more (Review Focus 1).
@MainActor
public final class VolumeObserver {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "volume")

    /// Everything needed to remove a listener block later. CoreAudio's remove
    /// call must be given the exact same object, address (selector/scope/
    /// element), dispatch queue, and *block reference* used to add it — the
    /// framework Block_copy's the block on add and matches by identity on
    /// remove, so a freshly-built equivalent closure will not do.
    private struct InstalledListener {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    public private(set) var availability: ServiceAvailability = .available

    private let onChange: (VolumeReading) -> Void
    /// Fired every time the listeners are re-pointed at a (possibly new)
    /// default output device, BEFORE that device's current level is
    /// emitted. `HUDService` uses it to drop the deriver's volume baseline,
    /// so plugging in AirPods (which remember their own level) does not
    /// fire a "Sound" HUD nobody asked for. This is the call the comment in
    /// `rebind()` always promised existed at the call site — and did not,
    /// until 2026-09-28.
    public var onRebind: (() -> Void)?
    private var device = AudioDeviceID(kAudioObjectUnknown)
    private var strategy: VolumeStrategy = .unavailable
    private var installedDeviceListener: InstalledListener?
    private var installedVolumeListeners: [InstalledListener] = []

    public init(onChange: @escaping (VolumeReading) -> Void) {
        self.onChange = onChange
    }

    // MARK: - pure decisions

    // `nonisolated`: these are pure functions of their parameters with no
    // access to actor state. Without this, `@MainActor` on the class would
    // make them implicitly async from a synchronous test context, which the
    // brief's own tests call them from directly.
    /// Virtual main volume first (review, 2026-09-29): it is the property
    /// the system's own keys and `VolumeControl` write, so reading it keeps
    /// the observer and the key interceptor on one number — on a device
    /// exposing both, the per-channel scalar need not track it in lockstep.
    /// Scalar is the fallback for devices without a virtual main.
    nonisolated public static func strategy(hasScalar: Bool, hasVirtualMain: Bool) -> VolumeStrategy {
        if hasVirtualMain { return .virtualMainVolume }
        if hasScalar { return .perChannelScalar }
        return .unavailable
    }

    nonisolated public static func availability(for strategy: VolumeStrategy) -> ServiceAvailability {
        strategy == .unavailable
            ? .unavailable(reason: "output device reports no volume control")
            : .available
    }

    // MARK: - lifecycle

    public func start() {
        installDefaultDeviceListener()
        rebind()
    }

    public func stop() {
        removeVolumeListener()
        removeDefaultDeviceListener()
    }

    // MARK: - binding

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private func installDefaultDeviceListener() {
        guard installedDeviceListener == nil else { return }
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let objectID = AudioObjectID(kAudioObjectSystemObject)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.rebind() }
        }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &addr, DispatchQueue.main, block)
        if status == noErr {
            installedDeviceListener = InstalledListener(objectID: objectID, address: addr, block: block)
        } else {
            Self.log.error("default-device listener failed: \(status)")
        }
    }

    /// Fix (Review Focus 1): the previous version only flipped a `Bool` here
    /// and never called `AudioObjectRemovePropertyListenerBlock`, so the
    /// listener survived `stop()` and kept firing into a torn-down observer.
    private func removeDefaultDeviceListener() {
        guard let listener = installedDeviceListener else { return }
        var addr = listener.address
        let status = AudioObjectRemovePropertyListenerBlock(
            listener.objectID, &addr, DispatchQueue.main, listener.block
        )
        if status != noErr {
            Self.log.error("default-device listener removal failed: \(status)")
        }
        installedDeviceListener = nil
    }

    private func currentDefaultOutputDevice() -> AudioDeviceID? {
        var addr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id
        )
        guard status == noErr, id != kAudioObjectUnknown else { return nil }
        return id
    }

    /// Re-points every listener at whatever the current default output device is.
    private func rebind() {
        removeVolumeListener()

        guard let id = currentDefaultOutputDevice() else {
            availability = .unavailable(reason: "no default output device")
            return
        }
        device = id

        var scalar = Self.address(
            kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput
        )
        var virtualMain = Self.address(
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            scope: kAudioDevicePropertyScopeOutput
        )

        strategy = Self.strategy(
            hasScalar: AudioObjectHasProperty(device, &scalar),
            hasVirtualMain: AudioObjectHasProperty(device, &virtualMain)
        )
        availability = Self.availability(for: strategy)

        guard strategy != .unavailable else {
            Self.log.info("device \(self.device) exposes no volume control")
            return
        }

        let volumeAddress = strategy == .perChannelScalar ? scalar : virtualMain
        let muteAddress = Self.address(
            kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput
        )

        // Same block reference installed at two addresses; removal tracks
        // each (address) pairing separately since CoreAudio matches on the
        // full (object, address, queue, block) tuple, not the block alone.
        let handler: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.emit() }
        }

        var mutableVolumeAddress = volumeAddress
        let volumeStatus = AudioObjectAddPropertyListenerBlock(
            device, &mutableVolumeAddress, DispatchQueue.main, handler
        )
        if volumeStatus == noErr {
            installedVolumeListeners.append(
                InstalledListener(objectID: device, address: volumeAddress, block: handler)
            )
        } else {
            Self.log.error("volume listener failed: \(volumeStatus)")
        }

        var mutableMuteAddress = muteAddress
        let muteStatus = AudioObjectAddPropertyListenerBlock(
            device, &mutableMuteAddress, DispatchQueue.main, handler
        )
        if muteStatus == noErr {
            installedVolumeListeners.append(
                InstalledListener(objectID: device, address: muteAddress, block: handler)
            )
        } else {
            Self.log.error("mute listener failed: \(muteStatus)")
        }

        // Re-baseline: the new device's level is not a change the user made.
        // `onRebind` lets the call site drop its baseline first; this
        // observer then just reports what CoreAudio says now, which the
        // deriver records silently.
        onRebind?()
        emit()
    }

    /// Fix (Review Focus 1): previously only flipped a `Bool`. Worse, `rebind()`
    /// calls this before installing a new listener, so every output-device
    /// change leaked another live listener on the old device — plug in AirPods
    /// a few times and several stale listeners fire together. Now actually
    /// removes every installed (address, block) pairing before clearing state.
    private func removeVolumeListener() {
        for listener in installedVolumeListeners {
            var addr = listener.address
            let status = AudioObjectRemovePropertyListenerBlock(
                listener.objectID, &addr, DispatchQueue.main, listener.block
            )
            if status != noErr {
                Self.log.error("volume listener removal failed: \(status)")
            }
        }
        installedVolumeListeners.removeAll()
    }

    // MARK: - reading

    private func read() -> VolumeReading? {
        guard strategy != .unavailable else { return nil }

        var addr = strategy == .perChannelScalar
            ? Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
            : Self.address(
                kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
                scope: kAudioDevicePropertyScopeOutput
              )

        var level = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &level) == noErr else {
            return nil
        }

        var muteAddr = Self.address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
        var muted = UInt32(0)
        var muteSize = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &muteAddr) {
            _ = AudioObjectGetPropertyData(device, &muteAddr, 0, nil, &muteSize, &muted)
        }

        return VolumeReading(level: Double(level), muted: muted == 1)
    }

    /// `HUDEventDeriver` already owns baseline suppression; this only ever
    /// forwards what CoreAudio currently reports.
    private func emit() {
        guard let reading = read() else { return }
        onChange(reading)
    }
}
