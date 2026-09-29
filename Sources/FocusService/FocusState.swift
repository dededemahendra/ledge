import Foundation

/// A Focus as the menu bar shows it: Control Center puts a
/// `com.apple.menuextra.focusmodes` extra up while one is on (its default
/// "show when active"), with the mode's name in its text. The Focus
/// database itself sits behind Full Disk Access, which this app will not
/// ask for. Pure — derived from `[MenuBarExtra]`, so it is testable.
public struct FocusState: Sendable, Equatable {
    public let name: String

    public init(name: String) {
        self.name = name
    }

    /// The Focus extra, if any. Its identifier is matched loosely
    /// ("focus" anywhere after the prefix) since the exact spelling was
    /// not observed before shipping; the name is the extra's value, else
    /// its description, with a leading "Focus" and its separators
    /// stripped, and "Do Not Disturb" when nothing is left.
    public static func current(in extras: [MenuBarExtra]) -> FocusState? {
        guard let extra = extras.first(where: {
            let id = $0.identifier.lowercased()
            return id.contains("focus") || id.contains("donotdisturb")
        }) else { return nil }
        let raw = extra.value ?? extra.description ?? extra.title ?? ""
        return FocusState(name: Self.name(from: raw))
    }

    static func name(from raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Focus", "focus"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,:–-—").union(.whitespaces))
        // "Do Not Disturb, on" style suffixes.
        for suffix in [", on", ", On", " on", " On"] where text.hasSuffix(suffix) {
            text = String(text.dropLast(suffix.count))
        }
        return text.isEmpty ? "Do Not Disturb" : text
    }

    /// The mode's glyph, from the names Apple ships. Anything else, and
    /// the user's own Focuses, get the moon — the system's Focus symbol.
    public var symbolName: String {
        switch name.lowercased() {
        case "do not disturb": return "moon.fill"
        case "sleep":          return "bed.double.fill"
        case "work":           return "briefcase.fill"
        case "personal":       return "person.fill"
        case "driving":        return "car.fill"
        case "fitness":        return "figure.run"
        case "gaming":         return "gamecontroller.fill"
        case "mindfulness":    return "leaf.fill"
        case "reading":        return "book.fill"
        default:               return "moon.fill"
        }
    }
}

public enum FocusEvent: Sendable, Equatable {
    case on(FocusState)
    case off(FocusState)

    public var state: FocusState {
        switch self {
        case .on(let s), .off(let s): return s
        }
    }

    public var isOn: Bool {
        if case .on = self { return true }
        return false
    }

    public var symbolName: String { isOn ? state.symbolName : "moon" }
    public var compactText: String { isOn ? "On" : "Off" }
}

/// Turns successive samples into events: only transitions count, and the
/// first sample sets the baseline silently — a Focus already on at launch
/// is not news.
public struct FocusEventDeriver: Sendable, Equatable {
    private var last: FocusState??

    public init() {}

    public mutating func sample(_ current: FocusState?) -> FocusEvent? {
        defer { last = .some(current) }
        guard let previous = last else { return nil }
        switch (previous, current) {
        case (nil, let now?):               return .on(now)
        case (let before?, nil):            return .off(before)
        case (let before?, let now?) where before != now: return .on(now)   // switched modes
        default:                            return nil
        }
    }
}
