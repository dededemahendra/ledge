# Calls that know the meeting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a call is a calendar meeting (Meet, Zoom, Teams, Webex or FaceTime link), the island shows the service's icon, the card shows the meeting's title and time left (red once over), the next meeting if it is within 10 minutes, and a camera glyph while the camera is on.

**Architecture:**
- A pure `CallMeetingMatcher` in `CallService` decides which calendar meeting a call is, from the shown app's bundle id, the time and plain `MeetingCandidate` values.
- `CallService.refresh` keeps the match for the call: it retries while unmatched, follows edits, moves on back to back, and exempts a hidden app. It also reads a `CameraSource`.
- `AppModel` maps `MeetingEvent`s to candidates and fills the card. NotchKit formats the time left and draws the card.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, CoreMediaIO, EventKit (through the existing `CalendarService`), swift-testing. macOS 27.

**Spec:** `docs/superpowers/specs/2026-10-22-call-meetings-design.md`. It builds on `docs/superpowers/specs/2026-10-22-call-island-design.md`.

## Global Constraints

- No new permission and no third-party logo in the bundle. Meet gets an SF Symbol `video.fill` in white on a tile coloured `#00A67E`.
- Matching window: `start - 10 min ≤ now < end`. Nearest start wins. A hidden app needs `start ≤ now`.
- Services by link host:
  - `meet.google.com` → Meet;
  - `zoom.us` and its subdomains → Zoom;
  - `teams.microsoft.com` or `teams.live.com` → Teams;
  - `webex.com` → Webex;
  - `facetime.apple.com` → FaceTime;
  - any other host → no match.
- Apps each service accepts, beyond the browsers:
  - Zoom: `us.zoom.xos`;
  - Teams: `com.microsoft.teams2`, `com.microsoft.teams`;
  - Webex: `Cisco-Systems.Spark`, `com.webex.meetingmanager`;
  - FaceTime: `com.apple.FaceTime`;
  - Meet: browsers only.
- Browsers:
  - `com.apple.Safari`
  - `com.google.Chrome`
  - `company.thebrowser.Browser`
  - `company.thebrowser.dia`
  - `com.microsoft.edgemac`
  - `org.mozilla.firefox`
  - `com.brave.Browser`
  - `com.operasoftware.Opera`
  - `com.vivaldi.Vivaldi`
  - `com.kagi.kagimacOS`
- Status copy:
  - under way: "12m left", "1h 5m left", "1h left" (whole minutes, rounded down);
  - "Ending now" under a minute;
  - over: "+3m", "+1h 2m", in red;
  - muted: "Muted · " (red) followed by the time copy;
  - unmatched: "On a call" / "Muted".
- Bottom row, the first that applies:
  1. "This mic can't be muted from here";
  2. "Next: <title> at <time>" (another `.event` starting within 10 minutes, not the matched one; `MeetingEvent.startTimeText()` for the time);
  3. the mic's name.

  A camera glyph (`video.fill`, 9 pt) goes at the left while a camera runs, and "Not a call" stays at the right.
- The card stays two rows; new information replaces lines.
- Candidates come from `calendar.upcoming(at:limit: 50, allowing: [.event])`, which already drops all-day and cancelled events. Don't log titles.
- Tests: `make test FILTER=<one name or file>`. A `|` in FILTER breaks the Makefile line, so run files one at a time.

## Review Focus

1. **Joining a meeting 15 minutes early:** the card starts as "On a call", then takes the title when the window opens. Pinned by `aCallJoinedEarlyMatchesWhenTheWindowOpens` (Task 3).
2. **A meeting extended mid-call:** the time left follows the new end instead of going falsely red. Pinned by `anExtendedMeetingUpdatesItsEnd` (Task 3).
3. **Leaving an overrunning meeting for the next one in the same app:** shows the new meeting, not the old one "+5m". Pinned by `backToBackMovesToTheNextOnceTheFirstHasEnded` (Task 3).
4. **No calendar access, or no events:** the call looks exactly as before. Pinned by `withNoMeetingsTheCallIsUnchanged` (Task 3).
5. **A very long meeting title (or emoji):** one line, truncated, and the card doesn't grow. Pinned by the headless render in Task 4, Step 6.

