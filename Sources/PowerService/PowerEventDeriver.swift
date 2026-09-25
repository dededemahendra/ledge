import Foundation

public enum PowerEvent: Sendable, Equatable {
    case pluggedIn(percent: Int, timeToFullMinutes: Int?)
    case unplugged(percent: Int)
    case fullyCharged
    case lowBattery(percent: Int)

    public var activityTitle: String {
        switch self {
        case .pluggedIn(let percent, let minutes):
            if let minutes {
                return "Charging · \(percent)% · \(minutes) min to full"
            }
            return "Charging · \(percent)%"
        case .unplugged(let percent):
            return "On battery · \(percent)%"
        case .fullyCharged:
            return "Fully charged"
        case .lowBattery(let percent):
            return "Low battery · \(percent)%"
        }
    }
}

/// Turns a stream of snapshots into the handful of moments worth showing.
///
/// Pure and deterministic: the same snapshot sequence always yields the same
/// events, which is what makes the IOKit shell around it nearly trivial.
public struct PowerEventDeriver: Sendable {
    public static let lowThresholds = [20, 10, 5]

    private var previous: PowerSnapshot?
    private var firedThresholds: Set<Int> = []
    private var firedFullyCharged = false

    public init() {}

    public mutating func events(for snapshot: PowerSnapshot) -> [PowerEvent] {
        defer { previous = snapshot }

        // First reading establishes a baseline only — launching while plugged in
        // must not announce a plug-in that happened before we existed.
        guard let previous else { return [] }

        var events: [PowerEvent] = []

        if snapshot.isPluggedIn != previous.isPluggedIn {
            if snapshot.isPluggedIn {
                events.append(.pluggedIn(
                    percent: snapshot.percent,
                    timeToFullMinutes: snapshot.timeToFullMinutes
                ))
            } else {
                events.append(.unplugged(percent: snapshot.percent))
            }
        }

        if snapshot.isCharged, !firedFullyCharged {
            events.append(.fullyCharged)
            firedFullyCharged = true
        }
        if !snapshot.isCharged {
            firedFullyCharged = false
        }

        if snapshot.isPluggedIn {
            // Charging rearms the warnings for the next discharge cycle.
            firedThresholds.removeAll()
        } else {
            // Report only the lowest threshold newly crossed, so waking from
            // sleep at 3% announces 3%, not 20% then 10% then 5%.
            let crossed = Self.lowThresholds
                .filter { snapshot.percent < $0 && !firedThresholds.contains($0) }
            if !crossed.isEmpty {
                firedThresholds.formUnion(crossed)
                events.append(.lowBattery(percent: snapshot.percent))
            }
        }

        return events
    }
}
