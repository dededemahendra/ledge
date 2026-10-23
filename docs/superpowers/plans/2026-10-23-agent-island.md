# Coding agents on the island Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Claude Code sessions on this Mac show on the island: a blip when one waits for the user, finishes or fails; a sticky item while any waits or works; a hover card listing them; a click that brings the session's window forward.

**Architecture:** Background (`async`) command hooks that Ledge writes into `~/.claude/settings.json` run a small helper (`LedgeAgentHook`, shipped in the bundle as `ledge-agent-hook` and copied to Application Support). The helper trims the hook's JSON to an `AgentMessage` (new `AgentWire` library) and writes one line to a Unix socket. A new `AgentService` library listens, keeps per-session state in a pure `AgentSessions` machine, watches each `claude` process and transcript, and tells `AppModel`, which draws the blips, the sticky items and the card through NotchKit as GitHub's are drawn.

**Tech Stack:** Swift 6 (strict concurrency), SwiftPM, SwiftUI, AppKit, Darwin (sysctl, AF_UNIX sockets, libproc), Accessibility (`AXUIElement`), swift-testing. macOS 27.

**Spec:** `docs/superpowers/specs/2026-10-23-agent-island-design.md`

## Global Constraints

- Platform floor macOS 27; no third-party dependencies; Swift language mode v6.
- Hook events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `StopFailure`, `SessionEnd`. `"matcher": "*"` only on `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`.
- Each Ledge hook: `{"type": "command", "command": <guarded>, "async": true, "timeout": 5}`, where `<guarded>` is `[ -x "<helper>" ] && "<helper>" || true` and `<helper>` is `$HOME/Library/Application Support/Ledge/ledge-agent-hook` written out as an absolute path. Ledge's entries are recognised by the substring `Ledge/ledge-agent-hook` in `command`.
- Socket: `~/Library/Application Support/Ledge/agents.sock`, mode 0600. One line per connection, read up to 8 KB. The helper gives up after 0.5 s and always exits 0.
- Message: JSON, `v: 1`, at most 4096 bytes with its newline; each string field cut to 200 characters (199 and `…`); over 4 KB, drop `message`, then `summary`, then `title`, then give up (send nothing).
- Interrupt markers, exact: `[Request interrupted by user]`, `[Request interrupted by user for tool use]`.
- Kinds: `agent` priority 39, TTL 8 (finished and failed blips pass 3); `agentWaiting` priority 25, sticky; `agentRun` priority 8, sticky. Record ids `"agent"`, `"agent-waiting"`, `"agent-run"`.
- Claude orange `#D97757` = `.color(red: 0.851, green: 0.467, blue: 0.341)`. Waiting words amber (`"yellow"`), done green (`"green"`), failed red (`"red"`).
- Words: "Allow?" (permission), "Question" (AskUserQuestion), "Plan" (ExitPlanMode), "Waiting" (other input), "Done", "Failed". Captions `name · detail`.
- Durations: "45s", "3m 20s", "1h 4m". Clock: `TimerText.format(seconds:)`.
- Failure reasons: `rate_limit` "Rate limited", `overloaded` "Overloaded", `authentication_failed` "Signed out", `billing_error` "Billing", anything else "API error".
- Settings: `agentsEnabled` false; `agentWaiting`, `agentFinished`, `agentWorking`, `agentFailed` true. Pane "Agents", symbol `asterisk`, Claude orange.
- Never shown on the lock screen. Never log prompts, commands, file names or session names (log event names and counts only).
- Run tests with `make test` or `make test FILTER=<name>`.
- Commit messages: the repo's lowercase sentence style, ending with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Ledge quit, crashed or deleted while sessions run:** Claude shows no error lines and is never slowed. Pinned by `withNoListenerTheHelperExitsZeroQuickly` (Task 3) and `everyHookIsAsyncAndGuarded` (Task 4).
2. **The user's `settings.json` shared with Claude Code, Superset, Orca and RTK:** re-enabling is idempotent, others' entries stay as they are, and an untouched file is byte-identical. Pinned by `installingTwiceChangesNothing`, `othersEntriesAreKept` and `aClaudeWrittenFileRoundTripsByteForByte` (Task 4).
3. **Esc mid-turn or at a prompt** (no hook fires): the session goes idle, not stuck working or waiting. Pinned by `onlyAnExactUserTextIsAnInterrupt` (Task 5) and `anInterruptLineInTheTranscriptIdlesTheSession` (Task 7).
4. **Background hooks arriving out of order** (`PermissionRequest` before its `PreToolUse`): the prompt still shows. Pinned by `aLatePreToolUseDoesNotHideThePrompt` (Task 5).
5. **Sessions already running when the switch goes on, and several in one folder:** they join on their first tool call, working with a clock from then, named "ledge", "ledge 2". Pinned by `aSessionFirstSeenMidTurnWorksFromNow` and `nameClashesGetANumber` (Task 5). A `Write` with a megabyte of content is drained and trimmed: `aHugeToolInputIsDrainedAndTrimmed` (Task 3).

---

### Task 1: Verify the hook facts on this Mac (no commit)

Throwaway. Headless only, no user needed; the interactive checks are in Task 12.

**Files:**
- Create (scratch, outside the repo): `<scratchpad>/agentprobe/log.sh`, `<scratchpad>/agentprobe/.claude/settings.json`

- [ ] **Step 1: Write the logger.** `log.sh` (chmod +x) appends to `<scratchpad>/agentprobe/log.txt`, per call: a line `== <epoch with microseconds via perl -MTime::HiRes=time -e 'printf "%.6f", time'> pid=$$ ppid=$PPID project=$CLAUDE_PROJECT_DIR`; then stdin (`cat`); then `ps -o pid=,ppid=,comm=,args= -p $PPID` and the same for the parent's parent.
- [ ] **Step 2: Write the project settings.** `.claude/settings.json` with a group for each of the ten events, each `{"type":"command","command":"<scratchpad>/agentprobe/log.sh","async":true}`, with `"matcher": "*"` on the four tool events.
- [ ] **Step 3: Run one headless session.** `cd <scratchpad>/agentprobe && claude -p "Run the shell command: echo hi" --allowedTools "Bash(echo:*)"`.
- [ ] **Step 4: Read the log and check:**
  - `SessionStart`, `UserPromptSubmit`, `PreToolUse` (`tool_name` `Bash`, `tool_input.command`), `PostToolUse`, `Stop`, `SessionEnd` each arrived with `session_id`, `cwd`, `transcript_path`, `hook_event_name`;
  - `CLAUDE_PROJECT_DIR` is set;
  - the hook's parent is a shell or `claude` itself, and within two hops there is a process whose `comm` ends in `claude` and whose `args` contain `-p`;
  - the session's answer was not delayed by the hooks (the run takes as long as without them).
- [ ] **Step 5: Gate.** If a field is missing, the env var is unset, or no `claude` process is within three hops, stop and report to the user with the log before Task 2: the helper's chain walk and the message fields rest on these. Record the observed chain shape in the Task 3 code comment.

### Task 2: `AgentWire`: the message and the trimming

**Files:**
- Modify: `Package.swift`: add `.target(name: "AgentWire")` and `.testTarget(name: "AgentWireTests", dependencies: ["AgentWire"])`.
- Create: `Sources/AgentWire/AgentMessage.swift`, `Sources/AgentWire/AgentTrim.swift`
- Test: `Tests/AgentWireTests/AgentTrimTests.swift`

