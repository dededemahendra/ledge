import Testing
import Foundation
import AgentWire
import CallService
@testable import AgentService

private let t0 = Date(timeIntervalSince1970: 1_000)
private let vscode = CallAppInfo(bundleID: "com.microsoft.VSCode", name: "Code", pid: 7)
private let facts = AgentFacts(claudePID: 42, isHeadless: false, host: vscode)

private func msg(_ event: String, stamp: Int64, session: String = "s1", project: String? = "/p/ledge",
                 transcript: String? = "/t/s1.jsonl", title: String? = nil, tool: String? = nil,
                 summary: String? = nil, notification: String? = nil, message: String? = nil,
                 error: String? = nil) -> AgentMessage {
    AgentMessage(event: event, session: session, stamp: stamp, project: project, transcript: transcript,
                 title: title, tool: tool, summary: summary, notification: notification,
                 message: message, error: error)
}

private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

@Test func aPromptStartsATurn() {
    var s = AgentSessions()
    let m = s.apply(msg("UserPromptSubmit", stamp: 1), facts: facts, now: t0)
    #expect(m == nil)
    #expect(s.sessions.count == 1)
    #expect(s.sessions[0].state == .working)
    #expect(s.sessions[0].turnStart == t0)
    #expect(s.sessions[0].host == vscode)
    #expect(s.sessions[0].claudePID == 42)
}

@Test func aSessionFirstSeenMidTurnWorksFromNow() {
    var s = AgentSessions()
    _ = s.apply(msg("PreToolUse", stamp: 1, tool: "Read"), facts: facts, now: at(5))
    #expect(s.sessions[0].state == .working)
    #expect(s.sessions[0].turnStart == at(5))
    #expect(s.sessions[0].name == "Ledge")
    #expect(s.sessions[0].project == "ledge")
}

@Test func aPermissionRequestWaitsWithWhatItWants() {
    var s = AgentSessions()
    let m = s.apply(msg("PermissionRequest", stamp: 1, tool: "Bash", summary: "make test"), facts: facts, now: t0)
    #expect(s.sessions[0].state == .waiting(.permission("Bash: make test")))
    #expect(m == .waiting(s.sessions[0]))
    var t = AgentSessions()
    _ = t.apply(msg("PermissionRequest", stamp: 1, tool: "Bash"), facts: facts, now: t0)
    #expect(t.sessions[0].state == .waiting(.permission("Bash")))
}

@Test func askUserQuestionAndExitPlanModeWait() {
    var s = AgentSessions()
    let q = s.apply(msg("PreToolUse", stamp: 1, tool: "AskUserQuestion", summary: "Which?"), facts: facts, now: t0)
    #expect(s.sessions[0].state == .waiting(.question("Which?")))
    #expect(q != nil)
    _ = s.apply(msg("PostToolUse", stamp: 2, tool: "AskUserQuestion"), facts: facts, now: at(1))
    let p = s.apply(msg("PreToolUse", stamp: 3, tool: "ExitPlanMode"), facts: facts, now: at(2))
    #expect(s.sessions[0].state == .waiting(.plan))
    #expect(p != nil)
}

@Test func aNotificationWaitsOnlyIfNotAlready() {
    var s = AgentSessions()
    let text = "Claude needs your permission"
    let a = s.apply(msg("Notification", stamp: 1, notification: "permission_prompt", message: text), facts: facts, now: t0)
    #expect(s.sessions[0].state == .waiting(.input(text)))
    #expect(a != nil)
    let b = s.apply(msg("Notification", stamp: 2, notification: "permission_prompt", message: text), facts: facts, now: at(1))
    #expect(b == nil)
}

@Test func idleAndOtherNotificationsDoNothing() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1), facts: facts, now: t0)
    for kind in ["idle_prompt", "auth_success"] {
        let m = s.apply(msg("Notification", stamp: 2, notification: kind, message: "x"), facts: facts, now: at(1))
        #expect(m == nil)
        #expect(s.sessions[0].state == .working)
    }
}

@Test func answeringGoesBackToWorkingQuietly() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1), facts: facts, now: t0)
    _ = s.apply(msg("PermissionRequest", stamp: 2, tool: "Bash"), facts: facts, now: at(1))
    let m = s.apply(msg("PostToolUse", stamp: 3, tool: "Bash"), facts: facts, now: at(2))
    #expect(m == nil)
    #expect(s.sessions[0].state == .working)
    #expect(s.sessions[0].turnStart == t0)
}

