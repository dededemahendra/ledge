# The meeting's own mute (Zoom, Meet) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** During a Zoom call, or a Meet in a browser, the card's mute button presses the meeting's own mute, and the island shows the meeting's own mute state. Everything else keeps today's system-wide mute.

**Architecture:**
- A pure finder in `CallService` locates the mute control in an Accessibility tree, through a small node protocol, and reads its state from the title. Recorded trees exercise it in tests.
- A live, thread-safe shell walks the real tree once per call off the main thread, keeps the found element, re-reads only its title once a second, and presses it on demand.
- `CallService` uses it for the live app when it answers, and never stacks it with a system mute.

**Tech Stack:** Swift 6, ApplicationServices (AXUIElement), swift-testing. macOS 27.

**Spec:** `docs/superpowers/specs/2026-10-22-call-controls-design.md`. This plan covers its "Scope now (2026-10-23)" section: Zoom and Meet only.

## Global Constraints

- Zoom (`us.zoom.xos`): the `AXMenuItem` with identifier `onMuteAudio:`, searched under the app's menu bar. A title starting "Unmute" means muted; starting "Mute" means unmuted; anything else is unknown.
- Meet: only when the call's app is a browser (`CallMeetingMatcher.browsers`), and only inside that app's windows whose title contains "Meet - ".
  - Find an `AXButton` titled "Turn off microphone" (unmuted) or "Turn on microphone" (muted).
  - Set `AXManualAccessibility` = true on the app element first (Chromium).
- No keystrokes, nothing brought to the front. Every AX call gets `AXUIElementSetMessagingTimeout(…, 0.25)`. Walks and reads run off the main thread.
- A walk is capped at depth 40 and 3000 nodes.
- A tap with the app's control known:
  1. undo any system mute Ledge applied;
  2. press the app's control only if its state differs from the target.
  The island shows muted if the app's own state is muted, or Ledge's system mute holds.
- Without Accessibility trust, or with no control found, the behaviour is today's, unchanged.
- The debug probe (`CallAppProbe`, `ledge://probe/call-ax`) stays, debug builds only.
- Tests: `make test FILTER=<one name or file>`. Don't put `|` in FILTER.

## Review Focus

1. **The Meet tab isn't the front tab** (no page exposed): no control is found, so the system mute is used. Pinned by `noMeetWindowNoControl` (Task 1) and `withoutAControlTheSystemMuteIsUsed` (Task 3).
2. **Muting from Zoom's or Meet's own window:** the island goes red within about a second. Pinned by `theAppsOwnStateIsWhatTheIslandShows` (Task 3).
3. **A system mute Ledge applied before the app's control was found**, then a tap: the system mute is undone, with no double mute. Pinned by `aSystemMuteIsUndoneWhenTheAppsOwnTakesOver` (Task 3).
4. **A microphone button in a non-Meet window,** or Zoom's other "Mute all" items, are never pressed. Pinned by `onlyTheMeetWindowCounts` and `zoomsMuteAllIsNotTheMuteItem` (Task 1).
5. **A hung Zoom or browser:** the island doesn't freeze. Ensured by off-main walks and reads with a 0.25 s timeout. Checked in the final review; there is no unit test for the shell.

---

### Task 1: The finder

**Files:**
- Create: `Sources/CallService/MeetingMute.swift`
- Modify: `Sources/CallService/CallMeeting.swift`. Make `CallMeetingMatcher.browsers` `public`.
- Test: `Tests/CallServiceTests/MeetingMuteTests.swift`

**Interfaces:**
- Produces:
  - `public protocol AXNode { var role: String? { get }; var identifier: String? { get }; var title: String? { get }; var children: [Self] { get } }`
  - `public struct AXSnapshot: AXNode, Sendable, Equatable { public var role, identifier, title: String?; public var children: [AXSnapshot]; public init(role:identifier:title:children:) }`, for test fixtures.
  - `public enum MeetingMute: Sendable, Equatable { case zoom, meet }`, with:
    - `public static func kind(for bundleID: String) -> MeetingMute?`
    - `public static func find<N: AXNode>(_ kind: MeetingMute, menuBar: N?, windows: [N]) -> N?`
    - `public static func isMuted(_ kind: MeetingMute, title: String?) -> Bool?`

