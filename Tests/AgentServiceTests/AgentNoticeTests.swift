import Testing
import Foundation
import CallService
@testable import AgentService

private let t0 = Date(timeIntervalSince1970: 1_000)

private func session(_ state: AgentSession.State, id: String = "s1", since: Date = t0,
                     turnStart: Date? = nil) -> AgentSession {
    AgentSession(id: id, name: "ledge", baseName: "ledge", project: "ledge", transcript: nil, host: nil,
                 claudePID: nil, state: state, stateSince: since, turnStart: turnStart,
                 lastStamp: 1, lastEvent: since)
}

@Test func eachWaitingHasItsWord() {
    let cases: [(AgentSession.Waiting, String)] = [
        (.permission("Bash: make test"), "Allow?"), (.question("Which?"), "Question"),
        (.plan, "Plan"), (.input("Hi"), "Waiting"),
    ]
    for (waiting, word) in cases {
        let blip = AgentNotice.blip(for: .waiting(session(.waiting(waiting))))
        #expect(blip.word == word)
        #expect(blip.tintName == "yellow")
        #expect(blip.ttl == 8)
        #expect(blip.title == "Waiting · ledge")
        #expect(blip.sessionID == "s1")
    }
    let permission = AgentNotice.blip(for: .waiting(session(.waiting(.permission("Bash: make test")))))
    #expect(permission.caption == "ledge · Bash: make test")
}

@Test func doneSaysHowLong() {
    let blip = AgentNotice.blip(for: .finished(session(.finished(took: 200))))
    #expect(blip.word == "Done")
    #expect(blip.tintName == "green")
    #expect(blip.caption == "ledge · 3m 20s")
    #expect(blip.ttl == 3)
    #expect(blip.title == "Done · ledge")
}

@Test func failedSaysWhy() {
    func caption(_ r: String) -> String { AgentNotice.blip(for: .failed(session(.failed(reason: r)))).caption }
    let blip = AgentNotice.blip(for: .failed(session(.failed(reason: "rate_limit"))))
    #expect(blip.word == "Failed")
    #expect(blip.tintName == "red")
    #expect(blip.ttl == 3)
    #expect(blip.title == "Failed · ledge")
    #expect(caption("rate_limit") == "ledge · Rate limited")
    #expect(caption("overloaded") == "ledge · Overloaded")
    #expect(caption("authentication_failed") == "ledge · Signed out")
    #expect(caption("billing_error") == "ledge · Billing")
    #expect(caption("server_error") == "ledge · API error")
    #expect(caption("x") == "ledge · API error")
}

@Test func durationsReadAsSpoken() {
    #expect(AgentNotice.duration(45) == "45s")
    #expect(AgentNotice.duration(200) == "3m 20s")
    #expect(AgentNotice.duration(180) == "3m")
    #expect(AgentNotice.duration(3840) == "1h 4m")
    #expect(AgentNotice.duration(3600) == "1h")
    #expect(AgentNotice.duration(0.9) == "0s")
}

@Test func theWaitingDetailHasFallbacks() {
    #expect(AgentNotice.detail(.permission("Bash: make test")) == "Bash: make test")
    #expect(AgentNotice.detail(.question("Which?")) == "Which?")
    #expect(AgentNotice.detail(.question(nil)) == "Asks a question")
    #expect(AgentNotice.detail(.plan) == "Plan ready")
    #expect(AgentNotice.detail(.input("Needs a name")) == "Needs a name")
    #expect(AgentNotice.detail(.input(nil)) == "Needs you")
}

@Test func rowsFollowTheSessions() {
    let t1 = t0.addingTimeInterval(50)
    let rows = AgentPanelRows.make([
        session(.working, id: "a", since: t1, turnStart: t0),
        session(.waiting(.permission("Bash: ls")), id: "b"),
        session(.finished(took: 5), id: "c", since: t1),
        session(.failed(reason: "rate_limit"), id: "d"),
        session(.idle, id: "e"),
    ])
    #expect(rows.map(\.id) == ["a", "b", "c", "d", "e"])
    #expect(rows.map(\.mark) == [
        .working(since: t0), .waiting("Bash: ls"), .done(at: t1), .failed("Rate limited"), .idle,
    ])
    #expect(rows[0].name == "ledge")
}
