import Foundation

/// How one event looks on the island (2026-10-22).
public struct GitHubBlip: Sendable, Equatable {
    public let title: String
    public let symbolName: String
    /// The trailing ear's word.
    public let word: String
    /// An Apple system colour by name (`SystemTint`), `nil` for white.
    public let tintName: String?
    public let caption: String
    public let url: URL
    /// Who did it, when a person did (2026-10-22).
    public let avatarURL: URL?
}

public enum GitHubNotice {
    /// The running item's ring and clock.
    public static let runningTintName = "yellow"

    /// The glyph sits on a disc in the event's colour, or as a badge on
    /// the person's avatar (2026-10-22).
    public static func blip(for event: GitHubEvent) -> GitHubBlip {
        switch event {
        case .checksPassed(let pr):
            return GitHubBlip(title: "Checks passed", symbolName: "checkmark", word: "Passed", tintName: "green",
                              caption: caption(pr.title, pr.repo), url: pr.url, avatarURL: nil)
        case .checksFailed(let pr):
            return GitHubBlip(title: "Checks failed", symbolName: "xmark", word: "Failed", tintName: "red",
                              caption: caption(pr.title, pr.checks?.failedName, pr.repo),
                              url: pr.checks?.failedURL ?? pr.url, avatarURL: nil)
        case .reviewed(let pr, let review):
            let url = review.url ?? pr.url
            let by = caption(pr.title, review.author, pr.repo)
            switch review.state {
            case .approved:
                return GitHubBlip(title: "Approved", symbolName: "checkmark", word: "Approved", tintName: "green",
                                  caption: by, url: url, avatarURL: review.avatarURL)
            case .changesRequested:
                return GitHubBlip(title: "Changes requested", symbolName: "exclamationmark", word: "Changes",
                                  tintName: "orange", caption: by, url: url, avatarURL: review.avatarURL)
            case .commented, .other:
                return GitHubBlip(title: "Comment", symbolName: "bubble.left.fill", word: "Comment", tintName: nil,
                                  caption: by, url: url, avatarURL: review.avatarURL)
            }
        case .commented(let pr, let comment):
            return GitHubBlip(title: "Comment", symbolName: "bubble.left.fill", word: "Comment", tintName: nil,
                              caption: caption(pr.title, comment.author, pr.repo), url: comment.url ?? pr.url,
                              avatarURL: comment.avatarURL)
        case .merged(let departure):
            return GitHubBlip(title: "Merged", symbolName: "arrow.triangle.merge", word: "Merged", tintName: "purple",
                              caption: caption(departure.pr.title, departure.by, departure.pr.repo), url: departure.pr.url,
                              avatarURL: departure.byAvatarURL)
        case .closed(let departure):
            return GitHubBlip(title: "Closed", symbolName: "xmark", word: "Closed", tintName: "gray",
                              caption: caption(departure.pr.title, departure.by, departure.pr.repo), url: departure.pr.url,
                              avatarURL: departure.byAvatarURL)
        case .reviewRequested(let pr):
            return GitHubBlip(title: "Review requested", symbolName: "eye.fill", word: "Review", tintName: "blue",
                              caption: caption(pr.title, pr.author, pr.repo), url: pr.url, avatarURL: pr.authorAvatarURL)
        case .runPassed(let run):
            return GitHubBlip(title: "Run passed", symbolName: "checkmark", word: "Passed", tintName: "green",
                              caption: caption(run.workflow, run.repo), url: run.url, avatarURL: nil)
        case .runFailed(let run):
            return GitHubBlip(title: "Run failed", symbolName: "xmark", word: "Failed", tintName: "red",
                              caption: caption(run.workflow, run.repo), url: run.url, avatarURL: nil)
        }
    }

    /// Lower is more important: what needs the user, then good news, then
    /// chatter.
    public static func rank(_ event: GitHubEvent) -> Int {
        switch event {
        case .checksFailed, .runFailed: return 0
        case .reviewed(_, let review) where review.state == .changesRequested: return 1
        case .reviewRequested: return 2
        case .reviewed(_, let review) where review.state == .approved: return 3
        case .merged: return 4
        case .checksPassed, .runPassed: return 5
        case .reviewed, .commented: return 6
        case .closed: return 7
        }
    }

    /// One blip for everything a round found: the most important, and how
    /// many more there were.
    public static func burst(_ events: [GitHubEvent]) -> GitHubBlip? {
        guard let top = events.enumerated()
            .min(by: { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) })?.element else { return nil }
        let blip = blip(for: top)
        guard events.count > 1 else { return blip }
        return GitHubBlip(title: blip.title, symbolName: blip.symbolName, word: blip.word, tintName: blip.tintName,
                          caption: "\(blip.caption) · +\(events.count - 1) more", url: blip.url,
                          avatarURL: blip.avatarURL)
    }

    static func prCaption(_ pr: GitHubPR) -> String { "#\(pr.number) \(short(pr.title)) · \(pr.repo)" }
    static func runCaption(_ run: GitHubRun) -> String { "\(run.workflow) · \(run.repo)" }

    /// "Fix the date picker · sam · web" (2026-10-22): the title first, which
    /// the island sets in bold up to the first separator, then who or what,
    /// then where; a missing part is left out.
    static func caption(_ title: String, _ parts: String?...) -> String {
        ([short(title)] + parts.compactMap { $0 }).joined(separator: " · ")
    }

    /// A long title would stretch the caption across the menu bar.
    static func short(_ title: String) -> String {
        title.count > 40 ? String(title.prefix(39)) + "…" : title
    }
}
