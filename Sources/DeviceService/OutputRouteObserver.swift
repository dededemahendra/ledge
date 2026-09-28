import Foundation
import CoreAudio
import OSLog

/// Reports the default output device whenever it changes, by UID, name and
/// transport. The baseline/announce decision lives in `DeviceEventDeriver`.
@MainActor
final class OutputRouteObserver {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "device.route")

    struct Route: Equatable {
        let uid: String
        let name: String
        let transport: AudioTransport
    }

    private let onChange: (Route) -> Void
    private var listener: AudioObjectPropertyListenerBlock?
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    init(onChange: @escaping (Route) -> Void) {
        self.onChange = onChange
    }

    func start() {
        guard listener == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.emit() }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block
        )
        if status == noErr { listener = block } else { Self.log.error("route listener failed: \(status)") }
        emit()   // baseline
    }

    func stop() {
        guard let listener else { return }
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
        )
        self.listener = nil
    }

    private func emit() {
        guard let route = Self.currentRoute() else { return }
        onChange(route)
    }

    static func currentRoute() -> Route? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }

        guard let uid = string(kAudioDevicePropertyDeviceUID, of: device),
              let name = string(kAudioObjectPropertyName, of: device) else { return nil }

        var transportAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var raw = UInt32(0)
        var rawSize = UInt32(MemoryLayout<UInt32>.size)
        _ = AudioObjectGetPropertyData(device, &transportAddr, 0, nil, &rawSize, &raw)
        return Route(uid: uid, name: name, transport: transport(fromRaw: raw))
    }

    nonisolated static func transport(fromRaw raw: UInt32) -> AudioTransport {
        switch raw {
        case kAudioDeviceTransportTypeBuiltIn:                                   return .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
        case kAudioDeviceTransportTypeUSB:                                       return .usb
        case kAudioDeviceTransportTypeHDMI:                                      return .hdmi
        case kAudioDeviceTransportTypeDisplayPort:                               return .displayPort
        case kAudioDeviceTransportTypeAirPlay:                                   return .airPlay
        default:                                                                 return .other
        }
    }

    private static func string(_ selector: AudioObjectPropertySelector, of device: AudioDeviceID) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