---

### Task 1: `CallMeetingMatcher`

**Files:**
- Create: `Sources/CallService/CallMeeting.swift`
- Test: `Tests/CallServiceTests/CallMeetingMatcherTests.swift`

**Interfaces:**
- Produces:
  - `public enum MeetingService: String, Sendable, Equatable, CaseIterable { case meet, zoom, teams, webex, facetime }`
  - `public struct MeetingCandidate: Sendable, Equatable { public let id: String; public let title: String; public let start: Date; public let end: Date; public let joinURL: URL?; public init(...) }`. A nil link never matches, but still counts for "Next".
  - `public struct CallMeeting: Sendable, Equatable { public let id: String; public let title: String; public let start: Date; public let end: Date; public let joinURL: URL; public let service: MeetingService }`
  - `public enum CallMeetingMatcher`, with:
    - `public static let lead: TimeInterval = 600`
    - `public static let nextWithin: TimeInterval = 600`
    - `public static func service(for url: URL) -> MeetingService?`
    - `public static func accepts(_ service: MeetingService, bundleID: String) -> Bool`
    - `public static func match(bundleID: String, at now: Date, in candidates: [MeetingCandidate], requireUnderWay: Bool = false) -> CallMeeting?`
    - `public static func next(after now: Date, in candidates: [MeetingCandidate], excluding id: String?) -> MeetingCandidate?`

- [ ] **Step 1: Write the failing tests.** Use `t0 = Date(timeIntervalSince1970: 100_000)` and the helper `meet(_ id:, start: Double, end: Double, url: "https://meet.google.com/abc")`, with times in minutes from t0.

```swift
@Test func meetInABrowserMatches()        // dia, now t0, meet 0…30 → .meet, title kept
@Test func meetInZoomsAppDoesNot()        // us.zoom.xos, meet 0…30 → nil
@Test func zoomMatchesInItsAppAndInABrowser()   // zoom.us/j/1 link: us.zoom.xos → .zoom; com.google.Chrome → .zoom
@Test func teamsMatchesInEitherTeamsApp()       // teams.microsoft.com link: com.microsoft.teams2 and com.microsoft.teams → .teams
@Test func theWindowOpensTenMinutesBefore()     // start 11 min after now → nil; 10 min → match
@Test func aCallStartingAtTheEndDoesNotMatch()  // now == end → nil
@Test func theNearestStartWins()                // A −50…+5 (min), B +2…+30 → B
@Test func noLinkOrAnotherServiceNeverMatches() // joinURL nil → nil; whereby.com → nil
@Test func aHiddenAppNeedsTheMeetingUnderWay()  // start +5 min, requireUnderWay: true → nil; start −1 min → match
@Test func nextIsWithinTenMinutesAndNeverTheMatchedOne()
    // B starts +9 → next == B; +11 → nil; excluding: B.id → nil; a link-less event counts
```

- [ ] **Step 2: Run them to make sure they fail.** Run `make test FILTER=CallMeetingMatcherTests`. Expected: compile failure.
- [ ] **Step 3: Implement** the types and `CallMeetingMatcher` with the tables in Global Constraints. A host matches when it equals the listed host or ends with `.` plus it. `match` keeps candidates with a service that accepts the bundle id and `start - lead ≤ now < end` (or `start ≤ now < end` when `requireUnderWay`), then picks the one with the smallest `abs(start - now)`.
- [ ] **Step 4: Run them to see them pass.** Run `make test FILTER=CallMeetingMatcherTests`. Expected: 10 passed.
- [ ] **Step 5: Commit** with the message "match a call to a calendar meeting: the service from the link, the apps it runs in, ten minutes early, nearest start".

