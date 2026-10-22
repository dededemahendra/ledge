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

    /// Colour meaning for the glyph, matching the system's own battery
    /// indicator: green on the charger or charged, red when low, none
    /// otherwise (2026-09-29). The charger going in is green even while
    /// macOS still says "not charging" (2026-10-22): it hands over to the
    /// steady charging state, which is green either way.
    public enum Tint: Sendable, Equatable {
        case positive, warning
    }

    public var tint: Tint? {
        switch self {
        case .pluggedIn, .fullyCharged: return .positive
        case .lowBattery:               return .warning
        case .unplugged:                return nil
        }
    }

    /// Glyph for the leading ear. The battery with a bolt when the charger
    /// goes in — the menu bar's own charging glyph (user's call,
    /// 2026-09-29: the bare bolt read as "power", not "battery") — the
    /// full battery when charged, a battery whose fill tracks the level
    /// otherwise. No plug while held on AC (2026-10-22, user's call):
    /// macOS reports most plug-ins as held for a few seconds before
    /// charging starts, and the plug then the battery read as two blips.
    public var symbolName: String {
        switch self {
        case .pluggedIn:               return "battery.100percent.bolt"
        case .fullyCharged:            return "battery.100percent"
        case .unplugged(let percent), .lowBattery(let percent):
            return Self.batterySymbol(percent: percent)
        }
    }

    /// How full the battery glyph draws (2026-10-22): the charge, so the
    /// blip fills its cell to the level as the steady charging state does
    /// rather than tinting the symbol end to end.
    public var barFill: Double {
        switch self {
        case .pluggedIn(let percent, _, _), .unplugged(let percent), .lowBattery(let percent):
            return Double(percent) / 100
        case .fullyCharged:
            return 1
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
        }
        // Charging starting or holding with the charger still in is no
        // moment of its own (2026-10-22, user's call): macOS reports most
        // plug-ins as held and then charging a few seconds later, and
        // re-firing on that flip made one plug-in two blips. The steady
        // charging state reads the snapshot itself.

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
