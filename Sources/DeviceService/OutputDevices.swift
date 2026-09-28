import Foundation
import CoreAudio
import OSLog

/// One selectable audio output, for the panel's output picker.
public struct OutputDevice: Sendable, Equatable, Identifiable {
    /// CoreAudio's device UID — stable across reconnects, unlike the id.
    public let id: String
    public let name: String
    public let transport: AudioTransport
    public let isCurrent: Bool

    public init(id: String, name: String, transport: AudioTransport, isCurrent: Bool) {
        self.id = id
        self.name = name
        self.transport = transport
        self.isCurrent = isCurrent
    }

    public var symbolName: String { DeviceEvent.glyph(name: name, transport: transport) }
}

/// Enumerates output-capable audio devices, marks the default, and sets a
/// new default on request — the spec's "output switching in the expanded
/// panel via `AudioObjectSetPropertyData`". No permission. Re-enumerates
/// whenever the device list or the default output changes.
@MainActor
final class OutputDeviceCatalog {
    nonisolated private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "device.outputs")

    private let onChange: ([OutputDevice]) -> Void
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    init(onChange: @escaping ([OutputDevice]) -> Void) {
        self.onChange = onChange
    }

    private nonisolated static func systemAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    func start() {
        guard listeners.isEmpty else { return }
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var addr = Self.systemAddress(selector)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
            if status == noErr { listeners.append((addr, block)) } else { Self.log.error("outputs listener failed: \(status)") }
        }
        refresh()
    }

    func stop() {
        for (address, block) in listeners {
            var addr = address
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, DispatchQueue.main, block)
        }
        listeners.removeAll()
    }

    func refresh() {
        onChange(Self.currentOutputs())
    }

    /// Every device with at least one output stream, in CoreAudio's order,
    /// the default output flagged.
    nonisolated static func currentOutputs() -> [OutputDevice] {
        var addr = systemAddress(kAudioHardwarePropertyDevices)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

        let current = OutputRouteObserver.currentRoute()?.uid
        return ids.compactMap { device in
            guard hasOutputStreams(device),
                  let uid = OutputRouteObserver.string(kAudioDevicePropertyDeviceUID, of: device),
                  let name = OutputRouteObserver.string(kAudioObjectPropertyName, of: device) else { return nil }
            var transportAddr = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
            )
            var raw = UInt32(0)
            var rawSize = UInt32(MemoryLayout<UInt32>.size)
            _ = AudioObjectGetPropertyData(device, &transportAddr, 0, nil, &rawSize, &raw)
            return OutputDevice(id: uid, name: name, transport: OutputRouteObserver.transport(fromRaw: raw), isCurrent: uid == current)
        }
    }

    private nonisolated static func hasOutputStreams(_ device: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr else { return false }
        return size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    /// Makes the device with this UID the default output. `false` when no
    /// such device is present any more or CoreAudio refuses.
    @discardableResult
    nonisolated static func setDefaultOutput(uid: String) -> Bool {
        var addr = systemAddress(kAudioHardwarePropertyDevices)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return false }
        var ids = [AudioDeviceID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return false }
        guard var target = ids.first(where: { OutputRouteObserver.string(kAudioDevicePropertyDeviceUID, of: $0) == uid }) else { return false }

        var defaultAddr = systemAddress(kAudioHardwarePropertyDefaultOutputDevice)
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddr, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &target
        )
        if status != noErr { log.error("set default output failed: \(status)") }
        return status == noErr
    }
}