**Interfaces:**
- Produces:

```swift
public struct AgentMessage: Codable, Sendable, Equatable {
    public var v: Int
    public var event: String
    public var session: String
    public var cwd: String?
    public var project: String?
    public var transcript: String?
    public var title: String?
    public var tool: String?
    public var summary: String?
    public var notification: String?
    public var message: String?
    public var error: String?
    public var source: String?
    public var reason: String?
    /// The helper process's start, from the kernel, in microseconds since 1970.
    public var stamp: Int64
    /// The helper's parents, nearest first.
    public var pids: [Int32]
    public init(event: String, session: String, stamp: Int64, pids: [Int32] = [], cwd: String? = nil,
                project: String? = nil, transcript: String? = nil, title: String? = nil, tool: String? = nil,
                summary: String? = nil, notification: String? = nil, message: String? = nil,
                error: String? = nil, source: String? = nil, reason: String? = nil)   // v = 1
}

public enum AgentTrim {
    public static let maxField = 200
    public static let maxLine = 4096
    /// `nil` unless the input is a JSON object with string `session_id` and `hook_event_name`.
    public static func message(hookJSON: Data, environment: [String: String], stamp: Int64, pids: [Int32]) -> AgentMessage?
    /// One line about the tool call, or nil.
    public static func summary(tool: String, input: [String: Any]) -> String?
    /// The JSON line with its "\n", within `maxLine`, or nil when even the trimmed line is too long.
    public static func line(_ message: AgentMessage) -> Data?
    /// Trimmed of surrounding whitespace, cut to `maxField` characters (199 and "…").
    public static func cut(_ text: String) -> String
}
```

- [ ] **Step 1: Write the failing tests:**

```swift
@Test func aHookBecomesAMessage()
    // {"session_id":"s1","hook_event_name":"PreToolUse","cwd":"/p/ledge","transcript_path":"/t.jsonl",
    //  "tool_name":"Bash","tool_input":{"command":"make test\nmake dev"}} with env CLAUDE_PROJECT_DIR=/p/ledge
    // → event "PreToolUse", session "s1", project "/p/ledge", tool "Bash", summary "make test", stamp and pids as given
@Test func theProjectFallsBackToTheFolder()          // no CLAUDE_PROJECT_DIR → project == cwd
@Test func notAHookIsNil()                           // "[]", "{}", {"session_id":1}, invalid JSON → nil
@Test func eachToolHasItsSummary()
    // Edit/MultiEdit/Write/Read {"file_path":"/a/b/AppModel.swift"} → "AppModel.swift"
    // NotebookEdit {"notebook_path":"/a/n.ipynb"} → "n.ipynb"; Grep/Glob {"pattern":"foo.*"} → "foo.*"
    // WebFetch {"url":"https://docs.swift.org/x"} → "docs.swift.org"; WebSearch {"query":"swift"} → "swift"
    // Agent and Task {"description":"Review the diff"} → "Review the diff"
    // mcp__github__create_issue {} → "github: create_issue"
    // AskUserQuestion {"questions":[{"question":"Which moments?"}]} → "Which moments?"
    // ExitPlanMode {} → nil; Unknown {} → nil
@Test func theOtherFieldsComeAcross()
    // Notification: notification_type, message, title; StopFailure: error; SessionStart: source,
    // session_title → title; SessionEnd: reason
@Test func longTextIsCutTo200()                      // a 500-character command → 200 characters, the last "…"
@Test func aLineFitsIn4KB()
    // built directly (not through `message`, which cuts): an AgentMessage with a 3000-char message and a
    // 3000-char summary → the line has no message, keeps the summary; with 1500-char cwd, project and
    // transcript as well → no summary and no title either; a 5000-char cwd → nil
@Test func theLineRoundTrips()                       // JSONDecoder().decode(AgentMessage.self, line minus "\n") == message
```

- [ ] **Step 2: Run them to make sure they fail.** `make test FILTER=AgentTrimTests`. Expected: compile failure.
- [ ] **Step 3: Implement.** `message` parses with `JSONSerialization`, reads the fields in the spec's table, cuts every string with `cut` except `cwd`, `project` and `transcript` (paths stay whole), and sets `summary` from `summary(tool:input:)` when `tool_input` is an object. `line` encodes with `JSONEncoder` (`.sortedKeys`, `.withoutEscapingSlashes`), appends `\n`, and drops fields in the order above while over `maxLine`.
- [ ] **Step 4: Run the tests to see them pass.** `make test FILTER=AgentTrimTests`. Expected: all pass.
- [ ] **Step 5: Commit** `Package.swift`, `Sources/AgentWire`, `Tests/AgentWireTests`: "trim a hook to one line for ledge: the session, the event, a summary of the tool call, its stamp and its parents".

### Task 3: The helper, its socket and its process facts

**Files:**
- Create: `Sources/AgentWire/AgentSocket.swift`, `Sources/AgentWire/AgentProcess.swift`
- Create: `Sources/LedgeAgentHook/main.swift`
- Modify: `Package.swift`: `.executableTarget(name: "LedgeAgentHook", dependencies: ["AgentWire"])`; `AgentWireTests` also depends on `"LedgeAgentHook"` (so `swift test` builds it).
- Modify: `Makefile`: in `bundle`, `cp "$(BUILDDIR)/LedgeAgentHook" "$(APPDIR)/Contents/MacOS/ledge-agent-hook"`; in `sign`, sign `$(APPDIR)/Contents/MacOS/ledge-agent-hook` with the same identity before the app.
- Test: `Tests/AgentWireTests/AgentSocketTests.swift`

**Interfaces:**
- Consumes: `AgentTrim`, `AgentMessage` (Task 2).
- Produces:

```swift
public enum AgentSocket {
    /// `$HOME` when set (Claude Code runs hooks with the user's), else `NSHomeDirectory()`.
    public static var home: URL { get }
    /// ~/Library/Application Support/Ledge
    public static func supportDirectory(home: URL = AgentSocket.home) -> URL
    public static func socketURL(home: URL = AgentSocket.home) -> URL   // supportDirectory/agents.sock
    public static func helperURL(home: URL = AgentSocket.home) -> URL   // supportDirectory/ledge-agent-hook
    /// Connects, writes all of `data`, closes. False on any failure. Never blocks past `timeout`.
    public static func send(_ data: Data, to socket: URL, timeout: TimeInterval) -> Bool
}

public enum AgentProcess {
    /// The process's start time from `sysctl(KERN_PROC_PID)` (`kp_proc.p_starttime`), in microseconds.
    public static func startTime(of pid: Int32) -> Int64?
    /// `pid`'s parent, its parent, …, nearest first; stops before a pid ≤ 1, at most `limit` entries.
    public static func parentChain(from pid: Int32, limit: Int = 12) -> [Int32]
    /// `proc_name`, e.g. "claude".
    public static func name(of pid: Int32) -> String?
    /// The process's argv from `sysctl(KERN_PROCARGS2)`; nil when unreadable.
    public static func arguments(of pid: Int32) -> [String]?
}
```

`main.swift` (the whole helper):

