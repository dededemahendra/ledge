import Testing
import CoreGraphics
import Foundation
@testable import LiveActivityService

/// The real card, as its Accessibility tree gave it (2026-10-01): a
/// football match, 408×122 pt, crests 40 pt, the figures above the names.
private func matchCard() -> [CardElement] {
    [
        .init(kind: .image, text: "Indonesia", frame: CGRect(x: 50, y: 26, width: 40, height: 40)),
        .init(kind: .text, text: "6", frame: CGRect(x: 144, y: 29, width: 18, height: 33)),
        .init(kind: .image, text: "FIFA ASEAN Cup Premier Division Grp. A", frame: CGRect(x: 191, y: 33, width: 26, height: 26)),
        .init(kind: .text, text: "1", frame: CGRect(x: 250, y: 29, width: 13, height: 33)),
        .init(kind: .image, text: "Bangladesh", frame: CGRect(x: 318, y: 26, width: 40, height: 40)),
        .init(kind: .text, text: "Indonesia", frame: CGRect(x: 42, y: 82, width: 56, height: 14)),
        .init(kind: .text, text: "HT", frame: CGRect(x: 175, y: 82, width: 17, height: 14)),
        .init(kind: .text, text: "5:56", frame: CGRect(x: 196, y: 82, width: 36, height: 14)),
        .init(kind: .text, text: "Bangladesh", frame: CGRect(x: 304, y: 82, width: 68, height: 14)),
    ]
}

private let cardSize = CGSize(width: 408, height: 122)

@Test func aMatchCardReadsAsTwoSidesAPeriodAndAClock() {
    let content = CardReader.read(matchCard(), cardSize: cardSize)
    #expect(content.isMatch)
    #expect(content.home?.name == "Indonesia" && content.home?.value == "6")
    #expect(content.away?.name == "Bangladesh" && content.away?.value == "1")
    #expect(content.clock == "5:56")
    #expect(content.status == "HT")
    #expect(content.home?.crestRect == CGRect(x: 50, y: 26, width: 40, height: 40), "the crest's own rectangle, for cutting")
    #expect(content.lines.first == "6", "everything the card says, in reading order")
}

/// A card with no sides — a golf round starting — is not a match, and
/// still says what state it is in.
@Test func aCardWithoutSidesIsNotAMatch() {
    let content = CardReader.read([
        .init(kind: .text, text: "PGA Tour · Bank of Utah Championship", frame: CGRect(x: 20, y: 20, width: 368, height: 14)),
        .init(kind: .text, text: "Round 1, Starting Soon", frame: CGRect(x: 120, y: 60, width: 168, height: 14)),
    ], cardSize: cardSize)
    #expect(!content.isMatch)
    #expect(content.status == "Round 1, Starting Soon")
    #expect(content.title == "PGA Tour · Bank of Utah Championship")
    #expect(content.clock == nil)
}

@Test func onlyAFigureThatLooksLikeAClockIsOne() {
    #expect(CardReader.isClock("5:56") && CardReader.isClock("12:03") && CardReader.isClock("1:02:30"))
    #expect(!CardReader.isClock("HT") && !CardReader.isClock("6") && !CardReader.isClock("5:5") && !CardReader.isClock(""))
}

@Test func anEmptyCardSaysNothing() {
    #expect(CardReader.read([], cardSize: cardSize) == LiveActivityContent())
    #expect(CardReader.read(matchCard(), cardSize: .zero) == LiveActivityContent())
}
