import Foundation

/// A calendar meeting's time left on the call card (2026-10-22): "12m
/// left", "1h 5m left", "Ending now" in its last minute, then "+3m" — in
/// red — once it has run over. Whole minutes, rounded down; over, from
/// the first second.
public enum CallMeetingText {
    public static func timeLeft(end: Date, now: Date) -> (text: String, isOver: Bool) {
        let remaining = end.timeIntervalSince(now)
        if remaining > 0 {
            let minutes = Int(remaining / 60)
            if minutes < 1 { return ("Ending now", false) }
            return ("\(duration(minutes)) left", false)
        }
        return ("+\(duration(max(1, Int(-remaining / 60))))", true)
    }

    private static func duration(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60)h" : "\(minutes / 60)h \(rest)m"
    }
}
