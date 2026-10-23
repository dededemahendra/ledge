# Long commands Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A zsh command that ran 10 s or more shows on the island when it finishes: a green check or red cross, its time, and its first plain words in the caption. A click brings back its terminal. It stays quiet while that terminal is in front.

**Architecture:**
- A marked block in `~/.zshrc`, installed and removed by a Settings switch, calls the existing helper (`ledge-agent-hook`) in a new `command` mode.
- The helper trims the line to a safe label and sends one JSON line to `commands.sock`.
- A `CommandMonitor` in `AgentService` listens there, reusing `AgentListener`, finds the terminal app, filters, and hands moments to `AppModel`.
- `AppModel` shows each moment as a blip with a caption.

**Tech Stack:** Swift 6, SwiftPM, zsh, Unix sockets (existing `AgentSocket`/`AgentListener`), swift-testing. macOS 27.

**Spec:** `docs/superpowers/specs/2026-10-23-long-commands-design.md`

## Global Constraints

- Threshold 10 s; exit status 130 (Ctrl-C) shows nothing.
- Label rules:
  - the program's base name plus up to two following plain words;
  - plain means only `[A-Za-z0-9_-]`, not starting with `-`, at most 20 characters;
  - the whole label is at most 24 characters, cut at a word;
  - the label is never logged.
- Skipped programs: `vi vim nvim nano emacs hx less more man ssh mosh top htop btop watch tmux screen zsh bash fish claude codex`, and `tail` when any argument is `-f` or `-F`.
- Socket: `~/Library/Application Support/Ledge/commands.sock`. Helper: `AgentSocket.helperURL()`.
- `ActivityKind.command`: priority 36, TTL 5. Record id `"command"`.
- Glyphs and colours: `checkmark.circle.fill` with tint `.positive` when passed, `xmark.circle.fill` with tint `.warning` when failed. The trailing ear shows `TimerText.format(seconds:)`.
- Caption, 5 s: `"<label> · <duration>"` or `"<label> failed · <duration>"`. The duration reads "45s", "1m 20s" or "2h 3m".
- The `~/.zshrc` block lies between `# >>> Ledge long commands >>>` and `# <<< Ledge long commands <<<`, with the exact body in the spec. The backup is `~/.zshrc.ledge-backup`, written once with the file's mode. A symlink's target is the file edited.
- Settings: `showsLongCommands` **off** by default.
  - Row "Long commands", detail "zsh commands that ran 10 seconds or more".
  - Footer: "Adds a marked block to ~/.zshrc and keeps a backup. New terminal windows pick it up; run exec zsh in open ones."
- No blip while locked: dropped, not queued. No blip while the command's terminal app is frontmost.
- Tests: `make test FILTER=<one name or file>`, never with `|`.

## Review Focus

1. **A `~/.zshrc` that already contains the block** (a second switch-on, or one copied by hand): one block, not two. Pinned by `installingTwiceLeavesOneBlock` (Task 2).
2. **A secret in a command line** (`curl -H "Authorization: Bearer abc…"`, `export TOKEN=…`, `gh auth login --with-token ghp_…`): only plain words up to 20 characters survive, so nothing secret is shown. Pinned by `secretsNeverReachTheLabel` (Task 1).
3. **A command run in VS Code's terminal, iTerm or Terminal:** the click brings that app forward, found from the parent chain. Pinned by `theTerminalIsFoundFromTheParentChain` (Task 3).
4. **A broken block** (begin marker without end, from a hand edit): left alone and reported, never "fixed" by deleting lines. Pinned by `aBrokenBlockIsLeftAloneAndReported` (Task 2).
5. **Many commands finishing in a row** (a script of `&&`s counts as one command line): one blip per command line. The newest replaces the last, as blips of a kind do. Covered by `ActivityQueue`'s existing per-kind replacement; no new test.

---

### Task 1: The wire — message, trimming, socket path, helper mode

**Files:**
- Create: `Sources/AgentWire/CommandMessage.swift`
- Modify: `Sources/AgentWire/AgentSocket.swift`. Add `public static func commandsSocketURL(home: URL = AgentSocket.home) -> URL`, which is `supportDirectory(home:)/commands.sock`.
- Modify: `Sources/LedgeAgentHook/main.swift`. With `arguments[1] == "command"`, build a message with `CommandHook.message(arguments:cwd:pids:stamp:)` and send it to `commandsSocketURL()` (timeout 0.5); otherwise run today's path. Exit 0 always.
- Test: `Tests/AgentWireTests/CommandMessageTests.swift`