@Test func aSecondPromptIsANewMoment() {
    var s = AgentSessions()
    _ = s.apply(msg("PermissionRequest", stamp: 1, tool: "Bash"), facts: facts, now: t0)
    _ = s.apply(msg("PostToolUse", stamp: 2, tool: "Bash"), facts: facts, now: at(1))
    let m = s.apply(msg("PermissionRequest", stamp: 3, tool: "Bash"), facts: facts, now: at(2))
    #expect(m != nil)
}

@Test func waitingToWaitingUpdatesWithoutAMoment() {
    var s = AgentSessions()
    _ = s.apply(msg("PermissionRequest", stamp: 1, tool: "Bash", summary: "a"), facts: facts, now: t0)
    let m = s.apply(msg("PermissionRequest", stamp: 2, tool: "Bash", summary: "b"), facts: facts, now: at(1))
    #expect(m == nil)
    #expect(s.sessions[0].state == .waiting(.permission("Bash: b")))
}

@Test func stopFinishesWithTheTurnsLength() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1), facts: facts, now: t0)
    let m = s.apply(msg("Stop", stamp: 2), facts: facts, now: at(200))
    #expect(s.sessions[0].state == .finished(took: 200))
    #expect(s.sessions[0].turnStart == nil)
    #expect(m == .finished(s.sessions[0]))
}

@Test func stopAfterAnInterruptStillFinishes() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1), facts: facts, now: t0)
    s.interrupt(session: "s1", now: at(10))
    #expect(s.sessions[0].state == .idle)
    #expect(s.sessions[0].turnStart == nil)
    let m = s.apply(msg("Stop", stamp: 2), facts: facts, now: at(12))
    #expect(m != nil)
    if case .finished = s.sessions[0].state {} else { Issue.record("not finished") }
}

@Test func stopFailureFailsWithItsReason() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1), facts: facts, now: t0)
    let m = s.apply(msg("StopFailure", stamp: 2, error: "rate_limit"), facts: facts, now: at(5))
    #expect(s.sessions[0].state == .failed(reason: "rate_limit"))
    #expect(m == .failed(s.sessions[0]))
}

@Test func aLatePreToolUseDoesNotHideThePrompt() {
    var s = AgentSessions()
    _ = s.apply(msg("PermissionRequest", stamp: 20, tool: "Bash"), facts: facts, now: t0)
    let m = s.apply(msg("PreToolUse", stamp: 10, tool: "Bash"), facts: facts, now: at(1))
    #expect(m == nil)
    #expect(s.sessions[0].state == .waiting(.permission("Bash")))
}

@Test func anEqualStampIsApplied() {
    var s = AgentSessions()
    _ = s.apply(msg("PreToolUse", stamp: 5, tool: "Bash"), facts: facts, now: t0)
    _ = s.apply(msg("PermissionRequest", stamp: 5, tool: "Bash"), facts: facts, now: at(1))
    #expect(s.sessions[0].state == .waiting(.permission("Bash")))
}

@Test func sessionEndRemovesIt() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1), facts: facts, now: t0)
    _ = s.apply(msg("SessionEnd", stamp: 2), facts: facts, now: at(1))
    #expect(s.sessions.isEmpty)
    _ = s.apply(msg("SessionEnd", stamp: 3, session: "nope"), facts: facts, now: at(2))
    #expect(s.sessions.isEmpty)
}

@Test func sessionStartOnAKnownSessionIdlesQuietly() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1), facts: facts, now: t0)
    let m = s.apply(msg("SessionStart", stamp: 2), facts: facts, now: at(1))
    #expect(m == nil)
    #expect(s.sessions[0].state == .idle)
    #expect(s.sessions[0].turnStart == nil)
}

@Test func theClaudeProcessExitingRemovesIt() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1), facts: facts, now: t0)
    #expect(s.claudePIDs == [42])
    s.processExited(42)
    #expect(s.sessions.isEmpty)
}

@Test func anInterruptIdlesWithoutAMoment() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1), facts: facts, now: t0)
    s.interrupt(session: "s1", now: at(3))
    #expect(s.sessions[0].state == .idle)
    #expect(s.sessions[0].turnStart == nil)
    s.interrupt(session: "ghost", now: at(4))
    #expect(s.sessions.count == 1)
}

@Test func headlessSessionsAreIgnored() {
    var s = AgentSessions()
    let headless = AgentFacts(claudePID: 42, isHeadless: true, host: nil)
    let m = s.apply(msg("UserPromptSubmit", stamp: 1), facts: headless, now: t0)
    #expect(m == nil)
    #expect(s.sessions.isEmpty)
}

