import Testing
import Foundation
@testable import AgentWire

private func hook(_ json: String, env: [String: String] = [:]) -> AgentMessage? {
    AgentTrim.message(hookJSON: Data(json.utf8), environment: env, stamp: 42, pids: [7, 1])
}

@Test func aHookBecomesAMessage() {
    let json = #"{"session_id":"s1","hook_event_name":"PreToolUse","cwd":"/p/ledge","transcript_path":"/t.jsonl","tool_name":"Bash","tool_input":{"command":"make test\nmake dev"}}"#
    let m = hook(json, env: ["CLAUDE_PROJECT_DIR": "/p/ledge"])
    #expect(m?.event == "PreToolUse")
    #expect(m?.session == "s1")
    #expect(m?.project == "/p/ledge")
    #expect(m?.cwd == "/p/ledge")
    #expect(m?.transcript == "/t.jsonl")
    #expect(m?.tool == "Bash")
    #expect(m?.summary == "make test")
    #expect(m?.stamp == 42)
    #expect(m?.pids == [7, 1])
    #expect(m?.v == 1)
}

@Test func theProjectFallsBackToTheFolder() {
    let m = hook(#"{"session_id":"s1","hook_event_name":"Stop","cwd":"/p/ledge"}"#)
    #expect(m?.project == "/p/ledge")
}

@Test func notAHookIsNil() {
    #expect(hook("[]") == nil)
    #expect(hook("{}") == nil)
    #expect(hook(#"{"session_id":1}"#) == nil)
    #expect(hook(#"{"session_id":"s1"}"#) == nil)
    #expect(hook("not json") == nil)
}

@Test func eachToolHasItsSummary() {
    func s(_ tool: String, _ json: String) -> String? {
        let input = try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
        return AgentTrim.summary(tool: tool, input: input)
    }
    for tool in ["Edit", "MultiEdit", "Write", "Read"] {
        #expect(s(tool, #"{"file_path":"/a/b/AppModel.swift"}"#) == "AppModel.swift")
    }
    #expect(s("NotebookEdit", #"{"notebook_path":"/a/n.ipynb"}"#) == "n.ipynb")
    #expect(s("Grep", #"{"pattern":"foo.*"}"#) == "foo.*")
    #expect(s("Glob", #"{"pattern":"foo.*"}"#) == "foo.*")
    #expect(s("WebFetch", #"{"url":"https://docs.swift.org/x"}"#) == "docs.swift.org")
    #expect(s("WebSearch", #"{"query":"swift"}"#) == "swift")
    #expect(s("Agent", #"{"description":"Review the diff"}"#) == "Review the diff")
    #expect(s("Task", #"{"description":"Review the diff"}"#) == "Review the diff")
    #expect(s("mcp__github__create_issue", "{}") == "github: create_issue")
    #expect(s("AskUserQuestion", #"{"questions":[{"question":"Which moments?"}]}"#) == "Which moments?")
    #expect(s("ExitPlanMode", "{}") == nil)
    #expect(s("Unknown", "{}") == nil)
}

@Test func theOtherFieldsComeAcross() {
    let n = hook(#"{"session_id":"s","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Needs you","title":"Claude"}"#)
    #expect(n?.notification == "permission_prompt")
    #expect(n?.message == "Needs you")
    #expect(n?.title == nil)
    #expect(hook(#"{"session_id":"s","hook_event_name":"StopFailure","error":"rate_limit"}"#)?.error == "rate_limit")
    let start = hook(#"{"session_id":"s","hook_event_name":"SessionStart","source":"resume","session_title":"Fix it"}"#)
    #expect(start?.source == "resume")
    #expect(start?.title == "Fix it")
    #expect(hook(#"{"session_id":"s","hook_event_name":"SessionEnd","reason":"clear"}"#)?.reason == "clear")
}

@Test func aBlankOrForeignTitleIsNil() {
    #expect(hook(#"{"session_id":"s","hook_event_name":"Notification","title":"Claude Code"}"#)?.title == nil)
    #expect(hook(#"{"session_id":"s","hook_event_name":"SessionStart","session_title":"  "}"#)?.title == nil)
}

@Test func longTextIsCutTo200() {
    let command = String(repeating: "a", count: 500)
    let m = hook(#"{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"\#(command)"}}"#)
    #expect(m?.summary?.count == 200)
    #expect(m?.summary?.last == "…")
    #expect(AgentTrim.cut("  short  ") == "short")
}

@Test func aLineFitsIn4KB() throws {
    let big = String(repeating: "x", count: 3000)
    var m = AgentMessage(event: "Notification", session: "s", stamp: 1, message: big)
    m.summary = big
    let a = try #require(AgentTrim.line(m))
    #expect(a.count <= AgentTrim.maxLine && a.last == 0x0A)
    let da = try JSONDecoder().decode(AgentMessage.self, from: a)
    #expect(da.message == nil && da.summary == big)

    let path = String(repeating: "p", count: 1200)
    var n = AgentMessage(event: "Notification", session: "s", stamp: 1, cwd: path, project: path, transcript: path,
                         title: "t", tool: "Bash", notification: "idle", message: big, error: "e")
    n.summary = "sum"
    let b = try #require(AgentTrim.line(n))
    #expect(b.count <= AgentTrim.maxLine)
    let db = try JSONDecoder().decode(AgentMessage.self, from: b)
    #expect(db.message == nil && db.summary == nil && db.title == nil)
    #expect(db.tool == "Bash" && db.transcript == path && db.project == path && db.cwd == path)
    #expect(db.notification == "idle" && db.error == "e")

    let wide = String(repeating: "w", count: 1400)
    #expect(AgentTrim.line(AgentMessage(event: "Stop", session: "s", stamp: 1, cwd: wide, project: wide, transcript: wide)) == nil)
    #expect(AgentTrim.line(AgentMessage(event: "Stop", session: "s", stamp: 1, cwd: String(repeating: "c", count: 5000))) == nil)
}

@Test func theLineRoundTrips() throws {
    let m = AgentMessage(event: "PreToolUse", session: "s1", stamp: 99, pids: [3, 2], cwd: "/a/b", project: "/a", tool: "Bash", summary: "ls")
    let line = try #require(AgentTrim.line(m))
    #expect(line.last == 0x0A)
    #expect(try JSONDecoder().decode(AgentMessage.self, from: line.dropLast()) == m)
}
