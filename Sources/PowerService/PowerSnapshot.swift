import Foundation

/// One reading of the system's power state.
///
/// Does NOT carry IOKit's "Is Charging" flag: it was parsed, stored, and
/// compared, but read by nothing — `PowerEventDeriver` only ever consumes
/// `isPluggedIn`/`isCharged`. Deleted rather than kept "for later": a
/// plugged-but-not-charging distinction (100% on AC, a thermal hold) is a
/// real thing a future task could want, but it is trivial to re-add a
/// parsed field when something actually consumes it, whereas carrying
/// dead-but-tested surface area indefinitely has a real, if small,
/// ongoing cost — every future change to this type has to keep an unused
/// field consistent for no functional benefit.
public struct PowerSnapshot: Sendable, Equatable {
    public let percent: Int
    public let isPluggedIn: Bool
    public let isCharged: Bool
    public let timeToFullMinutes: Int?

    public init(
        percent: Int,
        isPluggedIn: Bool,
        isCharged: Bool,
        timeToFullMinutes: Int?
    ) {
        self.percent = percent
        self.isPluggedIn = isPluggedIn
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
        let isCharged = description["Is Charged"] as? Bool ?? false

        let rawTimeToFull = description["Time to Full Charge"] as? Int
        let timeToFull = (rawTimeToFull ?? -1) > 0 ? rawTimeToFull : nil

        return PowerSnapshot(
            percent: percent,
            isPluggedIn: isPluggedIn,
            isCharged: isCharged,
            timeToFullMinutes: timeToFull
        )
    }
}
