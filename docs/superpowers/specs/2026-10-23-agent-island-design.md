# Coding agents on the island — design

2026-10-23. The user picked "coding agents" from the rest of their Developer
Island list (local Git, builds and tests, package installs, local servers,
errors, coding agents). They approved the transport, then the design section by
section in chat. Calls marked *(my call)* are mine, not the user's.

## Goal

The user stops watching Claude Code sessions to see whether they need them. The
island says when a session is waiting for them (a permission prompt, a
question, a plan to approve), when one finished its turn, when one failed, and
what is working now. A click brings that session's window forward. Nothing
leaves the Mac, and Claude Code never waits on Ledge.

## Decisions (user's, 2026-10-23)

| Question | Decision |
| --- | --- |
| Which agents | Claude Code only, every session on this Mac, any folder |
| Which moments | Waiting for you, finished its turn, working (live), failed. Each has its own switch |
| Where sessions run | VS Code's Claude extension (all 7 running sessions on 2026-10-23) and the CLI in Ghostty |
| Answering prompts | Not from the island. It shows what the session wants; a click goes to the session, where the user answers. Ledge never decides for Claude |
| How Ledge learns | Approach A: background (`async`) command hooks in `~/.claude/settings.json` run a small helper that writes one line to a Unix socket Ledge listens on. Not HTTP hooks (Claude waits on them and shows errors when Ledge is off), not reading transcripts alone |
| Working vs music | Working sits under music; it shows when nothing plays. Waiting sits over music |
| Settings | A new Settings › Agents pane, off by default, since turning it on writes to the user's Claude settings |

## What Claude Code gives us

Checked against the hooks reference (code.claude.com/docs/en/hooks.md) on
2026-10-23:

- Every hook gets `session_id`, `transcript_path`, `cwd`, `hook_event_name` on
  stdin, and `CLAUDE_PROJECT_DIR` in its environment.
- `PermissionRequest` fires only when Claude is about to ask (auto-approved
  calls never fire it), with `tool_name` and `tool_input`.
- `Stop` fires when a turn ends, but **not** when the user presses Esc.
  `StopFailure` fires instead of `Stop` on an API error, with `error`
  (`rate_limit`, `overloaded`, `authentication_failed`, `billing_error`,
  `server_error`, …).
- No event says "the user answered the prompt". The next `PreToolUse`,
  `PostToolUse`, `UserPromptSubmit` or `Stop` does.
- `"async": true` on a `command` hook: Claude does not wait for it, and its
  result is ignored. Exit 0 is silent; another non-zero code shows a
  non-blocking error line in the session.
- Hooks carry no PID, TTY or terminal. The hook is a child of the `claude`
  process, so the helper can walk up its own parents.