- [ ] **Step 1: Write the failing tests.** Fixtures are hand-built `AXSnapshot` trees shaped like the probe's recordings, with no real meeting names:
  - a Zoom menu bar of `AXMenuBarItem` "Meeting" → `AXMenu` → `AXMenuItem` children with ids `onMuteAll:` "Mute all", `onUnmuteAll:` "Ask all to unmute", `onMuteAudio:` "Unmute audio", `onMuteVideo:` "Start video";
  - a Dia window titled "Personal: Meet - abc-defg-hij", with groups 10 deep down to `AXButton`s "Turn off microphone", "Turn off camera", "Leave call";
  - a window "Personal: Home".

```swift
@Test func zoomsMuteItemIsFoundByItsIdentifier()   // find(.zoom, menuBar:, windows: []) → identifier "onMuteAudio:"; isMuted(.zoom, "Unmute audio") == true
@Test func zoomUnmutedReadsFromTheTitle()          // isMuted(.zoom, "Mute audio") == false; isMuted(.zoom, "Stummschalten") == nil
@Test func zoomsMuteAllIsNotTheMuteItem()          // a menu with only onMuteAll:/onUnmuteAll: → nil
@Test func meetsMicrophoneButtonIsFoundInTheMeetWindow() // → title "Turn off microphone"; isMuted(.meet, …) false; "Turn on microphone" → true
@Test func onlyTheMeetWindowCounts()               // the same button inside "Personal: Home" only → nil
@Test func noMeetWindowNoControl()                 // windows [Home] → nil
@Test func whichAppsHaveAControl()                 // us.zoom.xos → .zoom; company.thebrowser.dia, com.google.Chrome → .meet; com.apple.FaceTime → nil
```

- [ ] **Step 2: Run them to make sure they fail.** Run `make test FILTER=MeetingMuteTests`. Expected: compile failure.
- [ ] **Step 3: Implement** a depth-first search capped at depth 40 and 3000 nodes:
  - Zoom: under `menuBar`, for `role == "AXMenuItem" && identifier == "onMuteAudio:"`.
  - Meet: in each window whose title contains "Meet - ", for `role == "AXButton"` with one of the two titles.
- [ ] **Step 4: Run them to see them pass.** Run `make test FILTER=MeetingMuteTests`. Expected: 7 passed.
- [ ] **Step 5: Commit** with the message "find zoom's and meet's own mute in an accessibility tree, and read its state from the title".

### Task 2: The live shell

**Files:**
- Create: `Sources/CallService/AppMuteControls.swift`

**Interfaces:**
- Consumes: `MeetingMute`, `AXNode` (Task 1); `CallAppInfo`.
- Produces:
  - `@MainActor public protocol AppMuteSource: AnyObject { func update(for app: CallAppInfo?); var muted: Bool? { get }; func press() -> Bool }`
    - `muted` is nil when there is no control for the current app.
    - `press()` returns whether a control was pressed.
  - `@MainActor public final class AXAppMuteControls: AppMuteSource`, which works like this:
    - It keeps a private serial `DispatchQueue` and a lock-protected cache: the bundle id, an `@unchecked Sendable` wrapper around the found `AXUIElement`, and the last state.
    - `update(for:)` runs at most once a second, or at once when the app changes:
      - with no element cached, it walks on the queue, wrapping live elements as an `AXNode` that fetches children lazily;
      - otherwise it reads the element's `kAXTitleAttribute` on the queue;
      - a failed read drops the element.
    - Untrusted (`AXIsProcessTrusted() == false`), or an app with no `MeetingMute.kind`, gives `muted = nil`.
    - `press()` sends `AXUIElementPerformAction(element, kAXPressAction)` on the queue, flips the cached state at once, and lets the next read correct it.