### Task 2: `CameraWatcher`

**Files:**
- Create: `Sources/CallService/CameraWatcher.swift`

**Interfaces:**
- Produces:
  - `@MainActor public protocol CameraSource: AnyObject { var isCameraOn: Bool { get }; func refresh() }`
  - `@MainActor final class CameraWatcher: CameraSource`. On `refresh()` it reads `kCMIOHardwarePropertyDevices` on `kCMIOObjectSystemObject`, then `kCMIODevicePropertyDeviceIsRunningSomewhere` on each device. `isCameraOn` is true when any is running.

- [ ] **Step 1: Write a throwaway probe** in the scratchpad that prints each device's running flag every second. Run it while turning the camera on and off (Photo Booth, or the user's Meet). Expected: no prompt, and the flag follows the camera. If a prompt appears, stop and report.
- [ ] **Step 2: Implement `CameraWatcher`.** It reads only and has no listeners; `CallService` calls `refresh()` each tick while live.
- [ ] **Step 3: Build.** Run `swift build`. Expected: success, no warnings in the file.
- [ ] **Step 4: Commit** with the message "read whether a camera is running, for the call card".

### Task 3: `CallService` knows the meeting

**Files:**
- Modify: `Sources/CallService/CallService.swift`
- Test: `Tests/CallServiceTests/CallServiceTests.swift`

**Interfaces:**
- Consumes: `CallMeetingMatcher`, `MeetingCandidate`, `CallMeeting` (Task 1); `CameraSource` (Task 2).
- Produces:
  - `CallUpdate` gains `public let meeting: CallMeeting?` and `public let isCameraOn: Bool`. Init parameters default to `nil` and `false`, so existing call sites compile.
  - `CallService.init` gains `camera: CameraSource? = nil`; nil means a `CameraWatcher()`.
  - `public func refresh(at now: Date, hidden: Set<String>, meetings: [MeetingCandidate] = []) -> CallUpdate`

- [ ] **Step 1: Write the failing tests.**
  - Extend the test `Rig` with a `FakeCamera: CameraSource` (`var isCameraOn = false; func refresh() {}`).
  - Extend `refresh(from:to:hidden:)` to `refresh(from:to:hidden:meetings:)`.
  - Add a Chrome fixture at PID 300 (`com.google.Chrome`) to the rig's lookup.
  - Use `meet(...)` candidates as in Task 1.

```swift
@MainActor @Test func withNoMeetingsTheCallIsUnchanged()          // live Zoom, meetings [] → meeting == nil
@MainActor @Test func aMatchSticksPastTheEnd()                    // Chrome live in meet 0…30; at 35 min → meeting.id == "m"
@MainActor @Test func aCallJoinedEarlyMatchesWhenTheWindowOpens() // Chrome live from −15 min, meet 0…30: at −11 nil; at −10 → "m"
@MainActor @Test func backToBackMovesToTheNextOnceTheFirstHasEnded()
    // A 0…30, B 30…60, Chrome live from 0: at 29 → A; at 31 → B
@MainActor @Test func whileTheFirstIsUnderWayTheNextNeverTakesOver()
    // A 0…40, B 30…60: at 35 → A
@MainActor @Test func anExtendedMeetingUpdatesItsEnd()
    // matched A 0…30; candidates now A' (same link and title, new id) 0…45 → meeting.end == t0+45m
@MainActor @Test func aDeletedMeetingKeepsItsLastCopy()           // matched A; then meetings [] → meeting still A
@MainActor @Test func aHandOverMatchesAgain()                     // Zoom (Zoom link) then Chrome (Meet link) → .zoom then .meet
@MainActor @Test func aHiddenBrowserShowsOnceAMeetIsUnderWay()
    // Chrome hidden; meet starts +5: .idle until start; live from start; with no meetings stays .idle
@MainActor @Test func aHiddenBrowserStaysThroughTheMeetingsEnd()  // hidden Chrome live in meet 0…30 → still live at 33
@MainActor @Test func theCameraComesThrough()                     // FakeCamera.isCameraOn = true, live → update.isCameraOn
```

