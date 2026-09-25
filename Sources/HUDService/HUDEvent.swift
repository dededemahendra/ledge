import Foundation

public enum HUDEvent: Sendable, Equatable {
    case volume(level: Double, muted: Bool)
    case brightness(level: Double)

    /// Proportion of the bar to fill. Muted reads as empty regardless of level.
    public var barFill: Double {
        switch self {
        case .volume(let level, let muted): return muted ? 0 : level
        case .brightness(let level):        return level
        }
    }

    public var symbolName: String {
        switch self {
        case .volume(_, true):
            return "speaker.slash.fill"
        case .volume(let level, false):
            if level <= 0.001 { return "speaker.fill" }
            if level < 0.34 { return "speaker.wave.1.fill" }
            if level < 0.67 { return "speaker.wave.2.fill" }
            return "speaker.wave.3.fill"
        case .brightness:
            return "sun.max.fill"
        }
    }

    public var activityTitle: String {
        switch self {
        case .volume(_, true):
            return "Muted"
        case .volume(let level, false):
            return "Volume \(Int((level * 100).rounded()))%"
        case .brightness(let level):
            return "Brightness \(Int((level * 100).rounded()))%"
        }
    }

    /// Glanceable form for the trailing ear, which is the only place text can appear
    /// while a single activity holds the island at notch height. The ear is ~38pt
    /// wide, so this stays to a few characters.
    public var compactText: String {
        switch self {
        case .volume(_, true):            return "Muted"
        case .volume(let level, false):   return "\(Int((level * 100).rounded()))%"
        case .brightness(let level):      return "\(Int((level * 100).rounded()))%"
        }
    }
}
