import CoreAudio
import Foundation
import os

/// Which processes hold the mic right now (2026-10-22), from CoreAudio's
/// process objects. Reads again whenever the process list changes or an
/// input device starts or stops running somewhere — CoreAudio announces
/// those, but not a process's own "running input", which never notifies
/// (checked 2026-10-22: a process's running flags stay silent while its
/// device's flips every time). What neither announces, `CallService`
/// catches by calling `refresh()` while anything holds the mic.
/// `holderPIDs` is `nil` when the list can't be read.
/// Who holds the mic (2026-10-22). A protocol so the service can be tested
/// on a source that, like CoreAudio, doesn't announce every change.
@MainActor
public protocol MicHolderSource: AnyObject {
    /// The PIDs holding the mic as last read; `nil` when the list can't be
    /// read.
    var holderPIDs: [pid_t]? { get }
    /// Whether any input device is running somewhere: a call can start on
    /// it without CoreAudio announcing anything.
    var isMicRunning: Bool { get }
    /// The input devices the holders use for input, by UID; empty when
    /// unknown.
    var inputDeviceUIDs: Set<String> { get }
    func start()
    func stop()
    /// Reads again now, for what CoreAudio doesn't announce.
    func refresh()
}

@MainActor
final class MicHolders: MicHolderSource {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "call")
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    /// Removal must be handed the exact block that was added (CoreAudio
    /// matches it by identity), so each one is kept with its address.
    private struct InstalledListener {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    /// Nothing until started; `nil` only once a read has failed.
    /// Nothing until started; `nil` only once a read has failed.
    private(set) var holderPIDs: [pid_t]? = []
    private(set) var isMicRunning = false
    private(set) var inputDeviceUIDs: Set<String> = []
    private var systemListeners: [InstalledListener] = []
    private var deviceListeners: [InstalledListener] = []

    func start() {
        guard systemListeners.isEmpty else { return }
        systemListeners = [
            Self.listen(Self.system, Self.address(kAudioHardwarePropertyProcessObjectList)) { [weak self] in
                self?.read()
            },
            Self.listen(Self.system, Self.address(kAudioHardwarePropertyDevices)) { [weak self] in
                self?.relistenToDevices()
            },
        ].compactMap { $0 }
        relistenToDevices()
    }

    func stop() {
        systemListeners.forEach(Self.remove)
        systemListeners.removeAll()
        deviceListeners.forEach(Self.remove)
        deviceListeners.removeAll()
        holderPIDs = []
    }

    /// One "running somewhere" listener per input device, renewed when a
    /// device comes or goes (AirPods connecting mid-call).
    private func relistenToDevices() {
        deviceListeners.forEach(Self.remove)
        deviceListeners = Self.inputDevices().compactMap { device in
            Self.listen(device, Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)) { [weak self] in
                self?.readNowAndSoon()
            }
        }
        read()
    }

    func refresh() { read() }

    /// A device can flip to running a moment before the process taking it
    /// says so, and that second flip is never announced: read now, and
    /// again shortly after.
    private func readNowAndSoon() {
        read()
        for delay in [0.3, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.read() }
            }
        }
    }

    private func read() {
        let inputs = Self.inputDevices()
        isMicRunning = inputs.contains { device in
            var running = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            return AudioObjectGetPropertyData(device, &running, 0, nil, &size, &value) == noErr && value != 0
        }
        guard let processes = Self.processes() else {
            holderPIDs = nil
            inputDeviceUIDs = []
            return
        }
        var pids: [pid_t] = []
        var used: Set<String> = []
        for process in processes {
            var running = Self.address(kAudioProcessPropertyIsRunningInput)
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(process, &running, 0, nil, &size, &value) == noErr, value != 0 else { continue }
            var pidAddress = Self.address(kAudioProcessPropertyPID)
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(process, &pidAddress, 0, nil, &pidSize, &pid) == noErr else { continue }
            pids.append(pid)
            used.formUnion(Self.inputDeviceUIDs(of: process))
        }
        holderPIDs = pids
        inputDeviceUIDs = used
    }

    // MARK: - CoreAudio

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    private static func processes() -> [AudioObjectID]? {
        var addr = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return nil }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return nil }
        return ids
    }

    /// The devices a process uses for input, by UID.
    private static func inputDeviceUIDs(of process: AudioObjectID) -> Set<String> {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyDevices, mScope: kAudioObjectPropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(process, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(process, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return Set(ids.compactMap { id in
            var uidAddress = address(kAudioDevicePropertyDeviceUID)
            var uid: Unmanaged<CFString>?
            var uidSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &uidAddress, 0, nil, &uidSize, &uid) == noErr else { return nil }
            return uid?.takeRetainedValue() as String?
        })
    }

    private static func inputDevices() -> [AudioObjectID] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.filter { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams,
                                                     mScope: kAudioObjectPropertyScopeInput,
                                                     mElement: kAudioObjectPropertyElementMain)
            var streamSize: UInt32 = 0
            return AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr && streamSize > 0
        }
    }

    private static func listen(_ objectID: AudioObjectID, _ address: AudioObjectPropertyAddress,
                               _ action: @escaping @MainActor () -> Void) -> InstalledListener? {
        var addr = address
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { action() }
        }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &addr, DispatchQueue.main, block)
        guard status == noErr else {
            log.error("mic listener failed: \(status)")
            return nil
        }
        return InstalledListener(objectID: objectID, address: addr, block: block)
    }

    private static func remove(_ listener: InstalledListener) {
        var addr = listener.address
        let status = AudioObjectRemovePropertyListenerBlock(listener.objectID, &addr, DispatchQueue.main, listener.block)
        // A device or process already gone has taken its listener with it.
        if status != noErr, status != kAudioHardwareBadObjectError {
            log.error("mic listener removal failed: \(status)")
        }
    }
}