**Interfaces:**
- Produces:
  - `public struct CommandMessage: Codable, Sendable, Equatable { public var v: Int; public var event: String; public var label: String; public var status: Int32; public var seconds: Double; public var cwd: String?; public var pids: [Int32]; public var stamp: Int64; public init(label:status:seconds:cwd:pids:stamp:) }` — `v` is 1 and `event` is "command".
  - `public enum CommandTrim { public static func label(_ line: String) -> String?; public static func isSkipped(_ line: String) -> Bool }` — the label is nil when the line has no program, or the program is skipped.
  - `public enum CommandHook { public static func message(arguments: [String], cwd: String?, pids: [Int32], stamp: Int64) -> CommandMessage? }`. The arguments are `["ledge-agent-hook", "command", status, seconds, line]`. It returns nil for bad numbers or a nil label.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func theLabelIsTheProgramAndTwoPlainWords()   // "make test" → "make test"; "npm run build -- --watch" → "npm run build"; "/usr/bin/swift test --parallel" → "swift test"
@Test func secretsNeverReachTheLabel()              // "curl -H \"Authorization: Bearer abc123\" https://x" → "curl"; "TOKEN=abc make" → nil (an assignment first is no program); "gh auth login --with-token ghp_0123456789abcdefghijklmnopqrstuv" → "gh auth login"; "echo ghp_0123456789abcdefghijklmn" → "echo"
@Test func aLongLabelIsCutAtAWord()                 // "xcodebuild archive-and-export something" → "xcodebuild" (24 limit)
@Test func longLivedProgramsAreSkipped()            // vim x, ssh host, claude, tail -f log → isSkipped true; tail log → false; make → false
@Test func theHelperBuildsTheMessage()              // ["ledge-agent-hook","command","1","83.4","npm run build"] → label "npm run build", status 1, seconds 83.4; bad seconds → nil; skipped line → nil
@Test func theMessageRoundTripsAsJSON()             // encode → decode equal; event == "command", v == 1
```

- [ ] **Step 2: Run them to make sure they fail.** Run `make test FILTER=CommandMessageTests`. Expected: compile failure.
- [ ] **Step 3: Implement** the three units and the socket path. The program is the first word, unless it is an assignment (contains `=` before any `/`): then the label is nil. Then wire `main.swift`.
- [ ] **Step 4: Run them to see them pass.** Run `make test FILTER=CommandMessageTests`. Expected: 6 passed.
- [ ] **Step 5: Commit** with the message "carry a finished command to ledge: a safe label, its status and time, on a socket of its own, from the helper's command mode".

### Task 2: The block and the careful edit of `~/.zshrc`

**Files:**
- Create: `Sources/AgentService/ShellHook.swift`
- Test: `Tests/AgentServiceTests/ShellHookTests.swift`

**Interfaces:**
- Produces:
  - `public enum ShellHookBlock`, with:
    - `public static let begin = "# >>> Ledge long commands >>>"`
    - `public static let end = "# <<< Ledge long commands <<<"`
    - `public static var text: String` — the full block, from the spec, ending "\n".
    - `public enum State: Equatable { case absent, present, broken }`
    - `public static func state(of: String) -> State`
    - `public static func installing(into: String) -> String`, which appends the block after a blank line and returns the text unchanged if it is present.
    - `public static func removing(from: String) -> String`, which removes the block and the one blank line installing added.
  - `public struct ZshrcFile`, with:
    - `public enum Problem: Error, Equatable { case unreadable(String), broken, unwritable(String) }`
    - `public init(url: URL)`
    - `public func install() throws(Problem)` and `public func uninstall() throws(Problem)`
    - `public func isInstalled() -> Bool`
    - It edits the symlink's target, writes `.ledge-backup` once with the original's mode (copy `AgentHooksFile.writeBackup`'s O_EXCL and fchmod approach), and writes atomically. A missing file is created by `install` with just the block.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func installingIntoEmptyAndExistingText()      // "" → text == block; "export A=1\n" → starts with it, then blank line, then block
@Test func installingTwiceLeavesOneBlock()           // installing(installing(x)) == installing(x)
@Test func removingTakesExactlyWhatInstallingAdded() // removing(installing("export A=1\n")) == "export A=1\n"
@Test func aBrokenBlockIsLeftAloneAndReported()      // text with begin but no end: state == .broken; ZshrcFile.install/uninstall throw .broken and the file is unchanged
@Test func theFileIsCreatedBackedUpAndKeepsItsMode() // temp home: install creates; existing 0600 file → after install mode 0600, .ledge-backup has the old content and mode 0600
@Test func aSymlinkedZshrcStaysALink()                // ~/.zshrc → dotfiles/zshrc: after install the link remains, the target has the block
```

