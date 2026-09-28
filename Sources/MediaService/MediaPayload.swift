import Foundation

/// Now-playing state, decoded from the adapter's JSON.
///
/// Keys mirror the `mediaremote-adapter` README exactly: `bundleIdentifier`,
/// `playing` and `title` are the only three ever guaranteed non-null when
/// media exists. Every field is optional because the adapter's own payload
/// is: fields the source app never reports are simply absent.
public struct MediaPayload: Sendable, Equatable {
    public var bundleIdentifier: String?
    public var playing: Bool?
    public var title: String?
    public var artist: String?
    public var album: String?
    public var duration: Double?
    public var elapsedTime: Double?
    public var timestamp: Date?
    public var playbackRate: Double?
    public var artworkData: Data?
    public var artworkMimeType: String?
    /// MediaRemote's `kMRMediaRemoteNowPlayingInfoShuffleMode`, passed
    /// through by the adapter when the source app reports it (Music,
    /// Spotify; browsers never do): 1 off, 2 albums, 3 songs.
    public var shuffleMode: Int?
    /// The playing app's pid, as the adapter reports it — the precise way
    /// to bring THAT app forward when several instances share a bundle id.
    public var processIdentifier: Int?
    /// `kMRMediaRemoteNowPlayingInfoRepeatMode`: 1 off, 2 one, 3 all
    /// (the adapter's own `repeat 3` comment calls 3 "playlist").
    public var repeatMode: Int?

    public init() {}

    /// `nil` when the source does not report shuffle at all — the panel
    /// disables the button then, rather than showing a state it cannot
    /// know. Any mode above "off" counts as on.
    public var isShuffling: Bool? {
        shuffleMode.map { $0 >= 2 }
    }

    public enum RepeatMode: Sendable, Equatable {
        case off, one, all
    }

    /// `nil` when unreported; an out-of-range value reads as off rather
    /// than crashing on an adapter surprise.
    public var repeatSetting: RepeatMode? {
        guard let repeatMode else { return nil }
        switch repeatMode {
        case 2:  return .one
        case 3:  return .all
        default: return .off
        }
    }

    /// The adapter guarantees these three are non-null when media exists;
    /// a payload missing any of them is not usable now-playing state.
    public var hasMedia: Bool {
        bundleIdentifier != nil && playing != nil && title != nil
    }

    public var isPlaying: Bool { playing == true }

    /// Tolerant by design: a wrong type is treated as absent, never fatal —
    /// the adapter is an external process and its output must never be able
    /// to crash this app.
    public static func decode(_ json: [String: Any]) -> MediaPayload {
        var p = MediaPayload()
        p.bundleIdentifier = json["bundleIdentifier"] as? String
        p.playing = json["playing"] as? Bool
        p.title = json["title"] as? String
        p.artist = json["artist"] as? String
        p.album = json["album"] as? String
        p.duration = number(json["duration"])
        p.elapsedTime = number(json["elapsedTime"])
        p.playbackRate = number(json["playbackRate"])
        p.artworkMimeType = json["artworkMimeType"] as? String
        p.shuffleMode = number(json["shuffleMode"]).map { Int($0) }
        p.processIdentifier = number(json["processIdentifier"]).map { Int($0) }
        p.repeatMode = number(json["repeatMode"]).map { Int($0) }

        if let encoded = json["artworkData"] as? String {
            p.artworkData = Data(base64Encoded: encoded)
        }
        if let stamp = json["timestamp"] as? String {
            p.timestamp = ISO8601DateFormatter().date(from: stamp)
        } else if let seconds = number(json["timestamp"]) {
            p.timestamp = Date(timeIntervalSince1970: seconds)
        }
        return p
    }

    /// JSON delivers numbers as `Int` or `Double` depending on the value;
    /// `NSNumber` bridging means a plain `as? Double` cast can miss integral
    /// values, so both are tried explicitly.
    private static func number(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }
}
