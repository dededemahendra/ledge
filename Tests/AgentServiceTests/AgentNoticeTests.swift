import Testing
import Foundation
import CallService
@testable import AgentService

private let t0 = Date(timeIntervalSince1970: 1_000)

private func session(_ state: AgentSession.State, id: String = "s1", since: Date = t0,
                     turnStart: Date? = nil) -> AgentSession {
    AgentSession(id: id, name: "Ledge", baseName: "Ledge", project: "ledge", transcript: nil, host: nil,
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
        #expect(blip.title == "Waiting · Ledge")
        #expect(blip.sessionID == "s1")
    }
    let permission = AgentNotice.blip(for: .waiting(session(.waiting(.permission("Bash: make test")))))
    #expect(permission.caption == "Ledge · Bash: make test")
}

@Test func doneSaysHowLong() {
    let blip = AgentNotice.blip(for: .finished(session(.finished(took: 200))))
    #expect(blip.word == "Done")
    #expect(blip.tintName == "green")
    #expect(blip.caption == "Ledge · 3m 20s")
    #expect(blip.ttl == 3)
    #expect(blip.title == "Done · Ledge")
}

@Test func failedSaysWhy() {
    func caption(_ r: String) -> String { AgentNotice.blip(for: .failed(session(.failed(reason: r)))).caption }
    let blip = AgentNotice.blip(for: .failed(session(.failed(reason: "rate_limit"))))
    #expect(blip.word == "Failed")
    #expect(blip.tintName == "red")
    #expect(blip.ttl == 3)
    #expect(blip.title == "Failed · Ledge")
    #expect(caption("rate_limit") == "Ledge · Rate limited")
    #expect(caption("overloaded") == "Ledge · Overloaded")
    #expect(caption("authentication_failed") == "Ledge · Signed out")
    #expect(caption("billing_error") == "Ledge · Billing")
    #expect(caption("server_error") == "Ledge · API error")
    #expect(caption("x") == "Ledge · API error")
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

@Test func theActionTable() {
    let table: [(String?, String?, String)] = [
        (nil, nil, "Thinking"), (nil, "x", "Thinking"),
        ("Bash", "make test", "Running make test"), ("Bash", nil, "Running a command"),
        ("Edit", "a.swift", "Editing a.swift"), ("MultiEdit", "a.swift", "Editing a.swift"),
        ("NotebookEdit", "n.ipynb", "Editing n.ipynb"), ("Edit", nil, "Editing a file"),
        ("Write", "a.swift", "Writing a.swift"), ("Write", nil, "Writing a file"),
        ("Read", "a.swift", "Reading a.swift"), ("Read", nil, "Reading a file"),
        ("Grep", "foo", "Searching foo"), ("Glob", "*.swift", "Searching *.swift"),
        ("Grep", nil, "Searching"), ("Glob", nil, "Searching"),
        ("WebFetch", "example.com", "Fetching example.com"), ("WebFetch", nil, "Fetching a page"),
        ("WebSearch", "swift", "Searching the web for swift"), ("WebSearch", nil, "Searching the web"),
        ("Agent", "x", "Running a subagent"), ("Task", nil, "Running a subagent"),
        ("TodoWrite", "x", "Planning"), ("TodoWrite", nil, "Planning"),
        ("mcp__github__list", "github: list", "github: list"), ("mcp__github__list", nil, "Using a tool"),
        ("Skill", "x", "Using Skill"), ("Skill", nil, "Using Skill"),
    ]
    for (tool, summary, expected) in table {
        #expect(AgentNotice.action(tool: tool, summary: summary) == expected, "\(tool ?? "nil") \(summary ?? "nil")")
    }
}

@Test func theHomeFolderReadsAsTilde() {
    func s(_ t: String, _ home: String = "/Users/x") -> String { AgentNotice.shortened(t, home: home) }
    #expect(s("/Users/x/Developer/a") == "~/Developer/a")
    #expect(s("cd /Users/x && ls /Users/x/a") == "cd ~ && ls ~/a")
    #expect(s("/Users/xy/a") == "/Users/xy/a")
    #expect(s("'/Users/x/a b'") == "'~/a b'")
    #expect(s("/Users/x/a", "") == "/Users/x/a")
    #expect(s("/Users/x/a", "/") == "/Users/x/a")
}

@Test func actionsAndDetailsUseTheTilde() {
    #expect(AgentNotice.action(tool: "Bash", summary: "make -C /Users/x/p test", home: "/Users/x") == "Running make -C ~/p test")
    #expect(AgentNotice.detail(.permission("Bash: ls /Users/x/a"), home: "/Users/x") == "Bash: ls ~/a")
}