- [ ] **Step 2: Run them to make sure they fail.** Run `make test FILTER=ShellHookTests`. Expected: compile failure.
- [ ] **Step 3: Implement** `ShellHookBlock` and `ZshrcFile`.
- [ ] **Step 4: Run them to see them pass.** Run `make test FILTER=ShellHookTests`. Expected: 6 passed.
- [ ] **Step 5: Commit** with the message "write ledge's zsh block into ~/.zshrc with care: once, with a backup and the file's mode, through a symlink, and never over a broken block".

### Task 3: `CommandMonitor`

**Files:**
- Create: `Sources/AgentService/CommandMonitor.swift`
- Test: `Tests/AgentServiceTests/CommandMonitorTests.swift`

**Interfaces:**
- Consumes: `CommandMessage` and `commandsSocketURL()` (Task 1); `ZshrcFile` (Task 2); `AgentListener`; `AgentMonitor.installHelper(from:to:)`; `AgentHostLookup.resolve`; `CallAppInfo`.
- Produces:
  - `public struct CommandMoment: Sendable, Equatable { public let label: String; public let passed: Bool; public let seconds: Double; public let app: CallAppInfo? }`
  - `@MainActor public final class CommandMonitor`, with:
    - `public enum Status: Equatable { case off, ready, problem(String) }`
    - `public private(set) var status`
    - `public var onMoment: ((CommandMoment) -> Void)?`
    - `public init(zshrc: ZshrcFile = .init(url: home/.zshrc), socket: URL = AgentSocket.commandsSocketURL(), helper: URL = AgentSocket.helperURL(), helperSource: URL? = AgentPaths.live.helperSource, frontmostPID: @escaping () -> pid_t? = { NSWorkspace.shared.frontmostApplication?.processIdentifier }, appFor: @escaping ([Int32]) -> CallAppInfo? = <resolve the first pid with an app via AgentHostLookup.resolve(… lookup: .live)>)`
    - `public func enable()` — installs the helper if a source exists, installs the block, starts listening; on failure, status `.problem(text)` and nothing is left half-done.
    - `public func disable()` — stops listening and removes the block.
    - `static func moment(for message: CommandMessage, frontmostPID: pid_t?, app: CallAppInfo?) -> CommandMoment?` — pure.

- [ ] **Step 1: Write the failing tests** (for the pure `moment` function and the decoding path):

```swift
@MainActor @Test func passedAndFailedCommandsBecomeMoments()  // status 0 → passed true; status 2 → passed false; label and seconds carried
@MainActor @Test func anInterruptedCommandIsQuiet()            // status 130 → nil
@MainActor @Test func aShortCommandIsQuiet()                   // seconds 9.9 → nil
@MainActor @Test func aCommandInTheFrontmostTerminalIsQuiet()  // app.pid == frontmostPID → nil; another frontmost → moment
@MainActor @Test func theTerminalIsFoundFromTheParentChain()   // a monitor with an injected appFor: a received line with pids [900, 901, 902] → moment.app == the app appFor returns for that chain
```

- [ ] **Step 2: Run them to make sure they fail.** Run `make test FILTER=CommandMonitorTests`. Expected: compile failure.
- [ ] **Step 3: Implement.** The listener's `onLine` decodes a `CommandMessage`, resolves the app, applies `moment`, and calls `onMoment` on the main actor. Expose `func receive(_ line: Data)` internally for the parent-chain test.
- [ ] **Step 4: Run them to see them pass.** Run `make test FILTER=CommandMonitorTests`. Expected: 5 passed.
- [ ] **Step 5: Commit** with the message "listen for finished commands: find the terminal they ran in, and keep quiet for short, interrupted or in-front ones".

### Task 4: The kind and the island

**Files:**
- Modify: `Sources/ActivityKit/ActivityKind.swift`. Add `case command`, priority 36, TTL 5, `canSitInTab` false (it has a TTL).
- Modify: `Sources/NotchKit/NotchController.swift`. Add `public static let commandActivityID = "command"`, and let the caption show while it leads (the `hasCaption` list).
- Test: `Tests/ActivityKitTests/ActivityQueueTests.swift`, `Tests/NotchKitTests/NotchControllerTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
@Test func aFinishedCommandIsABlipBetweenGitHubAndTheUpdate()  // priority 36, defaultTTL 5, < .github, > .update
@MainActor @Test func aFinishedCommandShowsItsCaption()        // setActivities([command display]) then setCaption("make test · 1m 20s") → captionText == that
```

- [ ] **Step 2: Run them to make sure they fail.** Run `make test FILTER=ActivityQueueTests`, then `make test FILTER=NotchControllerTests`. Expected: compile failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run them to see them pass,** with the same two commands. Expected: all pass.
- [ ] **Step 5: Commit** with the message "add the finished command: a five second blip under github, with its caption".

