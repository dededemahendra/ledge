import CoreAudio
import Foundation
import os

/// Which processes hold the mic right now (2026-10-22), from CoreAudio's
/// process objects. Listens rather than polls: to the process list, and to
/// each process's "running input", re-listening when the list changes.
/// `holderPIDs` is `nil` when the list can't be read.
@MainActor
final class MicHolders {
    private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "call")
    private static let system = AudioObjectID(kAudioObjectSystemObject)

    /// Removal must be handed the exact block that was added (CoreAudio
    /// matches it by identity), so each one is kept with its address.
    private struct InstalledListener {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private(set) var holderPIDs: [pid_t]?
    private var listListener: InstalledListener?
    private var processListeners: [InstalledListener] = []

    func start() {
        guard listListener == nil else { return }
        listListener = Self.listen(Self.system, Self.address(kAudioHardwarePropertyProcessObjectList)) { [weak self] in
            self?.relisten()
        }
        relisten()
    }

    func stop() {
        if let listListener { Self.remove(listListener) }
        listListener = nil
        processListeners.forEach(Self.remove)
        processListeners.removeAll()
        holderPIDs = nil
    }

    private func relisten() {
        processListeners.forEach(Self.remove)
        processListeners.removeAll()
        guard let processes = Self.processes() else {
            holderPIDs = nil
            return
        }
        processListeners = processes.compactMap { process in
            Self.listen(process, Self.address(kAudioProcessPropertyIsRunningInput)) { [weak self] in
                self?.read()
            }
        }
        read()
    }

    private func read() {
        guard let processes = Self.processes() else {
            holderPIDs = nil
            return
        }
        holderPIDs = processes.compactMap { process in
            var running = Self.address(kAudioProcessPropertyIsRunningInput)
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(process, &running, 0, nil, &size, &value) == noErr, value != 0 else { return nil }
            var pidAddress = Self.address(kAudioProcessPropertyPID)
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            guard AudioObjectGetPropertyData(process, &pidAddress, 0, nil, &pidSize, &pid) == noErr else { return nil }
            return pid
        }
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
        if status != noErr { log.error("mic listener removal failed: \(status)") }
    }
}
