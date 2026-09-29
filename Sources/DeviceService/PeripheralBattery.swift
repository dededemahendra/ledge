import Foundation
import IOKit

/// Battery level for Bluetooth accessories that publish one, read from the
/// IORegistry — `AppleDeviceManagementHIDEventService` entries carry a
/// `Product` name and `BatteryPercent` for AirPods, Beats and Magic
/// peripherals. No permission: the registry is world-readable.
public enum PeripheralBattery {
    public struct Candidate: Sendable, Equatable {
        public let product: String
        public let percent: Int
        public init(product: String, percent: Int) {
            self.product = product
            self.percent = percent
        }
    }

    /// Name-matched loosely in both directions, since CoreAudio's device
    /// name ("Dede's AirPods Pro") and the registry's product string are
    /// not always identical — but the BEST match wins, not the first
    /// (review, 2026-09-29: with "AirPods" and "AirPods Pro" both paired,
    /// first-match could hand the Pro the plain pair's charge).
    public static func percent(forDeviceNamed name: String) -> Int? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var candidates: [Candidate] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let product = IORegistryEntryCreateCFProperty(entry, "Product" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String,
                  let percent = IORegistryEntryCreateCFProperty(entry, "BatteryPercent" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Int, (0...100).contains(percent) else { continue }
            candidates.append(Candidate(product: product, percent: percent))
        }
        return best(among: candidates, wanted: name)?.percent
    }

    /// Exact name first; otherwise the LONGEST product string that matches
    /// in either direction — "AirPods Pro" over "AirPods" for a device
    /// named "Dede's AirPods Pro". Pure, pinned by `DeviceServiceTests`.
    static func best(among candidates: [Candidate], wanted: String) -> Candidate? {
        let wantedLower = wanted.lowercased()
        let matching = candidates.filter { matches(candidate: $0.product.lowercased(), wanted: wantedLower) }
        if let exact = matching.first(where: { $0.product.lowercased() == wantedLower }) { return exact }
        return matching.max { $0.product.count < $1.product.count }
    }

    static func matches(candidate: String, wanted: String) -> Bool {
        !candidate.isEmpty && (candidate == wanted || wanted.contains(candidate) || candidate.contains(wanted))
    }
}
