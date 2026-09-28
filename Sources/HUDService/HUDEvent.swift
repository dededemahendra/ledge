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

    /// One CONSTANT symbol per kind, not a band ladder (wave.1/2/3): the ear
    /// renders it with SF Symbols variable-value (`variableValue: barFill`),
    /// so the waves/rays light up with the level the way macOS's own OSD
    /// draws it — and the glyph itself never swaps mid-slide, which kept
    /// firing a crossfade at every band edge. Mute stays its own symbol:
    /// that IS a state change, and the crossfade is right there.
    public var symbolName: String {
        switch self {
        case .volume(_, true):  return "speaker.slash.fill"
        case .volume(_, false): return "speaker.wave.3.fill"
        case .brightness:       return "sun.max.fill"
        }
    }

    /// The detail-row title (the expanded panel's activity list). Not shown
    /// in the ears any more (2026-09-28): the compact island is glyph +
    /// percentage. "Sound"/"Display" are the reference app's words.
    public var activityTitle: String {
        switch self {
        case .volume:     return "Sound"
        case .brightness: return "Display"
        }
    }

    /// The trailing ear's text: glyph left, this right, nothing else (the
    /// user's call, 2026-09-28 — a labelled "Sound …… bar" row was tried
    /// and dropped). The ear is ~38pt wide, so this stays to a few characters.
    public var compactText: String {
        switch self {
        // "0%", not "Muted" (2026-09-28): the ear is glyph + percentage now,
        // the slashed speaker already says muted, and the system's own
        // overlay draws mute as an empty bar — i.e. zero. "Muted" at the
        // ear's 11pt also measures ~33pt in a 38pt ear.
        case .volume(_, true):            return "0%"
        case .volume(let level, false):   return "\(Int((level * 100).rounded()))%"
        case .brightness(let level):      return "\(Int((level * 100).rounded()))%"
        }
    }
}