```swift
import AgentWire
import Foundation

// A Claude Code hook (2026-10-23): stdin to Ledge's socket, one line, and
// exit 0 whatever happens — Claude must never see an error from Ledge.
let input = FileHandle.standardInput.readDataToEndOfFile()
let me = getpid()
let stamp = AgentProcess.startTime(of: me) ?? Int64(Date().timeIntervalSince1970 * 1_000_000)
if let message = AgentTrim.message(hookJSON: input, environment: ProcessInfo.processInfo.environment,
                                   stamp: stamp, pids: AgentProcess.parentChain(from: me)),
   let line = AgentTrim.line(message) {
    _ = AgentSocket.send(line, to: AgentSocket.socketURL(), timeout: 0.5)
}
exit(0)
```

- [ ] **Step 1: Write the failing tests.** A tiny test listener: `socket(AF_UNIX, SOCK_STREAM)`, bind, listen, accept on a background thread, read to EOF. Paths must stay short (`sun_path` holds 104 bytes), so each test makes a home at `/tmp/lh-<8 hex>` (removed afterwards) and binds `AgentSocket.socketURL(home:)` inside it. Locate the helper as `Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") }?.bundleURL.deletingLastPathComponent().appending(path: "LedgeAgentHook")`, falling back to `<package root from #filePath>/.build/debug/LedgeAgentHook`; run it with `Process`, its environment's `HOME` set to the test's home.

```swift
@Test func sendDeliversTheBytes()                     // send(Data("hi\n".utf8), to: path, timeout: 0.5) == true; listener read "hi\n"
@Test func sendToNothingFailsFast()                   // no file at path → false, in under 0.6 s
@Test func ourOwnStartTimeAndParentsAreReadable()     // startTime(of: getpid()) within 1 h of now; parentChain(from: getpid()).first == getppid()
@Test func argumentsAreReadable()                     // arguments(of: getpid())?.first ends with the test runner's name
@Test func theHelperForwardsAHook()
    // run the helper with a PreToolUse hook JSON on stdin → the listener gets one line decoding to
    // AgentMessage(event: "PreToolUse", session: "s1", …) whose pids.first == the test process's pid; exit status 0
@Test func withNoListenerTheHelperExitsZeroQuickly()  // no socket → exit status 0 within 1 s
@Test func aHugeToolInputIsDrainedAndTrimmed()        // a Write hook whose content is 1 MB → exit 0, one line ≤ 4096 bytes, summary "x.swift"
@Test func garbageOnStdinExitsZeroAndSendsNothing()   // "not json" → exit 0, the listener gets nothing
```

- [ ] **Step 2: Run them to make sure they fail.** `make test FILTER=AgentSocketTests`. Expected: compile failure.
- [ ] **Step 3: Implement.** `send`: `socket(AF_UNIX, SOCK_STREAM, 0)`, `SO_NOSIGPIPE`, `O_NONBLOCK`; `connect`; on `EINPROGRESS` wait with `poll` for the rest of `timeout`; write in a loop with `poll` for writability; close. Paths longer than `sun_path` → false. `startTime`: `kinfo_proc` via `sysctl([CTL_KERN, KERN_PROC, KERN_PROC_PID, pid])`, `tv_sec * 1_000_000 + tv_usec`. `parentChain`: the same call's `kp_eproc.e_ppid`, walking up. `arguments`: `KERN_PROCARGS2`, skip the `argc` int and the executable path and its NUL padding, then read `argc` NUL-separated strings. `name`: `proc_name`. Write `main.swift` as above, with a comment recording the chain shape seen in Task 1. Update the Makefile.
- [ ] **Step 4: Run the tests to see them pass.** `make test FILTER=AgentSocketTests`, then `make bundle` and check `dist/Ledge.app/Contents/MacOS/ledge-agent-hook` exists, then `make sign` and `codesign --verify --strict dist/Ledge.app`. Expected: all pass, the helper is in the bundle and signed.
- [ ] **Step 5: Commit**: "add the agent hook helper: read the hook, send one line to ledge's socket within half a second, and always exit zero".

### Task 4: `AgentService`: the settings file

**Files:**
- Modify: `Package.swift`: `.target(name: "AgentService", dependencies: ["AgentWire", "CallService"])`, `.testTarget(name: "AgentServiceTests", dependencies: ["AgentService", "AgentWire"])`, and `"AgentService"` in Ledge's dependencies.
- Create: `Sources/AgentService/OrderedJSON.swift`, `Sources/AgentService/AgentHooks.swift`
- Test: `Tests/AgentServiceTests/OrderedJSONTests.swift`, `Tests/AgentServiceTests/AgentHooksTests.swift`

**Interfaces:**
- Produces:

```swift
/// JSON that keeps its keys' order and its numbers' text, written the way
/// Claude Code writes settings.json (JSON.stringify(value, null, 2)).
public indirect enum OrderedJSON: Sendable, Equatable {
    case object([(key: String, value: OrderedJSON)])   // Equatable by hand: same keys in the same order
    case array([OrderedJSON])
    case string(String)
    case number(String)        // the literal as written
    case bool(Bool)
    case null
    public static func parse(_ data: Data) throws -> OrderedJSON
    /// Two-space indent, `"key": value`, `[]` and `{}` when empty, a trailing "\n".
    public func written() -> Data
    public subscript(key: String) -> OrderedJSON? { get }
}

public enum AgentHooks {
    public static let events: [String]            // the ten, in the order above
    public static let matcherEvents: Set<String>  // the four tool events
    public static let marker = "Ledge/ledge-agent-hook"
    public static func command(helper: String) -> String
    public static func installing(into settings: OrderedJSON, helper: String) -> OrderedJSON
    public static func removing(from settings: OrderedJSON) -> OrderedJSON
    /// Ledge's entries are there for all ten events and point at `helper`.
    public static func isInstalled(in settings: OrderedJSON, helper: String) -> Bool
}

public struct AgentSettingsFile: Sendable {
    public enum Problem: Error, Equatable { case notAnObject; case unreadable(String) }
    public let url: URL                                   // ~/.claude/settings.json in the app
    public init(url: URL)
    public func install(helper: String) throws(Problem)   // read (missing: {}), backup once, change, write atomically if changed
    public func uninstall() throws(Problem)               // missing file: nothing to do
    public func isInstalled(helper: String) -> Bool
}
```

- [ ] **Step 1: Write the failing tests:**

