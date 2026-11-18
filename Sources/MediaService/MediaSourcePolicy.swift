import Foundation

/// Which now-playing sources the island shows and controls.
///
/// An allow-list of music players (user's call, 2026-09-29): MediaRemote
/// reports whatever played most recently — a browser tab, a video call, a
/// screen recording preview — and the island was showing those as "now
/// playing", title and all. Only real music apps belong there. Anything
/// else is treated exactly as if nothing were playing.
///
/// Browsers joined the list on 2026-11-18 (user's call), for video, but
/// only behind `BrowserVideoGate`: playing, something with a length, and
/// no call on the island.
public enum MediaSourcePolicy {
    /// Music apps' bundle identifiers, compared case-insensitively.
    public static let musicBundleIdentifiers: Set<String> = [
        "com.apple.music",                  // Apple Music
        "com.apple.itunes",                 // Music before Catalina
        "com.spotify.client",               // Spotify
        "com.tidal.desktop",                // TIDAL
        "com.deezer.deezer-desktop",        // Deezer
        "com.github.th-ch.youtube-music",   // YouTube Music (desktop app)
    ]

    /// Browsers whose video may take the island, lowercased.
    public static let browserBundleIdentifiers: Set<String> = [
        "com.apple.safari",
        "com.google.chrome",
        "company.thebrowser.browser",       // Arc
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "com.brave.browser",
    ]

    public static let allowedBundleIdentifiers = musicBundleIdentifiers.union(browserBundleIdentifiers)

    public static func isBrowser(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return browserBundleIdentifiers.contains(bundleIdentifier.lowercased())
    }

    public static func isAllowed(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return allowedBundleIdentifiers.contains(bundleIdentifier.lowercased())
    }
}

extension MediaSourcePolicy {
    /// The allow-list narrowed to what the user switched on in Settings
    /// (2026-09-30). "Music before Catalina" rides along with Music.
    public static func isAllowed(bundleIdentifier: String?, enabled: Set<String>) -> Bool {
        guard isAllowed(bundleIdentifier: bundleIdentifier), let id = bundleIdentifier?.lowercased() else { return false }
        let key = id == "com.apple.itunes" ? "com.apple.music" : id
        return enabled.contains(key)
    }
}
