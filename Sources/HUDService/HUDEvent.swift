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

    /// No digits: this renders next to a bar that already shows the level,
    /// and neither macOS's OSD nor Alcove numbers theirs. The word carries
    /// the kind, the bar carries the value.
    ///
    /// "Sound"/"Display", not "Volume"/"Brightness": these are the words the
    /// reference HUD uses, and they are also the ones that FIT — the label
    /// shares a ~90pt ear with the glyph (`NotchMetrics.hudEarWidth`), and
    /// "Brightness" at the label's 12pt semibold overruns it. Mute keeps the
    /// same word: the slashed speaker and the empty bar already say muted,
    /// and a label that swaps on every mute toggle would crossfade for no
    /// new information.
    public var activityTitle: String {
        switch self {
        case .volume:     return "Sound"
        case .brightness: return "Display"
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