- An Esc writes a `user` line to the transcript whose content is exactly
  `[Request interrupted by user]` or `[Request interrupted by user for tool
  use]` (seen 89 times in this Mac's transcripts). The same text appears inside
  tool results and assistant messages, so only an exact text item counts.

## How a session reaches Ledge

### The message: a new `AgentWire` library

Foundation only, shared by the helper and the app, so the format has one
definition and the trimming is tested once.

One JSON object per line, at most 4 KB:

| Field | From |
| --- | --- |
| `v` | `1` |
| `event` | `hook_event_name` |
| `session` | `session_id` |
| `cwd` | `cwd` |
| `project` | `$CLAUDE_PROJECT_DIR`, else `cwd` |
| `transcript` | `transcript_path` |
| `title` | `session_title`, when set |
| `tool` | `tool_name` |
| `summary` | one line about the tool call, below |
| `notification` | `notification_type` |
| `message` | a `Notification`'s `message` |
| `error` | `StopFailure`'s `error` |
| `source`, `reason` | `SessionStart`'s `source`, `SessionEnd`'s `reason` |
| `stamp` | the helper process's start time from the kernel, in microseconds |
| `pids` | the helper's parent chain, nearest first, up to 12, stopping at 1 |

The summary, by tool: Bash, its command's first line; Edit, MultiEdit, Write,
Read, NotebookEdit, the file's name; Grep and Glob, the pattern; WebFetch, the
host; WebSearch, the query; Agent or Task, its description; `mcp__server__tool`,
"server: tool"; AskUserQuestion, its first question; anything else, none. Every
string is cut to 200 characters. A line still over 4 KB drops `message`, then
`summary`.

### The helper: `ledge-agent-hook`

A small executable target depending on `AgentWire` alone. It reads all of
stdin (so Claude never gets a broken pipe), builds the line, connects to the
socket with a 0.5 s limit, writes, and exits 0 whatever happens.

`make bundle` copies it into `Ledge.app/Contents/MacOS/` and the app is signed
with it inside. While the switch is on, Ledge copies it at every launch to
`~/Library/Application Support/Ledge/ledge-agent-hook`, and the hooks point at
that copy: the same path whether Ledge runs from `/Applications` or `dist/`.

### The socket

`~/Library/Application Support/Ledge/agents.sock`, mode 0600. Ledge listens
only while the switch is on. Each connection is one line, read up to 8 KB,
then closed. A stale socket file at start is removed and bound again.

### The hooks: `AgentHooks`

With the switch on, Ledge adds to `~/.claude/settings.json`, for each of
`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`,
`PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`,
`StopFailure`, `SessionEnd`, one group:

```json
{ "matcher": "*", "hooks": [ { "type": "command", "async": true, "timeout": 5,
  "command": "[ -x \"$HOME/Library/Application Support/Ledge/ledge-agent-hook\" ] && \"$HOME/Library/Application Support/Ledge/ledge-agent-hook\" || true" } ] }
```

`"matcher": "*"` only on `PreToolUse`, `PostToolUse`, `PostToolUseFailure` and
`PermissionRequest`, as the entries other tools keep there do (checked in this
Mac's file). The guard means a deleted helper still exits 0.

- Ledge's entries are known by the helper path in `command`. Ledge only adds,
  updates or removes those; Superset's, Orca's and RTK's stay as they are.
- Read, change, replace atomically. The first write saves
  `settings.json.ledge-backup` (once, never overwritten).
- No file: create one holding just the hooks. A file that is not a JSON object:
  touch nothing and show why in Settings.
- Turning the switch off removes Ledge's entries and drops any group or event
  left empty by that.
- *(My call, after the chat, which said keys might be reordered.)* Read and
  written by a small order-keeping JSON reader and writer laid out the way
  Claude Code writes the file (two-space indent, `"key": value`, numbers as
  they were), so the file changes only where Ledge's entries go in or out.

## Tracking sessions: `AgentSessions`

Pure. One record per `session_id`: name, project, cwd, transcript, host app,
`claude` PID, state, the turn's start, the last applied stamp, the last event
time. A session appears on its first event, so ones already running when the
hooks went in join on their next tool call.

| Event | Becomes |
| --- | --- |
| `SessionStart` | idle |
| `UserPromptSubmit` | working; the turn's clock starts |
| `PreToolUse`, `PostToolUse`, `PostToolUseFailure` | working (the clock starts now if it was not running) |
| `PreToolUse` of `AskUserQuestion` | waiting: question, with its text |
| `PreToolUse` of `ExitPlanMode` | waiting: plan |
| `PermissionRequest` | waiting: permission, "Bash: make test" |
| `Notification` `permission_prompt`, `elicitation_dialog`, `elicitation_url_dialog`, `agent_needs_input` | waiting, with its message, unless already waiting |
| other `Notification`s (`idle_prompt`, …) | nothing |
| `Stop` | finished, with the turn's length |
| `StopFailure` | failed, with the reason |
| `SessionEnd`, or the `claude` process exits | removed |
| the transcript's interrupt line | idle, no moment |

- **Order.** An event whose `stamp` is older than the session's last applied
  one is dropped, so a late `PreToolUse` cannot hide the prompt that followed
  it.
- **Moments.** Entering waiting, finished or failed is a moment (a blip).
  Leaving waiting is not. A second prompt after the first was answered is a
  new moment.
- **Headless runs.** A session whose `claude` process was started with `-p` or
  `--print` (read from its arguments) is ignored: Superset jobs, crons, scripts.
- **Subagents.** No rows of their own. Their tool calls make the parent
  working, and their prompts make it waiting.
- **Names.** The title when set, else the project folder's name. A second live
  session with the same name is "ledge 2", kept for its life.
- **Forgetting.** A session idle, finished or failed for an hour leaves the
  list. Nothing is saved across launches.

### The watchers (thin, main actor)

- **Process.** From `pids`, the first process named `claude` (else the
  helper's grandparent). Its exit removes the session.
- **Transcript.** While a session is working or waiting, Ledge watches its
  transcript from the current end. A new line that is a `user` message whose
  content is exactly one of the two interrupt texts (or a text item equal to
  one) makes it idle. Not documented: if the format changes, an interrupted
  session stays working until its next event or its exit.
- **Host app.** macOS's responsible process for the `claude` PID (as
  `CallApp` does), else the first regular app up the chain: VS Code for the
  extension, Ghostty for the CLI.

## What the user sees

**The glyph.** SF Symbol `asterisk` in Claude orange (`#D97757`), not
Anthropic's logo *(my call)*. While anything works it turns once every 2.4 s;
with Reduce Motion it stays still. **Changed 2026-10-26 (user's call: "claude
real logo"):** Claude's own mark (`ClaudeMark`, the path from the Claude app's
bundled asset) replaces the asterisk wherever it stood for Claude, colours
unchanged; and it no longer turns ("dont rotate the claude logo"), the clock
alone saying a session works.

**Blips** — a new `agent` kind, priority 39 (over a GitHub blip, under a
notification):

| Moment | Left | Right | Under the hole |
| --- | --- | --- | --- |
| Waiting | asterisk | "Allow?", "Question" or "Plan", amber | `ledge · Bash: make test`, 8 s |
| Finished | asterisk | "Done", green | `ledge · 3m 20s`, 3 s |
| Failed | asterisk | "Failed", red | `ledge · Rate limited`, 3 s |

**Sticky items:**

- `agentWaiting`, priority 25 (over a Clock timer and GitHub's running item,
  under a call): the asterisk with an amber count, the session's name right, or
  "2 waiting".
- `agentRun`, priority 8 (under music at 10, over the charging state at 5): the
  turning asterisk, a count from two sessions, and the oldest running turn's
  clock (`4:12`, `1:04:12`).
- Neither shows on the lock screen.

**Click.** A blip goes to its session; the waiting item to the longest-waiting
session; the working item to the oldest turn.

- VS Code: Ledge opens the session's project folder with VS Code, which brings
  forward the window that has it. It cannot pick the Claude tab inside.
- Ghostty: Ledge activates Ghostty and, with Accessibility, raises the window
  whose title has the project folder's name; without it, just activates.
- Anything else: activates the app.

**Hover: the Agents card.** Joins the swipe after GitHub, while the switch is
on and a session is listed. Sessions, most recently active first: the host
app's small icon and the name left; the state right: amber "Bash: make test",
an orange clock "4:12", green "Done 2m ago", red "Rate limited", dim "Idle". A
row's click goes to that session. Hovering an agent blip or sticky item opens
it, as GitHub's do.

**Quiet when looking.** A session whose host app is frontmost and whose focused
window's title has the project folder's name (read with Accessibility) gets no
blip. Sticky items and the card still show. Without Accessibility, blips always
show.

## Settings › Agents

- "Show Claude Code sessions", off by default. On: copy the helper, write the
  hooks, listen. Off: stop listening and remove the hooks. Quitting Ledge
  leaves the hooks; they stay silent while Ledge is off.
- A status card: "Hooks in ~/.claude/settings.json" with "Last heard from a
  session 2m ago" (or "Nothing heard yet: start a new session"); or "Can't
  read settings.json: …"; or "The helper is missing" with Repair.
- Moments: Waiting, Finished, Working, Failed, each a switch, with a preview
  like the other panes.
- Dropped *(my call)*: the "interrupts aren't being noticed" line mentioned in
  chat. A prompt typed while Claude works looks the same as a missed Esc, so it
  would raise false alarms.

`AppSettings` keys: `agentsEnabled` (false), `agentWaiting`, `agentFinished`,
`agentWorking`, `agentFailed` (true).

## Building blocks

| Unit | Library | Job |
| --- | --- | --- |
| `AgentMessage`, `AgentTrim` | `AgentWire` | The line's fields, the summaries, the caps |
| `ledge-agent-hook` | executable | stdin to the socket, always exit 0 |
| `OrderedJSON` | `AgentService` | Read and write JSON keeping key order and number text |
| `AgentHooks` | `AgentService` | Merge and remove Ledge's entries in a settings JSON object |
| `AgentSessions` | `AgentService` | The state machine, moments, names, forgetting |
| `AgentNotice` | `AgentService` | Each moment's word, colour and caption |
| `AgentPanelRows` | `AgentService` | The card's rows |
| `AgentListener` | `AgentService` | The socket |
| `AgentWatchers` | `AgentService` | Process exit, transcript interrupts |
| `AgentHost` | `AgentService` | Host app, focus, "is the user looking" |
| `AgentMonitor` | `AgentService` | Ties them together for `AppModel` |
| kinds, items, card | `ActivityKit`, `NotchKit` | `agent`, `agentWaiting`, `agentRun`, the Agents panel |

## Tests

- `AgentTrim`: each tool's summary, the 200-character cut, the 4 KB cap and
  its drop order, a missing `CLAUDE_PROJECT_DIR`.
- `AgentHooks`: into nothing, into an empty object, beside Superset, Orca and
  RTK entries (left byte-for-byte equal as values), twice (no change), an old
  helper path updated, removal of only Ledge's entries and the emptied groups,
  a non-object file left alone.
- `AgentSessions`: the event table row by row; an out-of-order stamp; the
  interrupt; a second prompt after an answer; `-p` ignored; name clashes;
  forgetting after an hour; moments fired once per entry.
- `AgentNotice` and `AgentPanelRows`: words, colours, captions, row order.
- End to end: a listener on a temporary socket, the built helper run with a
  sample hook JSON on stdin, the line arrives; with no listener the helper
  exits 0 within 0.5 s.
- Headless renders: each blip, both sticky items, the card.
- `ledge://probe/agents` (debug builds) plays waiting, working, finished and
  failed with made-up sessions; `ledge://probe/agents-panel` pins the card.

## Docs

The README's "What it shows" table and Settings line, the companion spec's
priority table, and a "Coding agents" section in `docs/manual-checks.md`.

## Verify on this Mac (manual checks)

1. A new VS Code session and a Ghostty session each show up on their first
   tool call; the helper's chain has `claude`; the host is VS Code or Ghostty.
2. Whether a session already running picks up the new hooks, or only new ones
   do (Settings' "start a new session" wording follows from this).
3. A Bash prompt: the waiting blip and item; Allow: back to working.
4. AskUserQuestion and ExitPlanMode show "Question" and "Plan".
5. Esc while working and at a prompt: idle, no blip.
6. A finished turn: "Done" and its length. Closing the window or `/exit`: the
   session leaves.
7. Clicks reach the right VS Code window and the right Ghostty window.
8. Switching off removes only Ledge's entries.

A rate limit cannot be caused on purpose; the probe covers "Failed".

## Not in scope

Answering prompts from the island, other agents (Codex, Gemini, Cursor's own),
sessions in the cloud, desktop-app sessions (they may fire the same hooks; not
designed for), the token or cost count, showing subagents as rows, saving
sessions across launches.