- [ ] **Step 2: Run them to make sure they fail.** Run `make test FILTER=CallServiceTests`. Expected: compile failure on `meetings:` and `FakeCamera`.
- [ ] **Step 3: Implement the refresh rules** from the spec's "Matching a call to a meeting" and "Hidden apps" sections. State is `matched: CallMeeting?`, `matchedApp: String?`, `exemptApp: String?`, all cleared whenever the state isn't `.live`. Order within `refresh`:
  1. Compute the exempt set for hidden holders. An app is exempt if it is the kept `exemptApp`, or if `match(requireUnderWay: true)` finds a meeting for it.
  2. Run the tracker with `hidden` minus that set.
  3. While live, update `matched`:
     - if the shown app changed, match from scratch;
     - else if unmatched, retry;
     - else re-read the matched meeting by `joinURL` and `title`, and if it has ended and `match` finds a different candidate, switch to it.
  4. Read the camera only while live.
- [ ] **Step 4: Run the tests to see them pass.** Run `make test FILTER=CallServiceTests`. Expected: every CallService test passes, the earlier 46 included.
- [ ] **Step 5: Commit** with the message "keep a call's meeting: retry until its window opens, follow edits, move on back to back, and show a hidden browser during its meeting".

### Task 4: The card shows the meeting

**Files:**
- Modify: `Sources/NotchKit/CallPanel.swift`. `CallPanelData` gains `meetingTitle: String? = nil`, `meetingEnd: Date? = nil`, `isCameraOn: Bool = false` and `nextMeeting: String? = nil`, all defaulted in the init. There is no service field: the icon PNG already carries the service, so the spec's `service` mirror isn't needed.
- Create: `Sources/NotchKit/CallMeetingText.swift`
- Create: `Sources/NotchKit/CallTile.swift`
- Modify: `Sources/NotchKit/CallPanelView.swift`
- Test: `Tests/NotchKitTests/CallMeetingTextTests.swift`

**Interfaces:**
- Produces:
  - `public enum CallMeetingText { public static func timeLeft(end: Date, now: Date) -> (text: String, isOver: Bool) }`
  - `public enum CallTile { public static func png(symbol: String, color: NSColor, side: CGFloat = 64) -> Data? }`, which draws a rounded tile (corner radius 22 % of the side) with the symbol in white.

- [ ] **Step 1: Write the failing tests:**

```swift
@Test func timeLeftInMinutesThenHours()   // end −12m30s → ("12m left", false); −65m → ("1h 5m left", false); −60m → ("1h left", false)
@Test func underAMinuteIsEndingNow()      // end −30 s → ("Ending now", false)
@Test func overIsAPlusInRed()             // end +3m → ("+3m", true); +62m → ("+1h 2m", true); +10 s → ("+1m", true)
@Test func aTileIsASquarePNG()            // CallTile.png(symbol: "video.fill", color: .systemGreen) decodes to 64×64
```

- [ ] **Step 2: Run them to make sure they fail.** Run `make test FILTER=CallMeetingTextTests`. Expected: compile failure.
- [ ] **Step 3: Implement** `CallMeetingText.timeLeft` and `CallTile.png`. Over, the minutes are `max(1, floor(over / 60))`.
- [ ] **Step 4: Run them to see them pass.** Run `make test FILTER=CallMeetingTextTests`. Expected: 4 passed.
- [ ] **Step 5: Update `CallPanelView`:**
  - Name line: `meetingTitle ?? appName`, one line, truncated at the tail.
  - Status line: with `meetingEnd`, inside the existing `TimelineView`, use `CallMeetingText.timeLeft`. Prefix "Muted · " in red when muted, and colour the time red when over. Without `meetingEnd`, show today's "On a call" / "Muted".
  - Bottom-row left: an optional camera glyph, then the first applicable of the unmutable note, `"Next: \(nextMeeting)"`, or the mic's name.
