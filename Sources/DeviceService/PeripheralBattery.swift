import Foundation
import IOKit

/// Battery level for Bluetooth accessories that publish one, read from the
/// IORegistry — `AppleDeviceManagementHIDEventService` entries carry a
/// `Product` name and `BatteryPercent` for AirPods, Beats and Magic
/// peripherals. No permission: the registry is world-readable.
public enum PeripheralBattery {
    /// Name-matched loosely in both directions, since CoreAudio's device
    /// name ("Dede's AirPods Pro") and the registry's product string are
    /// not always identical.
    public static func percent(forDeviceNamed name: String) -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        let wanted = name.lowercased()
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let product = IORegistryEntryCreateCFProperty(entry, "Product" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String else { continue }
            guard matches(candidate: product.lowercased(), wanted: wanted) else { continue }
            if let percent = IORegistryEntryCreateCFProperty(entry, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int, (0...100).contains(percent) {
                return percent
            }
        }
        return nil
    }

    static func matches(candidate: String, wanted: String) -> Bool {
        !candidate.isEmpty && (candidate == wanted || wanted.contains(candidate) || candidate.contains(wanted))
    }
}