```swift
// OrderedJSONTests
@Test func aClaudeWrittenFileRoundTripsByteForByte()
    // a fixture shaped like this Mac's settings.json (model, hooks with matchers and timeouts, statusLine,
    // enabledPlugins, a number 10, true/false, a URL with slashes, "é", an empty object and array)
    // written as JSON.stringify(…, null, 2) + "\n" → parse(x).written() == x
@Test func keysKeepTheirOrder()                       // {"b":1,"a":2} → keys ["b","a"]
@Test func numbersKeepTheirText()                     // 1.0, 1e3, -0, 12345678901234567890 written back as given
@Test func stringsAreEscapedAsJavaScriptDoes()        // quote, backslash, \n, \t, U+0001 → \", \\, \n, \t, \u0001; "/" and "é" left as they are
@Test func badJSONThrows()                            // "{", "{'a':1}", trailing garbage

// AgentHooksTests
@Test func everyHookIsAsyncAndGuarded()
    // installing into {} → hooks has the ten events; each has one group, "matcher":"*" only on the four;
    // the hook is {"type":"command","command":command(helper:),"async":true,"timeout":5};
    // command(helper: "/H/L/ledge-agent-hook") == "[ -x \"/H/L/ledge-agent-hook\" ] && \"/H/L/ledge-agent-hook\" || true"
@Test func othersEntriesAreKept()
    // a fixture with RTK's PreToolUse "Bash" group, Orca's "*" group with timeout 10, Superset's "Artifact" group,
    // and their Stop groups → installing appends Ledge's group after theirs; theirs are equal, in the same order
@Test func installingTwiceChangesNothing()           // installing(installing(x)) == installing(x)
@Test func anOldHelperPathIsReplaced()               // installed with "/old/Ledge/ledge-agent-hook", installing with the new path → one Ledge group per event, the new path
@Test func removingTakesOnlyLedgesAndEmptiedGroups()
    // a group holding Ledge's hook and another tool's → only Ledge's hook goes; an event left empty goes;
    // "hooks" left empty goes; other top-level keys stay in order
@Test func isInstalledNeedsAllTenAtThisPath()
@Test func aMissingFileIsCreatedWithJustTheHooks()   // AgentSettingsFile on a temp URL → file exists, isInstalled
@Test func theFirstWriteKeepsABackupOnce()           // install over an existing file → settings.json.ledge-backup == original; a second install leaves the backup alone
@Test func notAnObjectIsLeftAlone()                  // "[]" in the file → install throws .notAnObject, file unchanged
@Test func anUnchangedFileIsNotRewritten()           // install twice → the second does not change the modification date
```

- [ ] **Step 2: Run them to make sure they fail.** `make test FILTER="OrderedJSONTests|AgentHooksTests"`. Expected: compile failure.
- [ ] **Step 3: Implement.** A small recursive-descent parser over UTF-8 bytes (whitespace, objects, arrays, strings with escapes and surrogate pairs, number lexemes per the JSON grammar, `true`/`false`/`null`, nothing after the value but whitespace). The writer mirrors `JSON.stringify(v, null, 2)`. `installing`: remove Ledge's hooks first (`removing`), then append one group per event. `AgentSettingsFile.install` writes with `Data.write(to:options: .atomic)` only when the bytes differ, after creating `~/.claude` if missing.
- [ ] **Step 4: Run the tests to see them pass.** `make test FILTER="OrderedJSONTests|AgentHooksTests"`. Expected: all pass.
- [ ] **Step 5: Commit**: "write ledge's agent hooks into claude's settings beside everyone else's, keeping the file's order and layout, and take only ours out again".

### Task 5: `AgentSessions`: the state machine and the interrupt line

**Files:**
- Create: `Sources/AgentService/AgentSessions.swift`, `Sources/AgentService/AgentTranscript.swift`
- Test: `Tests/AgentServiceTests/AgentSessionsTests.swift`, `Tests/AgentServiceTests/AgentTranscriptTests.swift`

**Interfaces:**
- Consumes: `AgentMessage` (Task 2); `CallAppInfo` (CallService).
- Produces:

```swift
/// What Ledge learned about a message's process, resolved outside the machine.
public struct AgentFacts: Sendable, Equatable {
    public let claudePID: Int32?
    public let isHeadless: Bool
    public let host: CallAppInfo?
    public init(claudePID: Int32?, isHeadless: Bool, host: CallAppInfo?)
}

public struct AgentSession: Sendable, Equatable, Identifiable {
    public enum Waiting: Sendable, Equatable {
        case permission(String)      // "Bash: make test", or "Bash"
        case question(String?)
        case plan
        case input(String?)
    }
    public enum State: Sendable, Equatable {
        case idle, working, waiting(Waiting), finished(took: TimeInterval), failed(reason: String)
    }
    public let id: String
    public var name: String
    public var project: String
    public var transcript: String?
    public var host: CallAppInfo?
    public var claudePID: Int32?
    public var state: State
    public var stateSince: Date
    public var turnStart: Date?
    public var lastStamp: Int64
    public var lastEvent: Date
}

public enum AgentMoment: Sendable, Equatable {
    case waiting(AgentSession), finished(AgentSession), failed(AgentSession)
}

public struct AgentSessions: Sendable, Equatable {
    public static let forgetAfter: TimeInterval = 3600
    public init()
    /// Most recently active first.
    public private(set) var sessions: [AgentSession]
    public mutating func apply(_ message: AgentMessage, facts: AgentFacts, now: Date) -> AgentMoment?
    public mutating func interrupt(session id: String, now: Date)
    public mutating func processExited(_ pid: Int32)
    public mutating func forget(now: Date)
    /// Sessions working or waiting, by id, with their transcript paths.
    public var transcriptsToWatch: [String: String] { get }
    public var claudePIDs: Set<Int32> { get }
}

public enum AgentTranscript {
    public static let markers: Set<String> = ["[Request interrupted by user]", "[Request interrupted by user for tool use]"]
    /// A `user` line whose content is exactly a marker, or holds a `text` item that is exactly one.
    public static func isInterrupt(_ line: Data) -> Bool
}
```

- [ ] **Step 1: Write the failing tests.** `t0 = Date(timeIntervalSince1970: 1_000)`; a helper `msg(_ event: String, stamp: Int64, …)`; `facts = AgentFacts(claudePID: 42, isHeadless: false, host: vscode)`.

```swift
@Test func aPromptStartsATurn()                      // UserPromptSubmit at t0 → working, turnStart t0, no moment
@Test func aSessionFirstSeenMidTurnWorksFromNow()     // first event PreToolUse at t0+5 → working, turnStart t0+5, name "ledge" (project /p/ledge)
@Test func aPermissionRequestWaitsWithWhatItWants()   // PermissionRequest tool Bash summary "make test" → .waiting(.permission("Bash: make test")), moment .waiting
@Test func askUserQuestionAndExitPlanModeWait()       // PreToolUse AskUserQuestion summary "Which?" → .question("Which?"); ExitPlanMode → .plan; each a moment
@Test func aNotificationWaitsOnlyIfNotAlready()       // Notification permission_prompt message "Claude needs your permission" → .input(that), moment; again → no moment
@Test func idleAndOtherNotificationsDoNothing()       // idle_prompt, auth_success → state unchanged, no moment
@Test func answeringGoesBackToWorkingQuietly()        // waiting, then PostToolUse → working, no moment, turnStart unchanged
@Test func aSecondPromptIsANewMoment()                // waiting → PostToolUse → PermissionRequest → moment again
@Test func stopFinishesWithTheTurnsLength()           // UserPromptSubmit t0, Stop t0+200 → .finished(took: 200), moment .finished
@Test func stopFailureFailsWithItsReason()            // StopFailure error "rate_limit" → .failed(reason: "rate_limit"), moment .failed
@Test func aLatePreToolUseDoesNotHideThePrompt()      // PermissionRequest stamp 20 applied, then PreToolUse stamp 10 → still waiting
@Test func anEqualStampIsApplied()                    // two events with the same stamp both apply, in arrival order
@Test func sessionEndRemovesIt()
@Test func theClaudeProcessExitingRemovesIt()         // processExited(42) → gone
@Test func anInterruptIdlesWithoutAMoment()           // working → interrupt → idle, turnStart nil
@Test func headlessSessionsAreIgnored()               // facts.isHeadless → nil, sessions empty
@Test func nameClashesGetANumber()                    // two sessions in /p/ledge → "ledge", "ledge 2"; the first ends; a third → "ledge" again
@Test func aTitleNamesTheSession()                    // SessionStart with title "Agent island" → name "Agent island"
@Test func forgettingDropsQuietSessionsAfterAnHour()  // finished at t0 → still there at t0+3599, gone at t0+3600; working never forgotten
@Test func theListIsMostRecentlyActiveFirst()
@Test func transcriptsAreWatchedOnlyWhileWorkingOrWaiting()

// AgentTranscriptTests
@Test func onlyAnExactUserTextIsAnInterrupt()
    // {"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}} → true
    // the same with "… for tool use]" → true; content as a plain string equal to a marker → true
    // a tool_result whose content contains the marker → false; an assistant text containing it → false
    // "[Request interrupted by user] and more" → false; not JSON → false
```

