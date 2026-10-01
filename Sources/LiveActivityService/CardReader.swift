import CoreGraphics
import Foundation

/// What an iPhone Live Activity's card says, read as text (2026-10-01).
/// The card's own Accessibility tree carries every figure — team names,
/// scores, the period, the clock — so the island does not have to read
/// pixels for them; only the crests are pictures.
public struct LiveActivityContent: Sendable, Equatable {
    public struct Side: Sendable, Equatable {
        public let name: String
        public let value: String
        /// Where the crest sits in the card, in card points — cut from
        /// the one picture taken when the card opened.
        public let crestRect: CGRect?
        public var crest: Data?

        public init(name: String, value: String, crestRect: CGRect? = nil, crest: Data? = nil) {
            self.name = name
            self.value = value
            self.crestRect = crestRect
            self.crest = crest
        }
    }

    /// A match: two sides with a figure each. `nil` for anything else.
    public var home: Side?
    public var away: Side?
    /// The period or state — "HT", "Round 1, Starting Soon".
    public let status: String?
    /// The running clock, as the card writes it.
    public let clock: String?
    /// The competition or app line.
    public let title: String?
    /// Everything the card says, in reading order.
    public let lines: [String]

    public var isMatch: Bool { home != nil && away != nil }

    public init(home: Side? = nil, away: Side? = nil, status: String? = nil, clock: String? = nil,
                title: String? = nil, lines: [String] = []) {
        self.home = home
        self.away = away
        self.status = status
        self.clock = clock
        self.title = title
        self.lines = lines
    }
}

/// One element of the card's Accessibility tree.
public struct CardElement: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case text, image }
    public let kind: Kind
    public let text: String
    /// Relative to the card's own top-left, in card points.
    public let frame: CGRect

    public init(kind: Kind, text: String, frame: CGRect) {
        self.kind = kind
        self.text = text
        self.frame = frame
    }
}

/// Turns the card's elements into something the island can show.
public enum CardReader {
    /// A clock the card is running: "5:56", "12:03", "1:02:30".
    static func isClock(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return false }
        guard parts.allSatisfy({ !$0.isEmpty && $0.count <= 2 && $0.allSatisfy(\.isNumber) }) else { return false }
        return parts.dropFirst().allSatisfy { $0.count == 2 }
    }
    /// A side's figure is short: a score, not a sentence.
    static let figureLimit = 3

    public static func read(_ elements: [CardElement], cardSize: CGSize) -> LiveActivityContent {
        guard cardSize.width > 0, cardSize.height > 0 else { return LiveActivityContent() }
        let texts = elements.filter { $0.kind == .text }
        let images = elements.filter { $0.kind == .image }
        let lines = texts.sorted { ($0.frame.midY, $0.frame.minX) < ($1.frame.midY, $1.frame.minX) }.map(\.text)

        // The crests: the outermost pictures, one each side of the middle.
        let byX = images.sorted { $0.frame.minX < $1.frame.minX }
        guard let first = byX.first, let last = byX.last, byX.count >= 2,
              first.frame.midX < cardSize.width * 0.4, last.frame.midX > cardSize.width * 0.6
        else {
            return LiveActivityContent(status: statusLine(texts, cardSize: cardSize), clock: clockLine(texts),
                                       title: titleLine(texts, cardSize: cardSize), lines: lines)
        }
        // The figures: the short texts on the crests' own line.
        let band = texts.filter { abs($0.frame.midY - first.frame.midY) < cardSize.height * 0.25 && $0.text.count <= figureLimit }
            .sorted { $0.frame.minX < $1.frame.minX }
        guard let homeValue = band.first, let awayValue = band.last, band.count >= 2 else {
            return LiveActivityContent(status: statusLine(texts, cardSize: cardSize), clock: clockLine(texts),
                                       title: titleLine(texts, cardSize: cardSize), lines: lines)
        }
        // The names: the text nearest under each crest, the crest's own
        // description when the card gives no name.
        func name(near crest: CardElement) -> String {
            let under = texts
                .filter { $0.frame.midY > crest.frame.maxY - cardSize.height * 0.1 && !$0.text.contains(":") }
                .min { abs($0.frame.midX - crest.frame.midX) < abs($1.frame.midX - crest.frame.midX) }
            return under?.text ?? crest.text
        }
        return LiveActivityContent(
            home: .init(name: name(near: first), value: homeValue.text, crestRect: first.frame),
            away: .init(name: name(near: last), value: awayValue.text, crestRect: last.frame),
            status: statusLine(texts, cardSize: cardSize),
            clock: clockLine(texts),
            title: titleLine(texts, cardSize: cardSize),
            lines: lines
        )
    }

    /// The clock, if the card is running one.
    static func clockLine(_ texts: [CardElement]) -> String? {
        texts.first { isClock($0.text) }?.text
    }

    /// The period or state: the middle text under the figures that is not
    /// the clock — "HT" — or, on a card with no sides, its own state line.
    static func statusLine(_ texts: [CardElement], cardSize: CGSize) -> String? {
        let middle = texts
            .filter { $0.frame.midX > cardSize.width * 0.3 && $0.frame.midX < cardSize.width * 0.7 }
            .filter { !isClock($0.text) }
            .sorted { $0.frame.midY < $1.frame.midY }
        return middle.last?.text
    }

    /// The competition line: the widest text, which is the one that runs
    /// across the card.
    static func titleLine(_ texts: [CardElement], cardSize: CGSize) -> String? {
        texts.filter { $0.frame.width > cardSize.width * 0.5 }.max { $0.frame.width < $1.frame.width }?.text
    }
}