@Test func nameClashesGetANumber() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1, session: "a"), facts: facts, now: t0)
    _ = s.apply(msg("UserPromptSubmit", stamp: 1, session: "b"), facts: facts, now: at(1))
    #expect(Set(s.sessions.map(\.name)) == ["Ledge", "Ledge 2"])
    _ = s.apply(msg("SessionEnd", stamp: 2, session: "a"), facts: facts, now: at(2))
    _ = s.apply(msg("UserPromptSubmit", stamp: 1, session: "c"), facts: facts, now: at(3))
    #expect(s.sessions.first { $0.id == "c" }?.name == "Ledge")
    #expect(s.sessions.first { $0.id == "b" }?.name == "Ledge 2")
}

@Test func namesArePrettified() {
    var s = AgentSessions()
    _ = s.apply(msg("SessionStart", stamp: 1, project: "/p/mornington-green"), facts: facts, now: t0)
    #expect(s.sessions[0].name == "Mornington green")
    _ = s.apply(msg("UserPromptSubmit", stamp: 2, title: "fix the login_bug"), facts: facts, now: at(1))
    #expect(s.sessions[0].name == "Fix the login bug")
}

@Test func theActionFollowsTheTurn() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1), facts: facts, now: t0)
    #expect(s.sessions[0].action == "Thinking")
    #expect(s.sessions[0].actionIsCommand == false)
    _ = s.apply(msg("PreToolUse", stamp: 2, tool: "Bash", summary: "make test"), facts: facts, now: at(1))
    #expect(s.sessions[0].action == "Running make test")
    #expect(s.sessions[0].actionIsCommand)
    _ = s.apply(msg("PostToolUse", stamp: 3, tool: "Bash"), facts: facts, now: at(2))
    #expect(s.sessions[0].action == "Running make test")
    _ = s.apply(msg("PreToolUse", stamp: 4, tool: "Read", summary: "a.swift"), facts: facts, now: at(3))
    #expect(s.sessions[0].action == "Reading a.swift")
    #expect(s.sessions[0].actionIsCommand == false)
    _ = s.apply(msg("Stop", stamp: 5), facts: facts, now: at(4))
    #expect(s.sessions[0].action == nil)
    #expect(s.sessions[0].actionIsCommand == false)
}

@Test func aSessionFirstSeenMidTurnTakesTheFirstToolAction() {
    var s = AgentSessions()
    _ = s.apply(msg("PreToolUse", stamp: 1, tool: "Grep", summary: "foo"), facts: facts, now: t0)
    #expect(s.sessions[0].action == "Searching foo")
}

@Test func anInterruptClearsTheAction() {
    var s = AgentSessions()
    _ = s.apply(msg("PreToolUse", stamp: 1, tool: "Bash", summary: "ls"), facts: facts, now: t0)
    s.interrupt(session: "s1", now: at(1))
    #expect(s.sessions[0].action == nil)
}

@Test func aTitleNamesTheSession() {
    var s = AgentSessions()
    _ = s.apply(msg("SessionStart", stamp: 1, title: "Agent island"), facts: facts, now: t0)
    #expect(s.sessions[0].name == "Agent island")
    _ = s.apply(msg("UserPromptSubmit", stamp: 2, title: "Renamed"), facts: facts, now: at(1))
    #expect(s.sessions[0].name == "Renamed")
}

@Test func forgettingDropsQuietSessionsAfterAnHour() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1, session: "done"), facts: facts, now: t0)
    _ = s.apply(msg("Stop", stamp: 2, session: "done"), facts: facts, now: t0)
    _ = s.apply(msg("UserPromptSubmit", stamp: 1, session: "busy"), facts: facts, now: t0)
    s.forget(now: at(3599))
    #expect(s.sessions.count == 2)
    s.forget(now: at(3600))
    #expect(s.sessions.map(\.id) == ["busy"])
}

@Test func theListIsMostRecentlyActiveFirst() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1, session: "a"), facts: facts, now: t0)
    _ = s.apply(msg("UserPromptSubmit", stamp: 1, session: "b"), facts: facts, now: at(1))
    #expect(s.sessions.map(\.id) == ["b", "a"])
    _ = s.apply(msg("PreToolUse", stamp: 2, session: "a", tool: "Read"), facts: facts, now: at(2))
    #expect(s.sessions.map(\.id) == ["a", "b"])
}

@Test func transcriptsAreWatchedOnlyWhileWorkingOrWaiting() {
    var s = AgentSessions()
    _ = s.apply(msg("SessionStart", stamp: 1), facts: facts, now: t0)
    #expect(s.transcriptsToWatch.isEmpty)
    _ = s.apply(msg("UserPromptSubmit", stamp: 2), facts: facts, now: at(1))
    #expect(s.transcriptsToWatch == ["s1": "/t/s1.jsonl"])
    _ = s.apply(msg("PermissionRequest", stamp: 3, tool: "Bash"), facts: facts, now: at(2))
    #expect(s.transcriptsToWatch == ["s1": "/t/s1.jsonl"])
    _ = s.apply(msg("Stop", stamp: 4), facts: facts, now: at(3))
    #expect(s.transcriptsToWatch.isEmpty)
}

