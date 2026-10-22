import CoreMediaIO
import Foundation

/// Whether a camera is on (2026-10-22). A protocol so the service can be
/// tested on a made-up camera.
@MainActor
public protocol CameraSource: AnyObject {
    var isCameraOn: Bool { get }
    /// Reads again now.
    func refresh()
}

/// The real cameras, from CoreMediaIO: any device running somewhere means
/// a camera is on. Reading the running state needs no permission (checked
/// 2026-10-22). Read only when asked — `CallService` asks each tick of a
/// live call, the only time the card shows it.
@MainActor
final class CameraWatcher: CameraSource {
    private(set) var isCameraOn = false

    func refresh() {
        isCameraOn = Self.devices().contains { device in
            var running = Self.address(CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere))
            var value: UInt32 = 0
            var used: UInt32 = 0
            return CMIOObjectGetPropertyData(device, &running, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr
                && value != 0
        }
    }

    private static func address(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(mSelector: selector,
                                  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func devices() -> [CMIOObjectID] {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var addr = address(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &ids) == noErr else { return [] }
        return ids
    }
}