- [ ] **Step 6: Check renders headlessly.** Write a temporary `ImageRenderer` test, not committed, at `NotchMetrics.canvasSize` and scale 4, for:
  - (a) a matched Meet with a Meet tile icon, "Design review", 12 minutes left, the camera on, and "Next: 1:1 at 15:00";
  - (b) over by 3 minutes and muted;
  - (c) a 90-character title with an emoji.

  Expected: (a) and (b) read as specified; (c) is one truncated line with the card's height unchanged (`NotchMetrics.callCard`). Delete the test afterwards.
- [ ] **Step 7: Run the whole suite.** Run `make test`. Expected: all pass.
- [ ] **Step 8: Commit** with the message "show the meeting on the call card: its title, the time left and red when over, the next meeting, the camera, and a tile for meet".

### Task 5: Wire it into `AppModel`

**Files:**
- Modify: `Sources/Ledge/AppModel.swift`

**Interfaces:**
- Consumes: `CallService.refresh(at:hidden:meetings:)`, `CallUpdate.meeting` and `isCameraOn` (Task 3); `CallPanelData`'s new fields and `CallTile` (Task 4); `CallMeetingMatcher.next(after:in:excluding:)` (Task 1); `MeetingEvent.startTimeText()`.

- [ ] **Step 1: Candidates.** In `refreshCall()`:
  - If `calendar.availability.isAvailable`, build `meetingCandidates` from `calendar.upcoming(at: now, limit: 50, allowing: [.event])`, mapping each event to `MeetingCandidate(id:title:start:end:joinURL:)`. Otherwise use `[]`.
  - Pass them to `call.refresh`.
  - Ledger it as a ruling: candidates are used whatever the "Calendar events" blip switch says, since that switch is about blips.
- [ ] **Step 2: Service icon.** Write `serviceIcon(_ service: MeetingService) -> Data?`, cached per service:
  - the first installed app among the service's own apps (as in Global Constraints) via `NSWorkspace`, the same 64×64 PNG path as `callIcon(for:)`;
  - otherwise `CallTile.png(symbol: "video.fill", color:)`. The colour is `#00A67E` for Meet, and the builder's choice for the others.

  When matched, use it for the record's `artwork` and the panel's `icon`.
- [ ] **Step 3: Panel fields.**
  - `meetingTitle` and `meetingEnd` come from `update.meeting`; `isCameraOn` comes from `update`.
  - `nextMeeting` is `"\(event.title) at \(event.startTimeText())"` for the event that `CallMeetingMatcher.next(after: now, in: candidates, excluding: update.meeting?.id)` names, looked up by id.

  The record's title stays "On a call · <app>", which nothing shows; no titles are logged.
- [ ] **Step 4: Build and run the suite.** Run `make test`. Expected: all pass.
- [ ] **Step 5: Install and relaunch.** Run `make install`, then `make stop`, then `open /Applications/Ledge.app`. Signing may wait on the keychain prompt; tell the user if it does.
- [ ] **Step 6: Live check with the user:**
  - a scheduled Meet in Dia shows the green Meet tile and the event title;
  - the time left counts down;
  - "Next:" appears when another meeting is within 10 minutes;
  - the camera glyph follows the camera.
- [ ] **Step 7: Commit** with the message "know the meeting on a call: calendar meetings to the call service, the service's icon, and the title, time left, next meeting and camera on the card".

### Task 6: Docs

**Files:**
- Modify: `README.md`. On the call row, append "; a calendar meeting shows its service, its title and the time left, with the next meeting and the camera on the card".
- Modify: `docs/manual-checks.md`. Append "## Calls that know the meeting (2026-10-22)" with the spec's pending list, marking what the user confirmed in Task 5.

- [ ] **Step 1: Make both edits.**
- [ ] **Step 2: Commit** with the message "describe calls that know the meeting in the readme and the manual checks".
