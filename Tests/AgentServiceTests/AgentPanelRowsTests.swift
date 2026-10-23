import Testing
import Foundation
import CallService
@testable import AgentService

private let t0 = Date(timeIntervalSince1970: 10_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

private func session(_ state: AgentSession.State, id: String, since: Date = t0, turnStart: Date? = nil,
                     last: Date? = nil, action: String? = nil, isCommand: Bool = false) -> AgentSession {
    AgentSession(id: id, name: id.uppercased(), baseName: id.uppercased(), project: id, transcript: nil, host: nil,
                 claudePID: nil, state: state, stateSince: since, turnStart: turnStart,
                 lastStamp: 1, lastEvent: last ?? since, action: action, actionIsCommand: isCommand)
}

@Test func aWaitingSessionIsTheHeroBeforeFailedAndWorking() {
    let card = AgentPanelRows.card([
        session(.working, id: "w", action: "Reading a file"),
        session(.failed(reason: "rate_limit"), id: "f", since: at(90)),
        session(.waiting(.permission("Bash: make test")), id: "p", since: at(50)),
    ], now: at(100))
    let hero = try! #require(card.hero)
    #expect(hero.id == "p" && hero.kind == .needsYou)
    #expect(hero.detail == "Bash: make test" && hero.isCommand && hero.since == at(50))
    #expect(Set(card.rows.map(\.id)) == ["w", "f"])
}

@Test func theLongestWaitingWins() {
    let card = AgentPanelRows.card([
        session(.waiting(.plan), id: "new", since: at(80)),
        session(.waiting(.question("Which?")), id: "old", since: at(20)),
    ], now: at(100))
    #expect(card.hero?.id == "old")
    #expect(card.hero?.detail == "Which?")
    #expect(card.hero?.isCommand == false)
    #expect(card.rows.map(\.id) == ["new"])
}

@Test func aRecentFailureBeatsWorkingButAnOldOneIsNoHero() {
    let recent = AgentPanelRows.card([
        session(.working, id: "w"), session(.failed(reason: "overloaded"), id: "f", since: at(500)),
    ], now: at(1000))
    #expect(recent.hero?.id == "f" && recent.hero?.kind == .failed)
    #expect(recent.hero?.detail == "Overloaded" && recent.hero?.since == nil)
    let old = AgentPanelRows.card([
        session(.working, id: "w", turnStart: at(0)), session(.failed(reason: "overloaded"), id: "f", since: at(300)),
    ], now: at(900))
    #expect(old.hero?.id == "w" && old.hero?.kind == .working)
    #expect(old.rows.map(\.id) == ["f"])
}

@Test func theMostRecentFailureIsTheHero() {
    let card = AgentPanelRows.card([
        session(.failed(reason: "rate_limit"), id: "a", since: at(10)),
        session(.failed(reason: "billing_error"), id: "b", since: at(40)),
    ], now: at(60))
    #expect(card.hero?.id == "b" && card.hero?.detail == "Billing")
}

@Test func theOldestTurnIsTheWorkingHero() {
    let card = AgentPanelRows.card([
        session(.working, id: "a", since: at(30), turnStart: at(30), action: "Thinking"),
        session(.working, id: "b", since: at(60), turnStart: at(5), action: "Running make test", isCommand: true),
        session(.working, id: "c", since: at(8), turnStart: nil),
    ], now: at(100))
    let hero = try! #require(card.hero)
    #expect(hero.id == "b" && hero.kind == .working && hero.since == at(5))
    #expect(hero.detail == "Running make test" && hero.isCommand)
    let thinking = AgentPanelRows.card([session(.working, id: "x")], now: at(1))
    #expect(thinking.hero?.detail == "Thinking" && thinking.hero?.isCommand == false)
}

@Test func noHeroWhenAllAreIdleOrDone() {
    let card = AgentPanelRows.card([
        session(.idle, id: "i"), session(.finished(took: 5), id: "d"),
    ], now: at(10))
    #expect(card.hero == nil)
    #expect(card.rows.count == 2)
}

@Test func rowsAreGroupedAndOrderedWithTheirMarks() {
    let card = AgentPanelRows.card([
        session(.idle, id: "i1", last: at(90)),
        session(.finished(took: 200), id: "d1", since: at(20), last: at(20)),
        session(.failed(reason: "rate_limit"), id: "f1", since: at(2000), last: at(2000)),
        session(.working, id: "w1", since: at(10), turnStart: at(4), last: at(10), action: "Editing a file"),
        session(.working, id: "w2", since: at(12), turnStart: at(6), last: at(70), action: "Thinking"),
        session(.waiting(.permission("Bash: ls")), id: "p1", since: at(1), last: at(1)),
        session(.waiting(.input(nil)), id: "p2", since: at(3), last: at(3)),
        session(.finished(took: 9), id: "d2", since: at(60), last: at(60)),
        session(.idle, id: "i2", last: at(95)),
    ], now: at(3000))
    // failed is stale (older than 600 s), so no failed hero; the longest waiting is the hero.
    #expect(card.hero?.id == "p1")
    // done and idle are hidden while anything is waiting or working.
    #expect(card.rows.map(\.id) == ["p2", "w2", "w1", "f1"])
    #expect(card.rows[0].mark == .waiting(detail: "Needs you", since: at(3)))
    #expect(card.rows[1].mark == .working(action: "Thinking", since: at(6)))
    #expect(card.rows[2].mark == .working(action: "Editing a file", since: at(4)))
    #expect(card.rows[3].mark == .failed(reason: "Rate limited", at: at(2000)))
}

@Test func doneAndIdleRowsAppearOnceNothingIsLive() {
    let card = AgentPanelRows.card([
        session(.idle, id: "i1", last: at(90)),
        session(.finished(took: 9), id: "d1", since: at(60), last: at(60)),
        session(.failed(reason: "rate_limit"), id: "f1", since: at(2000), last: at(2000)),
    ], now: at(3000))
    #expect(card.hero == nil)
    #expect(card.rows.map(\.id) == ["f1", "d1", "i1"])
    #expect(card.rows[1].mark == .done(took: 9, at: at(60)))
    #expect(card.rows[2].mark == .idle)
}

@Test func whileOneWorksDoneAndIdleAreHidden() {
    let card = AgentPanelRows.card([
        session(.working, id: "w"), session(.finished(took: 3), id: "d"), session(.idle, id: "i"),
    ], now: at(10))
    #expect(card.hero?.id == "w")
    #expect(card.rows.isEmpty)
}

@Test func whileSomeRunFailedStaysAndDoneIsHidden() {
    let card = AgentPanelRows.card([
        session(.waiting(.plan), id: "p", since: at(1)),
        session(.working, id: "w", since: at(2), last: at(2)),
        session(.finished(took: 3), id: "d", last: at(3)),
        session(.failed(reason: "rate_limit"), id: "f", since: at(4), last: at(4)),
    ], now: at(5000))
    #expect(card.hero?.id == "p")
    #expect(card.rows.map(\.id) == ["w", "f"])
}

@Test func aRecentFailureHeroLeavesTheDoneRow() {
    let card = AgentPanelRows.card([
        session(.failed(reason: "rate_limit"), id: "f", since: at(90)),
        session(.finished(took: 3), id: "d"),
    ], now: at(100))
    #expect(card.hero?.id == "f" && card.hero?.kind == .failed)
    #expect(card.rows.map(\.id) == ["d"])
}

@Test func aWorkingRowWithoutAnActionIsThinking() {
    let card = AgentPanelRows.card([
        session(.waiting(.plan), id: "p"), session(.working, id: "w", since: at(2)),
    ], now: at(10))
    #expect(card.rows.first?.mark == .working(action: "Thinking", since: at(2)))
}

@Test func aDoneRowWithoutALengthCarriesNone() {
    let card = AgentPanelRows.card([session(.finished(took: nil), id: "d", since: at(60))], now: at(100))
    #expect(card.rows.map(\.mark) == [.done(took: nil, at: at(60))])
}
