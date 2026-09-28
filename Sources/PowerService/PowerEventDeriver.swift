import Foundation

public enum PowerEvent: Sendable, Equatable {
    case pluggedIn(percent: Int, isCharging: Bool, timeToFullMinutes: Int?)
    case unplugged(percent: Int)
    case fullyCharged
    case lowBattery(percent: Int)

    /// `isPluggedIn` alone used to drive this ("Charging · N%" whenever AC was
    /// attached), which is simply false whenever macOS is holding off charging
    /// — optimised battery charging short of 100%, or a thermal hold. Only the
    /// `isCharging` branch may say "Charging"; the other tells the truth
    /// ("On AC") and drops the time-to-full estimate, which means nothing
    /// while nothing is actually charging.
    public var activityTitle: String {
        switch self {
        case .pluggedIn(let percent, let isCharging, let minutes):
            guard isCharging else {
                return "On AC · \(percent)%"
            }
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

    /// Glanceable form for the trailing ear, which is the only place text can
    /// appear while a single activity holds the island at notch height. The ear
    /// is ~38pt wide, so this stays to a few characters. Bare percentage either
    /// way — charging vs. held is a distinction `activityTitle` alone carries.
    public var compactText: String {
        switch self {
        case .pluggedIn(let percent, _, _): return "\(percent)%"
        case .unplugged(let percent):       return "\(percent)%"
        case .fullyCharged:                 return "100%"
        case .lowBattery(let percent):      return "\(percent)%"
        }
    }

    /// The word beside the glyph in the labelled ear (the HUD's layout:
    /// glyph + word left, value right, at `NotchMetrics.hud` size). No
    /// digits — `compactText` carries them on the other side. Every word
    /// here is measured to fit the ear's 57pt label budget at 12pt semibold
    /// (measured 2026-09-28: "Charging" 54, "On AC" 37, "Battery" 44,
    /// "Charged" 50, "Low" 24 — while "On battery" 63 and "Low battery" 70
    /// would run under the hole). The glyph's fill level and the percentage
    /// beside it say the rest; `activityTitle` keeps the long form for the
    /// detail row.
    public var earLabel: String {
        switch self {
        case .pluggedIn(_, let isCharging, _): return isCharging ? "Charging" : "On AC"
        case .unplugged:                       return "Battery"
        case .fullyCharged:                    return "Charged"
        case .lowBattery:                      return "Low"
        }
    }

    /// Glyph for the leading ear. A bolt while charging, a plug while held
    /// on AC, a battery whose fill tracks the level otherwise.
    public var symbolName: String {
        switch self {
        case .pluggedIn(_, true, _):   return "bolt.fill"
        case .pluggedIn(_, false, _):  return "powerplug.fill"
        case .fullyCharged:            return "battery.100percent.bolt"
        case .unplugged(let percent), .lowBattery(let percent):
            return Self.batterySymbol(percent: percent)
        }
    }

    /// SF Symbols ships the battery at five fills; pick the nearest.
    public static func batterySymbol(percent: Int) -> String {
        switch percent {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default:    return "battery.100percent"
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
                    isCharging: snapshot.isCharging,
                    timeToFullMinutes: snapshot.timeToFullMinutes
                ))
            } else {
                events.append(.unplugged(percent: snapshot.percent))
            }
        } else if snapshot.isPluggedIn, snapshot.isCharging != previous.isCharging {
            // Optional fix-wave addition: without this, nothing fires when the
            // state flips between charging and held (optimised-charging hold,
            // thermal hold) WITHOUT an intervening unplug/replug, so the island
            // would keep showing whatever label it last had. Re-fires the same
            // `.pluggedIn` event with the fresh `isCharging` value/estimate;
            // `ActivityQueue` coalesces it into the existing `.power` activity
            // by kind and restarts its TTL, same as any other update.
            events.append(.pluggedIn(
                percent: snapshot.percent,
                isCharging: snapshot.isCharging,
                timeToFullMinutes: snapshot.timeToFullMinutes
            ))
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
