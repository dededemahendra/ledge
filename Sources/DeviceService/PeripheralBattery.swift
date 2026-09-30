import Foundation
import IOKit

/// A Bluetooth peripheral's charge, per component where it reports them
/// (2026-09-30): AirPods and Beats buds give left, right and case; most
/// other headsets give one figure.
public struct PeripheralLevels: Sendable, Equatable {
    public let main: Int?
    public let left: Int?
    public let right: Int?
    public let `case`: Int?

    public init(main: Int? = nil, left: Int? = nil, right: Int? = nil, case: Int? = nil) {
        self.main = main
        self.left = left
        self.right = right
        self.case = `case`
    }

    public var isEmpty: Bool { main == nil && left == nil && right == nil && `case` == nil }
    public var hasBuds: Bool { left != nil || right != nil }

    /// The IO registry's keys on `AppleDeviceManagementHIDEventService`:
    /// `BatteryPercent` (or `BatteryPercentMain`), `BatteryPercentLeft`,
    /// `BatteryPercentRight`, `BatteryPercentCase`. Values outside 0…100
    /// are the driver's "unknown" and are dropped. `nil` with nothing left.
    public static func parse(properties: [String: Any]) -> PeripheralLevels? {
        func percent(_ key: String) -> Int? {
            guard let value = (properties[key] as? NSNumber)?.intValue, (0...100).contains(value) else { return nil }
            return value
        }
        let levels = PeripheralLevels(
            main: percent("BatteryPercent") ?? percent("BatteryPercentMain"),
            left: percent("BatteryPercentLeft"),
            right: percent("BatteryPercentRight"),
            case: percent("BatteryPercentCase")
        )
        return levels.isEmpty ? nil : levels
    }
}

public enum PeripheralBattery {
    public struct Candidate: Sendable, Equatable {
        public let product: String
        public let levels: PeripheralLevels

        public init(product: String, levels: PeripheralLevels) {
            self.product = product
            self.levels = levels
        }
    }

    /// Apple and Beats peripherals, through the HID battery service —
    /// no Bluetooth permission involved.
    public static func levels(forDeviceNamed name: String) -> PeripheralLevels? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var candidates: [Candidate] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var raw: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &raw, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let properties = raw?.takeRetainedValue() as? [String: Any],
                  let product = properties["Product"] as? String,
                  let levels = PeripheralLevels.parse(properties: properties)
            else { continue }
            candidates.append(Candidate(product: product, levels: levels))
        }
        return best(among: candidates, wanted: name)?.levels
    }

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
