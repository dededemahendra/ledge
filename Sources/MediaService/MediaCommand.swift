import Foundation

/// Playback commands. IDs are from the adapter README's `send COMMAND` table.
public enum MediaCommand: Sendable, Equatable {
    case play
    case pause
    case togglePlayPause
    case nextTrack
    case previousTrack
    case toggleShuffle
    case toggleRepeat
    case seek(seconds: Double)

    public var adapterArguments: [String] {
        switch self {
        case .play:             return ["send", "0"]
        case .pause:            return ["send", "1"]
        case .togglePlayPause:  return ["send", "2"]
        case .nextTrack:        return ["send", "4"]
        case .previousTrack:    return ["send", "5"]
        case .toggleShuffle:    return ["send", "6"]
        case .toggleRepeat:     return ["send", "7"]
        case .seek(let seconds):
            // The adapter requires a positive integer number of microseconds.
            let micros = Int((max(0, seconds) * 1_000_000).rounded())
            return ["seek", String(micros)]
        }
    }
}
