import Foundation

/// One reading of the system's power state.
public struct PowerSnapshot: Sendable, Equatable {
    public let percent: Int
    public let isPluggedIn: Bool
    /// Whether the battery is actively charging right now, straight off
    /// IOKit's `"Is Charging"` key. Distinct from `isPluggedIn`: macOS can
    /// report AC attached but NOT charging — optimised battery charging
    /// holding short of 100%, or a thermal hold — and `PowerEvent.activityTitle`
    /// depends on telling the two apart rather than claiming "Charging"
    /// whenever the machine is merely plugged in.
    public let isCharging: Bool
    public let isCharged: Bool
    public let timeToFullMinutes: Int?

    public init(
        percent: Int,
        isPluggedIn: Bool,
        isCharging: Bool,
        isCharged: Bool,
        timeToFullMinutes: Int?
    ) {
        self.percent = percent
        self.isPluggedIn = isPluggedIn
        self.isCharging = isCharging
        self.isCharged = isCharged
        self.timeToFullMinutes = timeToFullMinutes
    }

    /// Parses an `IOPSCopyPowerSourceDescription` dictionary.
    /// Returns `nil` rather than guessing when the shape is not what we expect.
    public static func parse(_ description: [String: Any]) -> PowerSnapshot? {
        guard
            let current = description["Current Capacity"] as? Int,
            let maximum = description["Max Capacity"] as? Int,
            maximum > 0
        else { return nil }

        let ratio = Double(current) / Double(maximum)
        let percent = min(100, max(0, Int((ratio * 100).rounded())))

        let state = description["Power Source State"] as? String
        let isPluggedIn = state == "AC Power"
        let isCharging = description["Is Charging"] as? Bool ?? false
        let isCharged = description["Is Charged"] as? Bool ?? false

        let rawTimeToFull = description["Time to Full Charge"] as? Int
        let timeToFull = (rawTimeToFull ?? -1) > 0 ? rawTimeToFull : nil

        return PowerSnapshot(
            percent: percent,
            isPluggedIn: isPluggedIn,
            isCharging: isCharging,
            isCharged: isCharged,
            timeToFullMinutes: timeToFull
        )
    }
}