- [ ] **Step 2: Run them to make sure they fail.** `make test FILTER="AgentSessionsTests|AgentTranscriptTests"`. Expected: compile failure.
- [ ] **Step 3: Implement** the table in the spec. A new session's name is its title, else the last path component of `project`; a clash with a live session's name adds " 2", " 3" (the lowest free). Waiting from a tool event uses `tool + ": " + summary`, or the tool alone. `UserPromptSubmit` always starts a new turn. Leaving any state for working keeps `turnStart` if set, else sets it to `now`. `finished`, `failed` and idle clear `turnStart`.
- [ ] **Step 4: Run the tests to see them pass.** Same filter. Expected: all pass.
- [ ] **Step 5: Commit**: "track each claude session: working, waiting with what it wants, done with its length, failed with its reason, idle on an esc, in stamp order".

### Task 6: `AgentNotice` and the card's rows

**Files:**
- Create: `Sources/AgentService/AgentNotice.swift`, `Sources/AgentService/AgentPanelRows.swift`
- Test: `Tests/AgentServiceTests/AgentNoticeTests.swift`

**Interfaces:**
- Consumes: `AgentSession`, `AgentMoment` (Task 5).
- Produces:

```swift
public struct AgentBlip: Sendable, Equatable {
    public let sessionID: String
    public let title: String          // "Waiting · ledge", "Done · ledge", "Failed · ledge"
    public let word: String
    public let tintName: String       // "yellow", "green", "red"
    public let caption: String        // "ledge · Bash: make test"
    public let ttl: TimeInterval      // 8 waiting, 3 otherwise
}

public enum AgentNotice {
    public static let orange = (red: 0.851, green: 0.467, blue: 0.341)
    public static let waitingTintName = "yellow"
    public static func blip(for moment: AgentMoment) -> AgentBlip
    public static func detail(_ waiting: AgentSession.Waiting) -> String   // "Bash: make test", question or "Asks a question", "Plan ready", message or "Needs you"
    public static func reason(_ error: String) -> String
    public static func duration(_ seconds: TimeInterval) -> String
}

public struct AgentRow: Sendable, Equatable, Identifiable {
    public enum Mark: Sendable, Equatable {
        case waiting(String), working(since: Date), done(at: Date), failed(String), idle
    }
    public let id: String
    public let name: String
    public let host: CallAppInfo?
    public let mark: Mark
}

public enum AgentPanelRows {
    public static func make(_ sessions: [AgentSession]) -> [AgentRow]   // the sessions' order
}
```

- [ ] **Step 1: Write the failing tests:**

```swift
@Test func eachWaitingHasItsWord()       // permission → "Allow?"; question → "Question"; plan → "Plan"; input → "Waiting"; all yellow, ttl 8
@Test func doneSaysHowLong()             // finished(took: 200) → word "Done", green, caption "ledge · 3m 20s", ttl 3
@Test func failedSaysWhy()               // failed("rate_limit") → "Failed", red, "ledge · Rate limited"; "overloaded" → "Overloaded";
                                         // "authentication_failed" → "Signed out"; "billing_error" → "Billing"; "server_error", "x" → "API error"
@Test func durationsReadAsSpoken()       // 45 → "45s"; 200 → "3m 20s"; 180 → "3m"; 3840 → "1h 4m"; 3600 → "1h"
@Test func theWaitingDetailHasFallbacks()// question(nil) → "Asks a question"; plan → "Plan ready"; input(nil) → "Needs you"
@Test func rowsFollowTheSessions()       // working since t0, waiting, finished at t1, failed, idle → marks in order, same ids
```

- [ ] **Step 2: Run them to make sure they fail.** `make test FILTER=AgentNoticeTests`. Expected: compile failure.
- [ ] **Step 3: Implement.** A finished row's `done(at:)` is its `stateSince`; a working row's `since` is `turnStart ?? stateSince`.
- [ ] **Step 4: Run the tests to see them pass.** Expected: all pass.
- [ ] **Step 5: Commit**: "say each agent moment: allow, question, plan, done with its length, failed with why, and the card's rows".

### Task 7: The listener, the watchers, the host and `AgentMonitor`

**Files:**
- Create: `Sources/AgentService/AgentListener.swift`: the socket server (`@MainActor`; `bind` after removing a stale file, `chmod 0600`, `listen`, a `DispatchSourceRead` on the listening fd; per connection a read source that collects up to 8 KB or EOF or a newline, then calls back on the main queue and closes).
- Create: `Sources/AgentService/AgentWatchers.swift`: `DispatchSource.makeProcessSource(.exit)` per `claude` PID (and an immediate `kill(pid, 0)` check); per watched transcript an `O_EVTONLY` file source on `[.extend, .write]`, reading from the offset at which the watch began, splitting lines, keeping a partial tail.
- Create: `Sources/AgentService/AgentHost.swift`: facts from `pids`; focus; "is the user looking".
- Create: `Sources/AgentService/AgentMonitor.swift`
- Test: `Tests/AgentServiceTests/AgentMonitorTests.swift`

**Interfaces:**
- Consumes: Tasks 2–6; `CallApp.resolve(_:ownPID:lookup:)`, `ProcessLookup.live` (CallService); `AgentProcess` (Task 3).
- Produces:

```swift
@MainActor public struct AgentHostLookup {
    public var name: (Int32) -> String?
    public var arguments: (Int32) -> [String]?
    public var app: (Int32) -> CallAppInfo?            // CallApp.resolve with ProcessLookup.live
    public static let live: AgentHostLookup
    /// The first pid named "claude" (else pids[1], else pids[0]); headless when its arguments hold "-p" or "--print".
    public func facts(for pids: [Int32]) -> AgentFacts
}

public struct AgentPaths: Sendable {
    public let settingsFile: URL      // ~/.claude/settings.json
    public let socket: URL            // AgentSocket.socketURL()
    public let helper: URL            // AgentSocket.helperURL()
    public let helperSource: URL?     // Bundle.main.bundleURL/Contents/MacOS/ledge-agent-hook, if it exists
    public static var live: AgentPaths { get }
}

@MainActor public final class AgentMonitor {
    public enum Status: Sendable, Equatable { case off, ready(lastHeard: Date?), problem(String) }
    public private(set) var status: Status
    public private(set) var sessions: AgentSessions
    public var onMoment: ((AgentMoment) -> Void)?
    public var onChange: (() -> Void)?
    public init(paths: AgentPaths = .live, host: AgentHostLookup = .live, listens: Bool = true)
    /// Copy the helper, install the hooks, listen. Idempotent; also the Repair button.
    public func enable()
    /// Stop listening and remove Ledge's hooks.
    public func disable()
    /// Stop listening, keep the hooks (Ledge quitting).
    public func suspend()
    /// One line from the socket (also the tests' and the probe's way in).
    public func receive(_ line: Data, now: Date = Date())
    /// The probe's way in: a message with made-up facts.
    public func receive(_ message: AgentMessage, facts: AgentFacts, now: Date = Date())
    public func tick(now: Date)                      // forget
    public func focus(sessionID: String)
    public func isLooking(at session: AgentSession) -> Bool
}
```

