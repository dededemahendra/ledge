import Foundation
import NotchKit
import OSLog

/// The card's favourite star, for Apple Music (2026-09-29). The adapter has
/// no "love this track" command, so this goes through Music's scripting
/// interface (`favorited of current track`). Spotify has no local way to
/// like a track, so for every other source the star is `.unsupported`.
///
/// **Permission, in context only.** Sending Apple Events to Music makes
/// macOS ask once to let Ledge control Music. That prompt must come from a
/// tap on the star, never from a track change in the background — so
/// until the star has been tapped once (remembered in `UserDefaults`),
/// this never queries Music at all and the star shows `.unknown`, hollow.
/// After that first tap it keeps the state in step on every track change.
@MainActor
final class MusicFavorites {
    nonisolated private static let log = Logger(subsystem: "com.dedemahendra.ledge", category: "favorites")
    static let supportedBundleIdentifier = "com.apple.music"
    private static let syncedKey = "favorites.synced"

    private(set) var state: MediaPresentation.Favorite = .unsupported
    /// Fired on the main actor when `state` changes.
    var onChange: (() -> Void)?

    private var supported = false
    private var synced = UserDefaults.standard.bool(forKey: MusicFavorites.syncedKey)
    private var generation = 0

    /// A new track (or source). Re-reads the state only once the user has
    /// opted in by tapping the star.
    func trackChanged(bundleIdentifier: String?) {
        supported = bundleIdentifier?.lowercased() == Self.supportedBundleIdentifier
        guard supported else { set(.unsupported); return }
        set(.unknown)
        if synced { refresh() }
    }

    func toggle() {
        guard supported else { return }
        synced = true
        UserDefaults.standard.set(true, forKey: Self.syncedKey)
        run(Self.toggleScript)
    }

    private func refresh() {
        run(Self.readScript)
    }

    private func run(_ source: String) {
        generation += 1
        let generation = self.generation
        Task { @MainActor [weak self] in
            let result = await Self.execute(source)
            guard let self, generation == self.generation else { return }
            switch result {
            case "true":  self.set(.on)
            case "false": self.set(.off)
            default:      self.set(self.supported ? .unknown : .unsupported)
            }
        }
    }

    private func set(_ new: MediaPresentation.Favorite) {
        guard new != state else { return }
        state = new
        onChange?()
    }

    /// Off the main actor: an Apple Event can wait on Music for a while,
    /// and the first one blocks on the permission prompt.
    private nonisolated static func execute(_ source: String) async -> String? {
        await Task.detached(priority: .userInitiated) {
            var error: NSDictionary?
            guard let script = NSAppleScript(source: source) else { return nil }
            let descriptor = script.executeAndReturnError(&error)
            if let error {
                log.info("Music script failed: \(String(describing: error[NSAppleScript.errorMessage]), privacy: .public)")
                return nil
            }
            return descriptor.stringValue
        }.value
    }

    /// `favorited` is the macOS 14+ name of what was `loved`.
    private static let readScript = """
    tell application "Music"
        if player state is stopped then return "unknown"
        return (favorited of current track) as string
    end tell
    """

    private static let toggleScript = """
    tell application "Music"
        if player state is stopped then return "unknown"
        set t to current track
        set favorited of t to not (favorited of t)
        return (favorited of t) as string
    end tell
    """
}