- [ ] **Step 1: Implement `AXAppMuteControls`** to the interface above, with the 0.25 s messaging timeout on the app element.
- [ ] **Step 2: Build.** Run `swift build`. Expected: success, with no warnings in the file under Swift 6 strict concurrency.
- [ ] **Step 3: Commit** with the message "read and press the meeting's own mute through accessibility, off the main thread, finding it once per call".

### Task 3: `CallService` uses the app's own mute

**Files:**
- Modify: `Sources/CallService/CallService.swift`
- Test: `Tests/CallServiceTests/CallServiceTests.swift`

**Interfaces:**
- Consumes: `AppMuteSource` (Task 2).
- Produces:
  - `CallService.init` gains `appMute: AppMuteSource? = nil`; nil means an `AXAppMuteControls()`.
  - `CallUpdate` gains `public let appMuted: Bool?`, defaulting to nil.
  - `CallUpdate.isMuted` is `appMuted == true || <system muted>`.
  - `canMute` is true when `appMuted != nil` or the system can mute.

- [ ] **Step 1: Write the failing tests.** Add a `FakeAppMute: AppMuteSource` to the rig: `var muted: Bool?`, `var updatedFor: [String]`, and `var presses`, where `press()` increments `presses`, flips `muted` and returns `muted != nil`.

```swift
@MainActor @Test func muteUsesTheAppsOwnMuteWhenItHasOne()      // live Zoom, fake.muted = false → toggleMute → presses == 1, device "a" not muted
@MainActor @Test func withoutAControlTheSystemMuteIsUsed()      // fake.muted = nil → toggleMute → device "a" muted, presses == 0
@MainActor @Test func theAppsOwnStateIsWhatTheIslandShows()     // fake.muted = true → refresh → isMuted == true, appMuted == true, device "a" not muted
@MainActor @Test func aSystemMuteIsUndoneWhenTheAppsOwnTakesOver()
    // fake.muted = nil, toggleMute (system mute on); then fake.muted = false; toggleMute → device unmuted, presses == 0, isMuted false
@MainActor @Test func theLiveAppIsHandedToTheControl()          // live Zoom → fake.updatedFor.last == "us.zoom.xos"; after the call → update(for: nil)
```

- [ ] **Step 2: Run them to make sure they fail.** Run `make test FILTER=CallServiceTests`. Expected: compile failure.
- [ ] **Step 3: Implement.**
  - In `refresh`:
    - call `appMute.update(for: <live app or nil>)`;
    - fill `appMuted`;
    - while the app's control is known, skip the "re-apply system mute to new devices" step.
  - `toggleMute()`:
    - with `appMute.muted != nil`: target = `!(appMuted == true || systemMuted)`; restore Ledge's system mute; then press if `appMute.muted != target`;
    - otherwise: today's path.
- [ ] **Step 4: Run them to see them pass.** Run `make test FILTER=CallServiceTests`. Expected: every CallService test passes.
- [ ] **Step 5: Commit** with the message "mute a zoom or meet call with the meeting's own mute, never stacked with the system mute".

### Task 4: Probe, docs, install, live check

**Files:**
- Add: `Sources/Ledge/CallAppProbe.swift`, plus its `AppModel` hooks (already written, uncommitted).
- Modify: `README.md`. On the call row, change "a card with a mute button" to "a card with a mute button (Zoom's and Meet's own mute for those calls)".
- Modify: `docs/manual-checks.md`. Append "## The meeting's own mute (2026-10-23)" with the pending checks below.

- [ ] **Step 1: Run the whole suite.** Run `make test`. Expected: all pass.
- [ ] **Step 2: Commit** the probe and the docs with the message "keep the call-controls probe for debug builds, and describe the meeting's own mute".
- [ ] **Step 3: Install and relaunch.** Run `make install`, then `make stop`, then `open /Applications/Ledge.app`. This also replaces the debug build that is running now.
- [ ] **Step 4: Live check with the user:**
  - Zoom: the card's mute shows Zoom muted, in Zoom's own toolbar.
  - Zoom: muting in Zoom turns the island red.
  - Meet in Dia: the same two checks.
  - Meet with another tab in front: the system mute is used.
