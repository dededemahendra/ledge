import Foundation

/// What a check found (2026-10-22).
public enum UpdateFinding: Sendable, Equatable {
    /// The running version is the latest, or newer.
    case upToDate
    /// A newer release; `announce` only the first time this version is found.
    case available(ReleaseInfo, announce: Bool)
}

/// One island blip per version (2026-10-22, user's call).
public enum UpdateDecision {
    public static func evaluate(current: AppVersion, latest: ReleaseInfo, lastAnnounced: AppVersion?) -> UpdateFinding {
        guard latest.version > current else { return .upToDate }
        let announce = lastAnnounced.map { $0 != latest.version } ?? true
        return .available(latest, announce: announce)
    }
}