### Task 5: Settings

**Files:**
- Modify: `Sources/LedgeSettings/AppSettings.swift`. Add `showsLongCommands`, default false.
- Modify: `Sources/SettingsKit/PreviewScene.swift`, `PreviewContent.swift` and `PreviewStage.swift`. Add `case longCommand`, titled "Long commands"; a sample with a green check, "1:20" and the caption "make test · 1m 20s".
- Modify: `Sources/Ledge/SettingsPanes.swift`. Under "What happens on the Mac", add the row "Long commands" with detail "zsh commands that ran 10 seconds or more", symbol `terminal`, colour `.systemGray`, `\.showsLongCommands`, `.longCommand`. Add the footer from Global Constraints. When the monitor reports `.problem(text)`, the row's detail shows `text` instead.
- Test: `Tests/LedgeSettingsTests/AppSettingsTests.swift`, `Tests/SettingsKitTests/PreviewStageTests.swift` (the latter already loops over `allCases`)

- [ ] **Step 1: Write the failing test:**

```swift
@MainActor @Test func longCommandsAreOffByDefault()   // fresh → showsLongCommands == false; set true → a new AppSettings on the suite reads true
```

- [ ] **Step 2: Run it to make sure it fails.** Run `make test FILTER=AppSettingsTests`. Expected: compile failure.
- [ ] **Step 3: Implement** the setting, the scene, the sample, the stage case and the row.
- [ ] **Step 4: Run the tests to see them pass.** Run `make test FILTER=AppSettingsTests`, then `make test FILTER=PreviewStageTests`. Expected: all pass. Note that `aScenesSwitchIsItsOption` may assume every switch defaults on; if it does, rule on it in the ledger and pin the exception.
- [ ] **Step 5: Commit** with the message "add long commands to settings: off until switched on, its preview, and why it can't when it can't".

### Task 6: Wire it into `AppModel`

**Files:**
- Modify: `Sources/Ledge/AppModel.swift`

**Interfaces:**
- Consumes: `CommandMonitor` and `CommandMoment` (Task 3); `ActivityKind.command` and `commandActivityID` (Task 4); `showsLongCommands` (Task 5); `TimerText.format`; `activateApp(bundleID:pid:)`; `showCaption(_:for:)`.

- [ ] **Step 1: Wire the monitor and the blip.**
  - Owning and switching:
    - add `private let commands = CommandMonitor()`;
    - in `applySettings`, call `commands.enable()` when `showsLongCommands` is on, else `commands.disable()`;
    - in `stop()`, leave the block in place (it is the user's setting) and only stop listening.
  - `commands.onMoment`:
    - **While locked:** drop it.
    - **Otherwise:** insert `ActivityRecord(id: commandActivityID, kind: .command, ttl: 5, title: caption, compactText: TimerText.format(seconds: seconds.rounded(.down)), symbolName: passed ? "checkmark.circle.fill" : "xmark.circle.fill", tint: passed ? .positive : .warning, url: URL(string: "ledge://command"))`. Then `showCaption(caption, for: 5)`, and remember `moment.app` for the click.
  - **Click:** route `ledge://command` in `open(_:)` to `activateApp(bundleID:pid:)` for the remembered app.
  - **Caption duration:** under 60 s it reads "45s"; under an hour, "1m 20s"; from an hour, "2h 3m".
- [ ] **Step 2: Run the whole suite.** Run `make test`. Expected: all pass.
- [ ] **Step 3: Commit** with the message "show finished commands on the island: the blip, its caption and time, and a click back to the terminal".

### Task 7: Docs, install, live check

**Files:**
- Modify: `README.md`. Add a row after GitHub's: "A zsh command that ran 10 s or more, once Settings › Island › Long commands is on | a green check or red cross left, its time right, "make test · 1m 20s" under the hole for 5 s; click to bring its terminal back. Quiet while that terminal is in front. Adds a marked block to ~/.zshrc".
- Modify: `docs/manual-checks.md`. Append "## Long commands (2026-10-23)" with the live checks below.

- [ ] **Step 1: Commit the docs.**
- [ ] **Step 2: Install and relaunch.** Run `make install`, then `make stop`, then `open /Applications/Ledge.app`.
- [ ] **Step 3: Live check with the user:**
  1. Switch on Settings › Island › Long commands: the block appears in `~/.zshrc`, with a backup.
  2. In a new terminal, run `sleep 12` and switch to another app: a green blip, "sleep · 12s".
  3. Run `sleep 12; false`: a red blip.
  4. Ctrl-C a `sleep 30`: nothing.
  5. Stay in the terminal: nothing.
  6. Switch the setting off: the block is gone.
