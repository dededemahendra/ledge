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
}

public enum GitHubNotice {
    /// The running item's ring and clock.
    public static let runningTintName = "yellow"

    public static func blip(for event: GitHubEvent) -> GitHubBlip {
        switch event {
        case .checksPassed(let pr):
            return GitHubBlip(title: "Checks passed", symbolName: "checkmark.circle.fill", word: "Passed",
                              tintName: "green", caption: prCaption(pr), url: pr.url)
        case .checksFailed(let pr):
            return GitHubBlip(title: "Checks failed", symbolName: "xmark.circle.fill", word: "Failed", tintName: "red",
                              caption: "#\(pr.number) \(short(pr.title)) · \(pr.checks?.failedName ?? pr.repo)",
                              url: pr.checks?.failedURL ?? pr.url)
        case .reviewed(let pr, let review):
            let url = review.url ?? pr.url
            switch review.state {
            case .approved:
                return GitHubBlip(title: "Approved", symbolName: "checkmark.seal.fill", word: "Approved", tintName: "green",
                                  caption: byCaption(review.author, pr), url: url)
            case .changesRequested:
                return GitHubBlip(title: "Changes requested", symbolName: "exclamationmark.bubble.fill", word: "Changes",
                                  tintName: "orange", caption: byCaption(review.author, pr), url: url)
            case .commented, .other:
                return GitHubBlip(title: "Comment", symbolName: "bubble.left.fill", word: "Comment", tintName: nil,
                                  caption: byCaption(review.author, pr), url: url)
            }
        case .commented(let pr, let comment):
            return GitHubBlip(title: "Comment", symbolName: "bubble.left.fill", word: "Comment", tintName: nil,
                              caption: byCaption(comment.author, pr), url: comment.url ?? pr.url)
        case .merged(let pr):
            return GitHubBlip(title: "Merged", symbolName: "arrow.triangle.merge", word: "Merged", tintName: "purple",
                              caption: prCaption(pr), url: pr.url)
        case .closed(let pr):
            return GitHubBlip(title: "Closed", symbolName: "xmark.circle", word: "Closed", tintName: "gray",
                              caption: prCaption(pr), url: pr.url)
        case .reviewRequested(let pr):
            return GitHubBlip(title: "Review requested", symbolName: "eye.fill", word: "Review", tintName: "blue",
                              caption: "\(pr.author ?? "Someone") asks for your review · #\(pr.number) \(pr.repo)", url: pr.url)
        case .runPassed(let run):
            return GitHubBlip(title: "Run passed", symbolName: "checkmark.circle.fill", word: "Passed", tintName: "green",
                              caption: runCaption(run), url: run.url)
        case .runFailed(let run):
            return GitHubBlip(title: "Run failed", symbolName: "xmark.circle.fill", word: "Failed", tintName: "red",
                              caption: runCaption(run), url: run.url)
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
                          caption: "\(blip.caption) · +\(events.count - 1) more", url: blip.url)
    }

    static func prCaption(_ pr: GitHubPR) -> String { "#\(pr.number) \(short(pr.title)) · \(pr.repo)" }
    static func runCaption(_ run: GitHubRun) -> String { "\(run.workflow) · \(run.repo)" }
    static func byCaption(_ login: String, _ pr: GitHubPR) -> String { "\(login) · #\(pr.number) \(pr.repo)" }

    /// A long title would stretch the caption across the menu bar.
    static func short(_ title: String) -> String {
        title.count > 40 ? String(title.prefix(39)) + "…" : title
    }
}