@Test func aNameStaysPutWhenAnotherSessionEnds() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1, session: "a"), facts: facts, now: t0)
    _ = s.apply(msg("UserPromptSubmit", stamp: 1, session: "b"), facts: facts, now: at(1))
    _ = s.apply(msg("SessionEnd", stamp: 2, session: "a"), facts: facts, now: at(2))
    _ = s.apply(msg("PreToolUse", stamp: 2, session: "b", tool: "Read"), facts: facts, now: at(3))
    #expect(s.sessions.first { $0.id == "b" }?.name == "Ledge 2")
    _ = s.apply(msg("UserPromptSubmit", stamp: 1, session: "c"), facts: facts, now: at(4))
    #expect(s.sessions.first { $0.id == "c" }?.name == "Ledge")
}

@Test func aRepeatedStopOrStopFailureChangesNothing() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1), facts: facts, now: t0)
    _ = s.apply(msg("Stop", stamp: 2), facts: facts, now: at(10))
    let before = s.sessions[0]
    #expect(s.apply(msg("Stop", stamp: 3), facts: facts, now: at(50)) == nil)
    #expect(s.apply(msg("StopFailure", stamp: 4, error: "x"), facts: facts, now: at(60)) == nil)
    #expect(s.sessions[0].state == before.state)
    #expect(s.sessions[0].stateSince == before.stateSince)
    var f = AgentSessions()
    _ = f.apply(msg("StopFailure", stamp: 1, error: "overloaded"), facts: facts, now: t0)
    #expect(f.apply(msg("StopFailure", stamp: 2, error: "rate_limit"), facts: facts, now: at(5)) == nil)
    #expect(f.apply(msg("Stop", stamp: 3), facts: facts, now: at(6)) == nil)
    #expect(f.sessions[0].state == .failed(reason: "overloaded"))
}

@Test func stopWhileIdleTakesTimeSinceTheStateBegan() {
    var s = AgentSessions()
    _ = s.apply(msg("SessionStart", stamp: 1), facts: facts, now: t0)
    _ = s.apply(msg("Stop", stamp: 2), facts: facts, now: at(2))
    #expect(s.sessions[0].state == .finished(took: 2))
}

@Test func laterFactsReplaceEarlierOnes() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1), facts: facts, now: t0)
    let ghostty = CallAppInfo(bundleID: "com.mitchellh.ghostty", name: "Ghostty", pid: 9)
    _ = s.apply(msg("PreToolUse", stamp: 2), facts: AgentFacts(claudePID: 77, isHeadless: false, host: ghostty), now: at(1))
    #expect(s.sessions[0].host == ghostty)
    #expect(s.sessions[0].claudePID == 77)
    _ = s.apply(msg("PreToolUse", stamp: 3), facts: AgentFacts(claudePID: nil, isHeadless: false, host: nil), now: at(2))
    #expect(s.sessions[0].host == ghostty)
    #expect(s.sessions[0].claudePID == 77)
}

@Test func stopWhileWaitingFinishesWithAMoment() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1), facts: facts, now: t0)
    _ = s.apply(msg("PermissionRequest", stamp: 2, tool: "Bash"), facts: facts, now: at(5))
    let m = s.apply(msg("Stop", stamp: 3), facts: facts, now: at(20))
    #expect(s.sessions[0].state == .finished(took: 20))
    #expect(m == .finished(s.sessions[0]))
}

@Test func stopFailureWhileWaitingFailsWithAMoment() {
    var s = AgentSessions()
    _ = s.apply(msg("PermissionRequest", stamp: 2, tool: "Bash"), facts: facts, now: t0)
    let m = s.apply(msg("StopFailure", stamp: 3, error: "overloaded"), facts: facts, now: at(5))
    #expect(s.sessions[0].state == .failed(reason: "overloaded"))
    #expect(m == .failed(s.sessions[0]))
}

@Test func aLaterClashingTitleGetsASuffix() {
    var s = AgentSessions()
    _ = s.apply(msg("UserPromptSubmit", stamp: 1, session: "a", title: "Island"), facts: facts, now: t0)
    _ = s.apply(msg("UserPromptSubmit", stamp: 1, session: "b"), facts: facts, now: at(1))
    _ = s.apply(msg("PreToolUse", stamp: 2, session: "b", title: "Island", tool: "Read"), facts: facts, now: at(2))
    #expect(s.sessions.first { $0.id == "a" }?.name == "Island")
    #expect(s.sessions.first { $0.id == "b" }?.name == "Island 2")
}