- [ ] **Step 1: Write the failing tests** (`listens: false`, temporary paths, a fake `AgentHostLookup`):

```swift
@MainActor @Test func enablingCopiesTheHelperAndInstallsTheHooks()
    // helperSource a temp file with mode 0755 → helper copied (executable), settings file isInstalled, status .ready(lastHeard: nil)
@MainActor @Test func aMissingHelperIsAProblem()       // helperSource nil → status .problem("The helper is missing from Ledge.app")
@MainActor @Test func anUnreadableSettingsFileIsAProblem()  // "[]" in it → .problem starting "Can't read settings.json"
@MainActor @Test func disablingRemovesTheHooks()       // enable, disable → not installed, status .off
@MainActor @Test func suspendingKeepsTheHooks()        // enable, suspend → still installed
@MainActor @Test func aLineUpdatesTheSessionsAndSaysTheMoment()
    // receive(line of PermissionRequest) → sessions has one waiting, onMoment called once, status .ready(lastHeard: now)
@MainActor @Test func headlessLinesAreIgnored()        // fake arguments ["claude", "-p", "x"] → no session
@MainActor @Test func anInterruptLineInTheTranscriptIdlesTheSession()
    // a temp transcript file; UserPromptSubmit with transcript: path → working; append the interrupt line
    // → after the main queue runs (await a short Task.sleep loop up to 2 s), the session is idle
@MainActor @Test func aTranscriptLineThatIsNotAnInterruptChangesNothing()
@MainActor @Test func theHostIsResolvedFromThePids()   // pids [10, 42, 7] with name(42) == "claude", app(42) == vscode → host vscode, claudePID 42
```

  The listener gets its own round-trip test: `AgentListener` on a short temp path, `AgentSocket.send` of a line, the callback gets it; a stale file at the path is replaced; the socket file's mode is 0600.

- [ ] **Step 2: Run them to make sure they fail.** `make test FILTER="AgentMonitorTests|AgentListenerTests"`. Expected: compile failure.
- [ ] **Step 3: Implement.**
  - `enable`: create the support directory; copy `helperSource` over `helper` (remove first), `chmod 0755`; `AgentSettingsFile(url: settingsFile).install(helper: helper.path)`; start the listener when `listens`. Errors become `.problem` with the copy in the spec ("Can't read settings.json: …", "The helper is missing from Ledge.app").
  - `receive(line)`: decode `AgentMessage` (drop `v != 1`), `host.facts(for: message.pids)`, apply, then sync the watchers to `transcriptsToWatch` and `claudePIDs`, set `.ready(lastHeard: now)`, call `onMoment` for a moment and `onChange`.
  - Watchers call `sessions.interrupt` / `processExited`, then `onChange`.
  - `focus`: VS Code (`com.microsoft.VSCode`, `com.microsoft.VSCodeInsiders`): `NSWorkspace.shared.open([URL(fileURLWithPath: project)], withApplicationAt: appURL, configuration:)` with `activates = true`. Ghostty (`com.mitchellh.ghostty`): activate, then with `AXIsProcessTrusted()` raise the first `kAXWindowsAttribute` window whose `kAXTitleAttribute` contains the project folder's name (`kAXRaiseAction`, then set `kAXMainAttribute`). Else activate the host by pid.
  - `isLooking`: the frontmost app's pid is the host's, `AXIsProcessTrusted()`, and the focused window's title contains the project folder's name.
  - Log only event names and counts (`Logger(subsystem: "com.dedemahendra.ledge", category: "agents")`).
- [ ] **Step 4: Run the tests to see them pass.** Expected: all pass.
- [ ] **Step 5: Commit**: "listen for agent hooks, watch each claude process and its transcript for an esc, find its window, and set the hooks up and take them down".

### Task 8: The three kinds

**Files:**
- Modify: `Sources/ActivityKit/ActivityKind.swift`: `agent` (39, TTL 8), `agentWaiting` (25, sticky), `agentRun` (8, sticky), each with a doc comment in the file's style.
- Test: `Tests/ActivityKitTests/ActivityQueueTests.swift`

- [ ] **Step 1: Write the failing test:**

```swift
@Test func agentsSitWhereTheSpecPutsThem() {
    #expect(ActivityKind.agent.priority == 39 && ActivityKind.agent.defaultTTL == 8)
    #expect(ActivityKind.agent > .github && ActivityKind.agent < .notification)
    #expect(ActivityKind.agentWaiting.priority == 25 && ActivityKind.agentWaiting.defaultTTL == nil)
    #expect(ActivityKind.agentWaiting < .call && ActivityKind.agentWaiting > .timer && ActivityKind.agentWaiting > .media)
    #expect(ActivityKind.agentRun.priority == 8 && ActivityKind.agentRun.defaultTTL == nil)
    #expect(ActivityKind.agentRun < .media && ActivityKind.agentRun > .charging)
}
```

- [ ] **Step 2: Run it to make sure it fails.** `make test FILTER=agentsSitWhereTheSpecPutsThem`. Expected: compile failure.
- [ ] **Step 3: Add the cases.** Fix every exhaustive `switch` over `ActivityKind` the compiler flags.
- [ ] **Step 4: Run** `make test FILTER=ActivityQueueTests`. Expected: all pass, including `everyKindHasADistinctPriority`.
- [ ] **Step 5: Commit**: "add the agent kinds: a blip over github's, waiting over timers and under a call, working under music".

### Task 9: NotchKit model: ids, the card's data, the panel

**Files:**
- Create: `Sources/NotchKit/AgentPanel.swift`
- Modify: `Sources/NotchKit/NotchController.swift`, `Sources/NotchKit/NotchPresenter.swift`
- Test: `Tests/NotchKitTests/NotchControllerTests.swift`

**Interfaces:**
- Produces:

```swift
public struct AgentPanelData: Sendable, Equatable {
    public struct Row: Sendable, Equatable, Identifiable {
        public enum Mark: Sendable, Equatable {
            case waiting(String), working(since: Date), done(at: Date), failed(String), idle
        }
        public let id: String
        public let name: String
        public let icon: Data?       // the host app's icon as PNG
        public let mark: Mark
        public let url: URL          // ledge://agent/<session id, percent-encoded>
        public init(id: String, name: String, icon: Data?, mark: Mark, url: URL)
    }
    public let rows: [Row]
    public init(rows: [Row])
}
```

  On `NotchController`: `agentActivityID = "agent"`, `agentWaitingActivityID = "agent-waiting"`, `agentRunActivityID = "agent-run"`; `isAgentLeading` (the blip); a private `isAnyAgentLeading` (any of the three); `Panel.agents`; `agentPanel` and `setAgentPanel(_:)` (drops to `.media` when the data goes, like `setGitHubPanel`). `hasCaption` includes `isAgentLeading`. `availablePanels` appends `.agents` after `.github`. `setHovered(true)` picks `.agents` when `isAnyAgentLeading && agentPanel != nil && !isPinnedOpen`. `recomputeState` expands for `panel == .agents` with data. The empty peek's swipe opens GitHub when it has data, else Agents. On `NotchPresenter`: `setAgentPanel(_:)`, forwarding and resyncing like `setGitHubPanel`.

- [ ] **Step 1: Write the failing tests:**

```swift
@MainActor @Test func hoveringAnAgentItemOpensTheAgentsCard()      // each of the three ids leading + data → .agents, .expanded
@MainActor @Test func theAgentsCardGoesWithItsData()                // setAgentPanel(nil) → .media, .activity
@MainActor @Test func theAgentsCardComesAfterGitHub()               // github and agent data → availablePanels ends [.github, .agents]
@MainActor @Test func anAgentBlipCarriesItsCaption()                // agent blip leading, setCaption("ledge · 3m") → captionText "ledge · 3m"
@MainActor @Test func theWaitingItemCarriesNoCaption()              // agent-waiting leading → hasCaption false
@MainActor @Test func theEmptyPeeksSwipeFallsBackToAgents()         // no github data, agent data, peek → swipe opens .agents
```

- [ ] **Step 2: Run them to make sure they fail.** Expected: compile failure.
- [ ] **Step 3: Implement** the interface above.
- [ ] **Step 4: Run** `make test FILTER=NotchControllerTests`. Expected: all pass.
- [ ] **Step 5: Commit**: "give the island its agents: the ids, the card's rows, the agents panel on hover and after github's".

### Task 10: NotchKit views: the asterisk, the ears and the card

**Files:**
- Create: `Sources/NotchKit/AgentPanelView.swift` (the card and `AgentGlyph`)
- Modify: `Sources/NotchKit/NotchRootView.swift`: a leading-ear branch for the three agent ids, before the product-render branch; the trailing ear's ticking and coloured-word sets; a `detailRow` branch for `.agents`.

**Interfaces:**
- Consumes: Task 9.
- Produces: `struct AgentGlyph: View { let color: Color; let turning: Bool; let count: Int?; let reduceMotion: Bool }`; `struct AgentPanelView: View { let data: AgentPanelData; let contentColor: Color; let reduceMotion: Bool; let emit: (NotchIntent) -> Void }`.

- [ ] **Step 1: `AgentGlyph`.** `Image(systemName: "asterisk")` at 13 pt semibold in `color`, inside a 14 × 14 frame. While `turning && !reduceMotion`, a `TimelineView(.animation)` turns it once per 2.4 s (like `GitHubRunRing`). When `count > 1`, the count at 8 pt bold, monospaced digits, at its bottom trailing corner.
- [ ] **Step 2: Leading ear.** For `agentActivityID` and `agentWaitingActivityID`: `AgentGlyph(color: orange, turning: false, count: activity.badge)`; for `agentRunActivityID`: `turning: true`. `orange` is `tintColor(for: .color(red: 0.851, green: 0.467, blue: 0.341)) ?? contentColor`, so the render test hook still gets one content colour.
- [ ] **Step 3: Trailing ear.** Add `agentRunActivityID` to `isTicking`; add `agentActivityID` and `agentWaitingActivityID` beside `isGitHub`, so their word takes the record's tint.
- [ ] **Step 4: `AgentPanelView`.** Rows in a column like `GitHubPanelView`'s list (same row height, `ListRowButtonStyle`, the same `reveal` stagger): the host icon at 16 pt (or the asterisk), the name in 13 pt semibold; at the right, by mark: amber detail text (`systemYellow`), an orange clock from `TimelineView(.periodic(from: .now, by: 1))` and `GitHubPanelView.clock(_:)` (as the call card does; NotchKit does not see TimerService), green "Done 2m ago" (`RelativeDateTimeFormatter` with `.abbreviated`, "Done just now" under a minute), red failure reason, dim "Idle". A row's button emits `.open(row.url)`. At most 6 rows; "N more" in dim text below when there are more. Wire into `detailRow` with `.id("agents")` and `panelTransition`.
- [ ] **Step 5: Check the renders headlessly.** A temporary test (not committed), in the style of the call task's: render `NotchRootView` at `NotchMetrics.canvasSize`, scale 4, for (a) a waiting blip "Allow?" with its caption, (b) the waiting item with a badge of 2 and "2 waiting", (c) the working item at "4:12" with a count of 3, (d) a done blip, (e) a failed blip, (f) the card with five rows of each mark. Crop the top with ffmpeg and look. Expected: the asterisk in orange left; amber, orange, green and red words right; the card's rows readable at the island's width. Delete the temporary test.
- [ ] **Step 6: Run the whole suite.** `make test`. Expected: all pass, `NotchRenderTests` included (the two `HUDServiceTests` brightness tests fail on this Mac with no built-in display, as on `main`).
- [ ] **Step 7: Commit**: "draw the agents: an orange asterisk that turns while one works, amber, green and red words, the waiting count and the working clock, and the agents card".

### Task 11: Settings: the keys, the previews and the Agents pane

**Files:**
- Modify: `Sources/LedgeSettings/AppSettings.swift`: keys and properties `agentsEnabled` (false), `agentWaiting`, `agentFinished`, `agentWorking`, `agentFailed` (true), in the file's style.
- Modify: `Sources/SettingsKit/PreviewScene.swift`: `agentWaiting` "Waiting for you", `agentWorking` "Working", `agentFinished` "Finished its turn", `agentFailed` "Failed", each `isOn` its key.
- Modify: `Sources/SettingsKit/PreviewStage.swift`: stage each with `AgentNotice` samples (a session "ledge" with `.permission("Bash: make test")`, a working item "4:12", done after 200 s, failed `rate_limit`), captioned as samples (`"no session"`).
- Modify: `Package.swift`: `SettingsKit` and `SettingsKitTests` also depend on `"AgentService"`.
- Create: `Sources/Ledge/AgentSettings.swift`
- Modify: `Sources/Ledge/SettingsWindow.swift`: `SettingsSection.agents` after `.github`: "Agents", `asterisk`, Claude orange.
- Test: `Tests/LedgeSettingsTests/AppSettingsTests.swift`, `Tests/SettingsKitTests/PreviewStageTests.swift`

**Interfaces:**
- Consumes: `AgentMonitor.Status` through `AppModel` (Task 12 adds `agentsStatus`, `enableAgents()`, `disableAgents()`, `repairAgents()`); write the pane against those names.

- [ ] **Step 1: Write the failing tests:**

```swift
@MainActor @Test func agentsAreOffButEveryMomentIsOnByDefault()
    // fresh suite → agentsEnabled false; agentWaiting, agentFinished, agentWorking, agentFailed true
@MainActor @Test func agentSettingsAreSaved()        // set each, a new AppSettings on the suite reads them back
```

  `everySceneShowsSomethingAndIsCaptioned` covers the four scenes through `allCases`.
- [ ] **Step 2: Run them to make sure they fail.** `make test FILTER="AppSettingsTests|PreviewStageTests"`. Expected: compile failure.
- [ ] **Step 3: Implement** the keys, scenes and staging. Then `AgentSettings`, laid out like `GitHubSettings`:
  - the preview strip with the four scenes;
  - a section with `SettingsRow("Show Claude Code sessions", detail: "Adds Ledge's hooks to ~/.claude/settings.json. Switching off takes them out.", symbol: "asterisk", color: orange)` holding a toggle bound to `agentsEnabled`; while on, a status line under it from `model.agentsStatus` in a `TimelineView(.periodic(from: .now, by: 2))`: "Hooks in ~/.claude/settings.json · Last heard from a session 2 min ago", or "· Nothing heard yet: start a new session", or the problem's text with a Repair button calling `model.repairAgents()`;
  - footer: "Each hook runs a small helper that tells Ledge what happened, over a socket only you can use. Nothing leaves this Mac, and Claude never waits for Ledge.";
  - a "Moments" section with four rows via the pane's `moment(…)` pattern: Waiting for you ("Permission prompts, questions and plans to approve.", `hand.raised.fill`, yellow), Working ("A turning asterisk and a clock while a session works. Under music.", `asterisk`, orange), Finished its turn ("Done, and how long it took.", `checkmark.circle.fill`, green), Failed ("A turn that ended on an error.", `exclamationmark.triangle.fill`, red); dimmed to 0.55 while off.
- [ ] **Step 4: Run the tests to see them pass.** Expected: all pass. The app target does not build until Task 12; that is expected.
- [ ] **Step 5: Commit**: "add agents to settings: the switch, its status, the four moments and their previews".

### Task 12: Wire it into `AppModel` and check it live

**Files:**
- Modify: `Sources/Ledge/AppModel.swift`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Owning it.** `private let agents = AgentMonitor()`. `agents.onMoment = { [weak self] in self?.showAgentMoment($0) }`, `agents.onChange = { [weak self] in self?.publishAgentPanel() }`. In `applySettings`: `agentsEnabled` → `agents.enable()` if its status is `.off`; else, if not `.off`, `agents.disable()`, remove the three kinds, clear the caption the agent blip put up, `presenter.setAgentPanel(nil)`. In `stop()`: `agents.suspend()`. For the pane: `var agentsStatus: AgentMonitor.Status { agents.status }`, `func repairAgents() { agents.enable() }`.
- [ ] **Step 2: Moments.** `showAgentMoment`: drop it when its setting is off (waiting → `agentWaiting`, finished → `agentFinished`, failed → `agentFailed`), when locked, or when `agents.isLooking(at:)` the session. Otherwise insert `ActivityRecord(id: NotchController.agentActivityID, kind: .agent, insertedAt: now, ttl: blip.ttl, title: blip.title, compactText: blip.word, symbolName: "asterisk", tint: .system(blip.tintName), url: agentURL(blip.sessionID))`, publish, and show its caption for `blip.ttl`, remembering it like `githubCaptionShown` so taking the blip away takes only its own caption.
- [ ] **Step 3: Sticky items, every tick** (`refreshAgents()` after `refreshGitHub()`): `agents.tick(now:)`; when locked or off, remove both sticky kinds. Waiting sessions (with `agentWaiting`): one record `agentWaitingActivityID`, kind `.agentWaiting`, `compactText` the name or "N waiting", `tint: .system(AgentNotice.waitingTintName)`, `badge` N when N > 1, `url` the longest-waiting session's. Working sessions (with `agentWorking`): `agentRunActivityID`, kind `.agentRun`, `compactText: TimerText.format(seconds: now - oldest turnStart)`, tint orange, `badge` N when N > 1, `url` the oldest's. Republish only when what is drawn changes (the `githubRunShown` pattern).
- [ ] **Step 4: The card.** `publishAgentPanel()`: nil when off, locked or no sessions; else rows from `AgentPanelRows.make`, each host's icon as PNG cached per bundle id (as `callIcons`), `url: agentURL(id)`. Also on lock changes from the tick.
- [ ] **Step 5: Clicks.** `agentURL(_ id: String) -> URL` builds `ledge://agent/<id>` (percent-encoded). In `open(_:)`, before the rest: `ledge` + host `agent` → `agents.focus(sessionID:)` with the path's last component.
- [ ] **Step 6: Probes (debug).** `ledge://probe/agents`: feed `agents.receive(_:facts:)` made-up messages for two sessions, "ledge" and "fairwell", a step every 3 s: prompt (working), `PermissionRequest` Bash "make test" (waiting), `PostToolUse` (working), `Stop` (done), then the second session's `StopFailure` `rate_limit`; then hold 30 s and `SessionEnd` both. `ledge://probe/agents-panel`: four sessions, one in each mark, `presenter.debugOpen(.agents)` for 20 s. Both in `openURL`'s `#if DEBUG` block, logged like the GitHub probes.
- [ ] **Step 7: Issues.** In `issues`, when `agentsEnabled` and the status is `.problem(text)`, `note("Agents", .unavailable(reason: text))` in the file's existing style.
- [ ] **Step 8: Build and test.** `make test`. Expected: all pass but the two built-in-display brightness tests.
- [ ] **Step 9: Run it and play the probe.** `make dev`, then `open ledge://probe/agents` and `open ledge://probe/agents-panel`. Expected: each moment as the spec's table, the working clock and count, the card.
- [ ] **Step 10: Live check with the user.** Ask the user to turn on Settings › Agents, then:
  1. start a new Claude session in VS Code; it shows on its first tool call (working, with a clock);
  2. a Bash prompt: the "Allow?" blip with "name · Bash: …", then the waiting item; Allow: back to working;
  3. AskUserQuestion: "Question"; plan mode's exit: "Plan";
  4. Esc mid-turn and at a prompt: idle, no blip;
  5. a finished turn: "Done" and its length; the card lists it;
  6. a click on the blip, the waiting item and a card row: the right VS Code window comes forward;
  7. the same in Ghostty, the right window raised;
  8. a session already running before the switch: does it join on its next tool call? Note the answer for the status line's wording;
  9. switching off: `~/.claude/settings.json` has none of Ledge's entries and the rest is as it was (`diff` against `settings.json.ledge-backup` shows only the original's content).

  Fix what fails before Step 11, each fix with its own test where one can pin it.
- [ ] **Step 11: Commit**: "show claude code sessions on the island: blips when one waits, finishes or fails, the waiting and working items, the agents card, and a click to the session".

### Task 13: Docs

**Files:**
- Modify: `README.md`: a "What it shows" row after GitHub's:

  > Claude Code sessions, once switched on in Settings › Agents | an orange asterisk: "Allow?", "Question" or "Plan" in amber when a session waits for you, with what it wants under the hole; "Done" and how long in green, "Failed" and why in red; while any wait or work, the count and the oldest turn's clock (working sits under music); hover for a card of every session; click to bring its window forward (VS Code, Ghostty). Never on the lock screen

  And the Agents pane in the Settings sentence.
- Modify: `docs/superpowers/specs/2026-09-25-notch-companion-design.md`: the priority table gains `39 agent` (blip), `25 agentWaiting` (sticky), `8 agentRun` (sticky).
- Modify: `docs/manual-checks.md`: "## Coding agents on the island (2026-10-23)" with Task 12's list, marking what the user confirmed and what is pending.

- [ ] **Step 1: Make the three edits.**
- [ ] **Step 2: Commit**: "describe coding agents on the island in the readme, the spec's priority table and the manual checks".
