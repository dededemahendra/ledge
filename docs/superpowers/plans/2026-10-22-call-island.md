# Calls on the island Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** While any regular app holds the microphone, the island shows that app's icon and a green running clock, with a hover card that mutes every running mic and can mark the app "Not a call". When the call ends, the island shows a red hang-up glyph and the call's length for 3 s.

**Architecture:** A new `CallService` library (built like the other services: thin CoreAudio shells on the main actor, judgement in pure value types with injected lookups) reports who holds the mic, tracks the call with 2 s grace in both directions, and plans mute and restore. `AppModel` polls it from the existing 0.25 s tick and turns it into a sticky `ActivityKind.call` record and a `CallPanelData` card. NotchKit gains the call ear branch, the `.call` panel and two intents.

**Tech Stack:** Swift 6 (strict concurrency), SwiftPM, SwiftUI, CoreAudio (process objects, input device mute/volume), AppKit (`NSRunningApplication`, `NSWorkspace`), swift-testing. macOS 27.

**Spec:** `docs/superpowers/specs/2026-10-22-call-island-design.md`

## Global Constraints

- Platform floor: macOS 27 (`platforms: [.macOS("27.0")]`); no new third-party dependencies.
- No permission prompts of any kind; no `NSMicrophoneUsageDescription` is added.
- A holder counts only if it resolves to a regular app (`activationPolicy == .regular`); Ledge's own PID never counts.
- Start grace 2 s, end grace 2 s; the clock counts from the first take.
- `ActivityKind.call`: priority 30, sticky (`ttl: nil`); the ended moment is the same kind re-inserted with `ttl: 3`. Record id `"call"`.
- Clock text: `TimerText.format(seconds:)` ("m:ss", then "h:mm" from an hour).
- Colours: running time `.positive` (green); muted glyph `mic.slash.fill` red; ended glyph `phone.down.fill` red with the final length in white.
- Click while live: `ledge://call`, which activates the app by bundle id through LaunchServices, else by PID.
- Settings: `showsCalls` on by default; `hiddenCallApps` empty by default. Row copy: title "Calls", detail "The app and how long, while the mic is on". Card button copy: "Not a call". Unmutable copy: "This mic can't be muted from here".
- Every mute Ledge applies is undone when the call ends, the app is hidden, Calls is switched off, or Ledge quits. A saved record restores it on the next launch after a crash.
- Never log app names or call times.
- Run tests with `make test` or `make test FILTER=<name>` (the Makefile passes the testing macro plugin path).

## Review Focus

1. **A mic switch mid-call** (AirPods connecting): the holder drops for under 2 s, then a new device starts running. The call and clock carry on, and if muted, the new device is muted too. Pinned by `aShortDropKeepsTheCallAndTheClock` (Task 3) and `aDeviceThatStartsWhileMutedIsMuted` (Task 5).
2. **Ledge relaunched while muted** (the user's own build-and-relaunch loop): the next launch restores the mic, unless the user changed that device in the meantime. Pinned by `aSavedRecordIsRestoredOnStart` and `aSavedRecordLeavesADeviceTheUserChanged` (Task 5).
3. **Meet in Safari:** the holder is a WebKit process whose parent is launchd. It must resolve to Safari through the responsible process. Pinned by `aWebKitHelperResolvesThroughItsResponsibleProcess` (Task 2).
4. **The call app quitting or crashing mid-call:** its process vanishes from the list. That is a release, so the ended moment shows with the length up to the last time the mic was seen. Pinned by `aHolderVanishingEndsTheCallWithItsLength` (Task 3).
5. **Switching Calls off, or "Not a call", while muted:** the mic is unmuted and there is no ended moment. Pinned by `stoppingRestoresLedgesMute` and `hidingWhileMutedRestores` (Task 5) and `hidingTheOnlyAppEndsWithoutAnEndedMoment` (Task 3).

---

### Task 1: Verify the platform assumptions on this Mac (no commit)

The spec's "Verify first". Throwaway; nothing is committed. The user takes part in it.

**Files:**
- Create (scratch, outside the repo): `<scratchpad>/micprobe/main.swift`

- [ ] **Step 1: Write a probe** that every second prints, for each object in `kAudioHardwarePropertyProcessObjectList`: the PID, `kAudioProcessPropertyBundleID`, `kAudioProcessPropertyIsRunningInput`, `responsibility_get_pid_responsible_for_pid(pid)` (declare with `@_silgen_name`), the parent PID (`proc_pidinfo` with `PROC_PIDTBSDINFO`), and whether `NSRunningApplication(processIdentifier:)` has `activationPolicy == .regular`. For each input device, it also prints the UID, the name, `kAudioDevicePropertyDeviceIsRunningSomewhere`, and whether `kAudioDevicePropertyMute` and `kAudioDevicePropertyVolumeScalar` (input scope, main element) are settable.
- [ ] **Step 2: Run it** with `swiftc -O main.swift -o micprobe && ./micprobe`, and ask the user to:
  - (a) make a FaceTime call, or open Voice Memos and record;
  - (b) join a Meet in Safari;
  - (c) join a Meet in Chrome;
  - (d) watch for any permission prompt and for the orange mic dot appearing when no app is using the mic.

  Expected: no prompt. The holder resolves to FaceTime or Voice Memos, Safari and Chrome respectively. The orange dot appears only while the call app holds the mic.
- [ ] **Step 3: Set and unset input mute** on the built-in mic with the probe, while Voice Memos records. Expected: the recording goes silent, there is no prompt, and the state reads back.
- [ ] **Step 4: Gate.** If any expectation fails, stop and report to the user before Task 2, with what failed and the probe's output. The design rests on these.

### Task 2: `CallService` target and the app resolver

**Files:**
- Modify: `Package.swift`
  - add `.target(name: "CallService", dependencies: ["ActivityKit"])`;
  - add `.testTarget(name: "CallServiceTests", dependencies: ["CallService"])`;
  - add `"CallService"` to Ledge's dependencies.
- Create: `Sources/CallService/CallApp.swift`
- Test: `Tests/CallServiceTests/CallAppTests.swift`

**Interfaces:**
- Produces:
  - `public struct CallAppInfo: Sendable, Equatable, Hashable { public let bundleID: String; public let name: String; public let pid: pid_t }`
  - `@MainActor public struct ProcessLookup { public var regularApp: (pid_t) -> CallAppInfo?; public var responsiblePID: (pid_t) -> pid_t?; public var parentPID: (pid_t) -> pid_t?; public static let live: ProcessLookup }`
  - `@MainActor public enum CallApp { public static func resolve(_ pid: pid_t, ownPID: pid_t, lookup: ProcessLookup) -> CallAppInfo? }`

- [ ] **Step 1: Write the failing tests** in `CallAppTests.swift`, using a fake `ProcessLookup` built from dictionaries:

```swift
@MainActor @Test func aRegularAppIsItself()            // regularApp[100] = Zoom → resolve(100) == Zoom
@MainActor @Test func aWebKitHelperResolvesThroughItsResponsibleProcess()
    // 200 not regular, parent 1, responsible 150, regularApp[150] = Safari → Safari
@MainActor @Test func aHelperResolvesToItsRegularParent()
    // 300 not regular, responsible nil, parent 301 (not regular), parent of 301 = 302 = Chrome → Chrome
@MainActor @Test func aDaemonWithNoRegularAncestorIsNil()   // 400 → parent 1, nothing regular → nil
@MainActor @Test func ledgeItselfIsNil()               // resolve(own, ownPID: own) == nil even if regular
@MainActor @Test func theWalkStopsAfterTenHops()       // a parent cycle 500 → 501 → 500 … → nil, terminates
```

- [ ] **Step 2: Run them to make sure they fail.** Run `make test FILTER=CallAppTests`. Expected: compile failure, because `CallApp` is not defined.
- [ ] **Step 3: Implement `CallApp.resolve`.** The order is:
  1. own PID → nil;
  2. the PID itself if it is a regular app;
  3. its responsible PID (when different, and not Ledge) if that is regular;
  4. otherwise walk parents (at most 10 hops, stopping at PID ≤ 1) to the first regular app;
  5. otherwise nil.

  `ProcessLookup.live` uses:
  - `NSRunningApplication(processIdentifier:)`, where regular means `activationPolicy == .regular` and the bundle id and localized name are non-nil;
  - `responsibility_get_pid_responsible_for_pid` via `@_silgen_name`, where a result ≤ 0 means nil;
  - `proc_pidinfo(PROC_PIDTBSDINFO)` for `pbi_ppid`.
- [ ] **Step 4: Run the tests to see them pass.** Run `make test FILTER=CallAppTests`. Expected: 6 passed.
- [ ] **Step 5: Commit.** Run `git add Package.swift Sources/CallService Tests/CallServiceTests`, then commit with the message "resolve the app on the mic: itself, its responsible app, or its nearest regular parent, never ledge".

### Task 3: `CallTracker`

**Files:**
- Create: `Sources/CallService/CallTracker.swift`
- Test: `Tests/CallServiceTests/CallTrackerTests.swift`

**Interfaces:**
- Consumes: `CallAppInfo` (Task 2).
- Produces:
  - `public struct CallTracker: Sendable { public static let startGrace: TimeInterval = 2; public static let endGrace: TimeInterval = 2; public init() }`
  - `public enum CallState: Sendable, Equatable { case idle; case live(app: CallAppInfo, since: Date); case ended(app: CallAppInfo, length: TimeInterval) }`
  - `public mutating func update(now: Date, holders: [CallAppInfo], hidden: Set<String>) -> CallState`. `.ended` is returned on exactly one call; the next update returns `.idle` unless a new call has started.

- [ ] **Step 1: Write the failing tests.** `t0 = Date(timeIntervalSince1970: 1_000)`, Zoom and FaceTime are fixtures, and the tick is 0.25 s.

```swift
@Test func aHoldUnderTwoSecondsIsNoCall()       // Zoom held t0…t0+1.75, released; every state .idle, no .ended
@Test func aCallStartsAfterTwoSecondsCountingFromTheFirstTake()
    // Zoom held from t0; at t0+1.75 .idle; at t0+2 == .live(app: zoom, since: t0)
@Test func aShortDropKeepsTheCallAndTheClock()  // live; holders [] for 1.0 s; then Zoom again → still .live(zoom, since: t0)
@Test func aTwoSecondDropEndsWithTheLengthUpToTheLastHold()
    // live from t0, last held at t0+60, [] afterwards: .live until t0+62, then exactly one .ended(zoom, length: 60), then .idle
@Test func aHolderVanishingEndsTheCallWithItsLength()  // same as above, the holders list simply stops containing Zoom
@Test func whenTheFirstAppLeavesTheNextCarriesOnWithoutARestart()
    // Zoom from t0, FaceTime from t0+10; Zoom gone at t0+30 → after grace .live(app: facetime, since: t0), no .ended
@Test func hidingTheOnlyAppEndsWithoutAnEndedMoment()   // live Zoom; hidden = ["us.zoom.xos"] → .idle at once, never .ended
@Test func hidingTheShownAppHandsOverToAnotherHolder()  // Zoom + FaceTime live; hide Zoom → .live(app: facetime, since: t0)
@Test func unhidingMidHoldShowsTheCallFromItsFirstTake()
    // Zoom hidden and held from t0; unhide at t0+30 → .live(zoom, since: t0) on that update
```

- [ ] **Step 2: Run them to make sure they fail.** Run `make test FILTER=CallTrackerTests`. Expected: compile failure.
- [ ] **Step 3: Implement `update`.** Keep `firstTake` and `lastSeen` per bundle id for every holder, hidden ones included, so unhiding counts from the first take. Drop an entry once `now - lastSeen > endGrace`.
  - The shown app is the non-hidden entry with the earliest `firstTake` among those within grace.
  - A call starts when such an entry is holding now and has `now - firstTake >= startGrace`.
  - `since` is fixed at that app's `firstTake` for the whole call, across hand-overs.
  - When no non-hidden entry is left:
    - if the last shown app is hidden and still within grace, return `.idle`;
    - otherwise return `.ended` once, with `length = lastSeen(shown) - since`.
- [ ] **Step 4: Run the tests to see them pass.** Run `make test FILTER=CallTrackerTests`. Expected: 9 passed.
- [ ] **Step 5: Commit** `Sources/CallService/CallTracker.swift` and `Tests/CallServiceTests/CallTrackerTests.swift` with the message "track a call: two seconds to start and to end, the clock from the first take, hand over between apps, and hiding ends it quietly".

### Task 4: The mute planner

**Files:**
- Create: `Sources/CallService/InputMutePlan.swift`
- Test: `Tests/CallServiceTests/InputMutePlanTests.swift`

**Interfaces:**
- Produces:
  - `public struct InputDeviceState: Sendable, Equatable { public let uid: String; public let name: String; public let isRunning: Bool; public let canMute: Bool; public let isMuted: Bool; public let canSetVolume: Bool; public let volume: Float32 }`
  - `public struct MuteChange: Codable, Sendable, Equatable { public enum Kind: Codable, Sendable, Equatable { case mute; case volume(previous: Float32) }; public let uid: String; public let kind: Kind }`
  - `public enum MuteAction: Sendable, Equatable { case setMute(uid: String, Bool); case setVolume(uid: String, Float32) }`
  - `public enum InputMutePlan`, with these static functions:
    - `mute(_ devices: [InputDeviceState], changes: [MuteChange]) -> (actions: [MuteAction], changes: [MuteChange])`: running devices not already muted get mute where `canMute`, else volume 0 where `canSetVolume` (recording the previous volume). Returns the merged changes.
    - `unmute(_ devices: [InputDeviceState], changes: [MuteChange]) -> [MuteAction]`: every running device with `isMuted` gets `setMute(false)`, whoever muted it. Every recorded volume change gets its previous value back.
    - `restore(_ devices: [InputDeviceState], changes: [MuteChange]) -> [MuteAction]`: only Ledge's changes, and only on devices still in Ledge's state (muted for `.mute`, volume 0 for `.volume`).
    - `isMuted(_ devices: [InputDeviceState], changes: [MuteChange]) -> Bool`: true when there is at least one running device and every running device is muted, either by its flag or by a recorded volume change.
    - `canMute(_ devices: [InputDeviceState]) -> Bool`: some running device has `canMute || canSetVolume`.
    - `micName(_ devices: [InputDeviceState]) -> String?`: the one running device's name, "2 mics" (the count) when several are running, nil when none are.

- [ ] **Step 1: Write the failing tests:**

```swift
@Test func muteUsesTheMuteFlagWhereItCan()          // canMute → [.setMute(uid, true)], changes [.mute]
@Test func muteFallsBackToVolumeZeroAndRemembersIt() // !canMute, canSetVolume, volume 0.7 → [.setVolume(uid, 0)], changes [.volume(previous: 0.7)]
@Test func aDeviceThatCanDoNeitherIsLeftAndReported() // → no actions; canMute(devices) == false
@Test func onlyRunningDevicesAreMuted()             // a non-running device gets no action
@Test func unmuteClearsAnOutsideMuteToo()           // device muted elsewhere (isMuted, no change recorded) → [.setMute(uid, false)]
@Test func restoreLeavesAnOutsideMuteAlone()        // same device, changes [] → restore == []
@Test func restorePutsBackExactlyWhatLedgeChanged() // changes [.mute(a), .volume(b, previous 0.7)], both still in Ledge state → [.setMute(a,false), .setVolume(b,0.7)]
@Test func restoreSkipsADeviceTheUserChangedSince() // .volume(b, 0.7) recorded but b's volume now 0.4 → no action for b
@Test func mutedMeansEveryRunningMicIsMuted()       // two running, one muted → false; both → true; none running → false
@Test func theMicNameIsOneNameOrACount()            // one running → its name; two → "2 mics"; none → nil
```

- [ ] **Step 2: Run them to make sure they fail.** Run `make test FILTER=InputMutePlanTests`. Expected: compile failure.
- [ ] **Step 3: Implement `InputMutePlan`** as pure functions on the values above.
- [ ] **Step 4: Run the tests to see them pass.** Run `make test FILTER=InputMutePlanTests`. Expected: 10 passed.
- [ ] **Step 5: Commit** both files with the message "plan mute and restore: the flag where it can, else volume zero remembered, unmute clears anyone's mute, restore only undoes ledge's".

### Task 5: The CoreAudio shells and `CallService`

**Files:**
- Create: `Sources/CallService/MicHolders.swift`. A `@MainActor` CoreAudio shell. It listens on the main queue (the `VolumeObserver` pattern, keeping each installed listener tuple for removal) to `kAudioHardwarePropertyProcessObjectList`, and to `kAudioProcessPropertyIsRunningInput` on each process object, re-listening when the list changes. `var holderPIDs: [pid_t]?` is nil when the list can't be read.
- Create: `Sources/CallService/InputDevices.swift`. `@MainActor public protocol InputDeviceIO { func states() -> [InputDeviceState]; func perform(_ actions: [MuteAction]) }`, plus `CoreAudioInputDevices: InputDeviceIO`. Input devices are those with input streams. Reads: UID, name, `kAudioDevicePropertyDeviceIsRunningSomewhere`, and mute and volume-scalar on the input scope, main element, with settability via `AudioObjectIsPropertySettable`. Writes use `AudioObjectSetPropertyData`, following `OutputDeviceCatalog.setDefaultOutput`.
- Create: `Sources/CallService/CallService.swift`
- Test: `Tests/CallServiceTests/CallServiceTests.swift`

**Interfaces:**
- Consumes: `CallApp`, `ProcessLookup` (Task 2); `CallTracker`, `CallState` (Task 3); `InputMutePlan`, `InputDeviceState`, `MuteChange`, `MuteAction` (Task 4); `ServiceAvailability` (ActivityKit).
- Produces:
  - `public struct CallUpdate: Sendable, Equatable { public let state: CallState; public let isMuted: Bool; public let canMute: Bool; public let micName: String? }`
  - `@MainActor public final class CallService`, with:
    - `public init(holders: (() -> [pid_t]?)? = nil, devices: InputDeviceIO = CoreAudioInputDevices(), lookup: ProcessLookup = .live, defaults: UserDefaults = .standard, ownPID: pid_t = getpid())`. A nil `holders` means the service owns a `MicHolders`, installing its listeners in `start()` and removing them in `stop()`. Tests pass a closure instead.
    - `public private(set) var availability: ServiceAvailability`
    - `public func start()`: idempotent; installs the listeners and restores a saved record.
    - `public func stop()`: removes the listeners and restores Ledge's mute.
    - `public func refresh(at now: Date, hidden: Set<String>) -> CallUpdate`
    - `public func toggleMute()`
  - The saved record key is `"callMuteChanges"` (a JSON `[MuteChange]`), written on every change and removed after a restore.

- [ ] **Step 1: Write the failing tests.** Use a `FakeDevices: InputDeviceIO` that applies actions to its states and records them, a fake holders closure, a fake lookup, and `UserDefaults(suiteName: UUID().uuidString)`.

```swift
@MainActor @Test func aCallShowsAfterTwoSecondsWithTheMicName()   // holders [zoomPID] from t0 → at t0+2 .live, micName "MacBook Pro Microphone"
@MainActor @Test func toggleMuteMutesAndReportsIt()               // live; toggleMute → device muted, next refresh isMuted == true
@MainActor @Test func aDeviceThatStartsWhileMutedIsMuted()        // muted; a second device becomes running → muted on the next refresh
@MainActor @Test func theCallEndingRestoresLedgesMute()           // muted; holders [] past grace → .ended and the device unmuted, record cleared
@MainActor @Test func hidingWhileMutedRestores()                  // muted; refresh with hidden [zoom] → .idle and unmuted
@MainActor @Test func stoppingRestoresLedgesMute()                // muted; stop() → unmuted, record cleared
@MainActor @Test func aSavedRecordIsRestoredOnStart()             // defaults hold [.mute(a)], device a muted → start() unmutes a, record removed
@MainActor @Test func aSavedRecordLeavesADeviceTheUserChanged()   // [.volume(b, 0.7)] saved but b now at 0.4 → start() leaves b, record removed
@MainActor @Test func anUnreadableProcessListIsUnavailable()      // holders returns nil → availability == .unavailable(reason: "can't read which apps use the microphone"), state .idle
```

- [ ] **Step 2: Run them to make sure they fail.** Run `make test FILTER=CallServiceTests`. Expected: compile failure.
- [ ] **Step 3: Implement `CallService`.** Each `refresh` does the following:
  1. Resolve the holder PIDs through `CallApp.resolve`, de-duplicated by bundle id, and run the tracker.
  2. While muted, re-apply `InputMutePlan.mute` so a device that newly starts running gets muted.
  3. On a transition out of `.live` (to `.idle` or `.ended`), apply `restore` and clear the mute request.
  4. Report `isMuted`, `canMute` and `micName` from the plan.

  `toggleMute` reads `isMuted`: if muted, it applies `unmute` and clears the changes; otherwise it applies `mute` and keeps the changes.
- [ ] **Step 4: Run the tests to see them pass.** Run `make test FILTER=CallServiceTests`. Expected: 9 passed.
- [ ] **Step 5: Commit** `Sources/CallService` and `Tests/CallServiceTests` with the message "watch the mic's holders and the input devices, and restore ledge's mute when a call ends, on stop, and after a crash".

### Task 6: `ActivityKind.call`

**Files:**
- Modify: `Sources/ActivityKit/ActivityKind.swift`. Add `case call` with a doc comment (sticky while the mic is on, over a Clock timer, under every blip), priority 30, `defaultTTL` nil.
- Test: `Tests/ActivityKitTests/ActivityQueueTests.swift`

- [ ] **Step 1: Write the failing test:**

```swift
@Test func aCallSitsUnderEveryBlipAndOverTimersAndMusic() {
    #expect(ActivityKind.call.priority == 30)
    #expect(ActivityKind.call.defaultTTL == nil)
    #expect(ActivityKind.call < .update && ActivityKind.call > .timer)
    #expect(ActivityKind.call > .media && ActivityKind.call > .liveActivity && ActivityKind.call > .githubRun)
}
```

- [ ] **Step 2: Run it to make sure it fails.** Run `make test FILTER=aCallSitsUnderEveryBlip`. Expected: compile failure.
- [ ] **Step 3: Add the case.** Fix any exhaustive `switch` over `ActivityKind` that the compiler flags.
- [ ] **Step 4: Run the test to see it pass**, along with the existing `everyKindHasADistinctPriority`. Run `make test FILTER=ActivityQueueTests`. Expected: all pass.
- [ ] **Step 5: Commit** with the message "add the call kind: sticky, under every blip, over timers and music".

### Task 7: NotchKit model: the call id, the card's data, the panel and the intents

**Files:**
- Create: `Sources/NotchKit/CallPanel.swift`
- Modify: `Sources/NotchKit/NotchController.swift`
- Modify: `Sources/NotchKit/NotchPresenter.swift`
- Test: `Tests/NotchKitTests/NotchControllerTests.swift`

**Interfaces:**
- Produces:
  - `public struct CallPanelData: Sendable, Equatable { public let appName: String; public let icon: Data?; public let since: Date; public let isMuted: Bool; public let canMute: Bool; public let micName: String? }`, with a memberwise public init.
  - On `NotchController`:
    - `public static let callActivityID = "call"`
    - `Panel.call`
    - `public private(set) var callPanel: CallPanelData?` and `public func setCallPanel(_:)`, which drops back to `.media` when the data goes, like `setGitHubPanel`.
    - `public private(set) var callIconImage: NSImage?`, decoded once in `setActivities` when the leading call record's `artwork` changes, like `githubAvatarImage`.
    - `public var isCallLeading: Bool`
  - On `NotchIntent`: `case toggleMute` and `case hideCallApp`.
  - On `NotchPresenter`: `public func setCallPanel(_ data: CallPanelData?)`, which forwards and resyncs the window.
  - The call id joins `leadingBlipKey`'s list, so the ended moment pulses.
  - `availablePanels` lists `.call` first when `callPanel != nil`.
  - `setHovered(true)` picks `.call` when `isCallLeading && callPanel != nil && !isPinnedOpen`.
  - `recomputeState` expands when hovered, `panel == .call` and `callPanel != nil`.

- [ ] **Step 1: Write the failing tests** (in the style of `hoveringTheRunningItemOpensTheGitHubPanel`):

```swift
@MainActor @Test func hoveringTheCallOpensItsCard()
    // setActivities([call display]), setCallPanel(sample); setHovered(true) → panel == .call, state == .expanded
@MainActor @Test func theCallCardGoesWithItsData()
    // open; setCallPanel(nil) → panel == .media, state == .activity
@MainActor @Test func withoutCardDataHoveringTheCallStaysAnItem()    // no setCallPanel → state == .activity
@MainActor @Test func whileLockedTheCallsButtonsDoNothing()
    // setLocked(true); emit(.toggleMute), emit(.hideCallApp) → the intent handler is never called
@MainActor @Test func theCallsIconIsDecodedOnce()
    // the same artwork twice → callIconImage is the identical instance (===)
```

- [ ] **Step 2: Run them to make sure they fail.** Run `make test FILTER="hoveringTheCallOpensItsCard|theCallCardGoesWithItsData|withoutCardDataHoveringTheCallStaysAnItem|whileLockedTheCallsButtonsDoNothing|theCallsIconIsDecodedOnce"`. Expected: compile failure.
- [ ] **Step 3: Implement** the interface above in the files listed.
- [ ] **Step 4: Run the tests to see them pass.** Run `make test FILTER=NotchControllerTests`. Expected: all pass.
- [ ] **Step 5: Commit** with the message "give the island a call: its id, its card's data, the call panel on hover, mute and hide intents, and its icon decoded once".

### Task 8: NotchKit views: the ears and the card

**Files:**
- Create: `Sources/NotchKit/CallPanelView.swift`
- Modify: `Sources/NotchKit/NotchRootView.swift`:
  - `leadingEar`: a call branch before the generic artwork branch.
  - The trailing ear's `isTicking`: add the call id.
  - `detailRow`: a `.call` branch like the GitHub one.

**Interfaces:**
- Consumes: `CallPanelData`, `callIconImage`, `callActivityID`, `NotchIntent.toggleMute` and `.hideCallApp` (Task 7).

- [ ] **Step 1: Leading ear.** When the call leads:
  - if `symbolName` is `mic.slash.fill` or `phone.down.fill`, draw that symbol at 13 pt medium in `systemRed`;
  - else if `callIconImage` exists, draw it at 20 × 20 pt;
  - else draw `mic.fill` in `systemGreen`.

  Swap with the ear's existing `.contentTransition(.symbolEffect(.replace.downUp))` and text animation.
- [ ] **Step 2: Trailing ear.** Add `NotchController.callActivityID` to `isTicking`, so the clock takes the record's tint (green live, white ended, because the ended record has no tint) and doesn't bump every second.
- [ ] **Step 3: `CallPanelView(data:contentColor:reduceMotion:emit:)`.** Lay out, top to bottom:
  1. The app icon (28 pt) and `appName`, a button emitting `.open(URL(string: "ledge://call")!)`.
  2. The time, large (28 pt semibold, monospaced digits), from `TimelineView(.periodic(from: .now, by: 1))` with `GitHubPanelView.clock(context.date.timeIntervalSince(data.since))`.
  3. A round 44 pt mute button emitting `.toggleMute`: `mic.fill` on white at 15 % opacity, or `mic.slash.fill` on `systemRed` when `isMuted`. When `!canMute` it is disabled, with the caption "This mic can't be muted from here".
  4. `micName` in 11 pt secondary.
  5. A plain text button "Not a call" at the foot, 11 pt secondary, emitting `.hideCallApp`.

  Use the same `reveal` stagger as `GitHubPanelView`, and wire it into `detailRow` with `.id("call")` and `panelTransition`.
- [ ] **Step 4: Check the renders headlessly.** Write a temporary test (not committed) that renders `NotchRootView` at `NotchMetrics.canvasSize` with `ImageRenderer` at scale 4, without setting `NotchRenderTestHook`, for four cases:
  - (a) live with an icon artwork at "12:04";
  - (b) muted;
  - (c) ended at "12:04" with no tint;
  - (d) hovered with `CallPanelData`.

  Run it with `make test FILTER=<name>`, crop the top of each PNG with ffmpeg, and look. Expected: (a) the icon left and a green "12:04" right; (b) a red crossed-out mic and a green clock; (c) a red hang-up and a white "12:04"; (d) the card under the ears, with icon, name, clock, button, mic name and "Not a call". Delete the temporary test.
- [ ] **Step 5: Run the whole suite.** Run `make test`. Expected: all pass, including `NotchRenderTests`.
- [ ] **Step 6: Commit** with the message "draw the call: the app's icon and a green clock, a red crossed-out mic when muted, a red hang-up and the length when it ends, and its card".

### Task 9: Settings: the switch, the hidden list, the preview

**Files:**
- Modify: `Sources/LedgeSettings/AppSettings.swift`:
  - keys `showsCalls` and `hiddenCallApps`;
  - `public var showsCalls: Bool` (default true);
  - `public var hiddenCallApps: [String]` (default `[]`, saved as an array);
  - `public func hideCallApp(_ bundleID: String)` (appends if absent) and `public func unhideCallApp(_ bundleID: String)`.
- Modify: `Sources/SettingsKit/PreviewScene.swift`: `case call`, titled "Calls", with `isOn` as `settings.showsCalls`.
- Modify: `Sources/SettingsKit/PreviewContent.swift`: `PreviewSample.call`, a call display at "12:04" with tint `.positive`. Its artwork is FaceTime's icon (`NSWorkspace.urlForApplication(withBundleIdentifier: "com.apple.FaceTime")`, then `icon(forFile:)`, encoded to PNG), else nil.
- Modify: `Sources/SettingsKit/PreviewStage.swift`: `apply` handles `.call` with `PreviewSample.call`, captioned as a sample.
- Modify: `Sources/Ledge/SettingsPanes.swift`, under "What happens on the Mac":
  - `row("Calls", "The app and how long, while the mic is on", "phone.fill", .systemGreen, \.showsCalls, .call)`;
  - below it, while `hiddenCallApps` is non-empty, a "Not calls" list: each app's icon via the existing `AppIcon` and its name (from `NSWorkspace` or the bundle id), with a minus button calling `unhideCallApp`.
- Test: `Tests/LedgeSettingsTests/AppSettingsTests.swift`, `Tests/SettingsKitTests/PreviewStageTests.swift`

- [ ] **Step 1: Write the failing tests:**

```swift
// AppSettingsTests
@MainActor @Test func callsAreOnAndNothingIsHiddenByDefault()   // fresh suite → showsCalls == true, hiddenCallApps == []
@MainActor @Test func hidingACallAppSavesOnceAndUnhidingRemovesIt()
    // hideCallApp("us.zoom.xos") twice → hiddenCallApps == ["us.zoom.xos"]; a new AppSettings on the same suite reads it; unhide → []
```

Also extend `everythingIsOnByDefaultAsTheAppBehavedBeforeSettings` with `showsCalls`. `everySceneShowsSomethingAndIsCaptioned` covers `.call` through `allCases`.
- [ ] **Step 2: Run them to make sure they fail.** Run `make test FILTER="AppSettingsTests|PreviewStageTests"`. Expected: compile failure.
- [ ] **Step 3: Implement** the settings, the scene, the sample, the stage case and the Island rows above.
- [ ] **Step 4: Run the tests to see them pass.** Run `make test FILTER="AppSettingsTests|PreviewStageTests"`. Expected: all pass.
- [ ] **Step 5: Commit** with the message "add calls to settings: the switch, its preview, and the not-calls list to bring an app back".

### Task 10: Wire it into `AppModel`

**Files:**
- Modify: `Sources/Ledge/AppModel.swift`
- Modify: `Sources/Ledge/AppDelegate.swift`, only if `model?.stop()` doesn't already reach the new `call.stop()`.

**Interfaces:**
- Consumes: `CallService`, `CallUpdate` and `CallState` (Task 5); `ActivityKind.call` (Task 6); `CallPanelData`, `callActivityID`, the intents and `presenter.setCallPanel` (Task 7); `settings.showsCalls`, `hiddenCallApps` and `hideCallApp` (Task 9); `TimerText.format` (TimerService).

- [ ] **Step 1: Owning and starting the service.**
  - Add `private let call = CallService()`.
  - In `applySettings`, `call.start()` when `settings.showsCalls`. Otherwise call `call.stop()`, remove `.call` from the queue, `presenter.setCallPanel(nil)`, and clear the shown state.
  - In `stop()`, call `call.stop()`.
- [ ] **Step 2: `refreshCall()`** goes in the 0.25 s tick after `refreshTimer()`. Guard on `settings.showsCalls`. Call `call.refresh(at: now, hidden: Set(settings.hiddenCallApps))`, then:
  - **`.live(app, since)`:** insert a record:
    - `id: NotchController.callActivityID`, `kind: .call`, `ttl: nil`, `insertedAt` kept stable;
    - `title: "On a call · \(app.name)"`;
    - `compactText: TimerText.format(seconds: now.timeIntervalSince(since).rounded(.down))`;
    - `symbolName: update.isMuted ? "mic.slash.fill" : "mic.fill"`;
    - `artwork`: the app's icon as PNG, cached per bundle id;
    - `tint: .positive`, `url: URL(string: "ledge://call")`.

    Republish only when the text, symbol, artwork or app change. Publish `CallPanelData(appName:icon:since:isMuted:canMute:micName:)` through `presenter.setCallPanel`. The panel is not cleared while locked; the controller already makes its buttons inert.
  - **`.ended(app, length)`:** insert the same id and kind with `ttl: 3`:
    - `title: "Call ended · \(app.name)"`;
    - `compactText: TimerText.format(seconds: length.rounded(.down))`;
    - `symbolName: "phone.down.fill"`, no artwork, no tint, no url.

    Then `setCallPanel(nil)`.
  - **`.idle`:** if a live record is shown, remove `.call` and `setCallPanel(nil)`. Never remove an ended record early; its TTL ends it.
- [ ] **Step 3: Clicks.** Generalise `openSourceApp()` into `activateApp(bundleID: String?, pid: pid_t?)`, keeping its LaunchServices-first comment, and have `openSourceApp` call it. In `open(_:)`, route `ledge://call` to `activateApp` with the live app's bundle id and PID before anything else.
- [ ] **Step 4: Intents.** In `handle(_ intent:)`:
  - `.toggleMute` calls `call.toggleMute()`;
  - `.hideCallApp` calls `settings.hideCallApp(liveApp.bundleID)` when a call is live.

  The next refresh then hands over or goes idle quietly, and the service restores any mute.
- [ ] **Step 5: When the service can't run.** In `evictUnavailableServices`, `if !call.availability.isAvailable { queue.remove(kind: .call) }` and clear the panel. In `issues`, add `note("Calls", call.availability)` when `settings.showsCalls`.
- [ ] **Step 6: Build and run all tests.** Run `make test`. Expected: all pass.
- [ ] **Step 7: Install, relaunch, and check live with the user.** Run `make install`, then `make stop`, then `open /Applications/Ledge.app`. Ask the user to start a FaceTime call (or a Voice Memos recording):
  - the icon and green clock appear about 2 s after the mic goes on;
  - hover opens the card; mute turns the glyph red;
  - "Not a call" on Voice Memos makes the pill go;
  - Settings › Island lists Voice Memos under "Not calls", and removing it brings the pill back;
  - ending the call shows a red hang-up and the length for 3 s.
- [ ] **Step 8: Commit** with the message "show calls on the island: the app and its clock while the mic is on, mute and not-a-call on the card, and the length when it ends".

### Task 11: Docs

**Files:**
- Modify: `README.md`. Add a row to "What it shows" after the Clock timer row, with the copy from the spec's Docs section:

  > On a call in any app (the mic in use) | the app's icon left, the time right in green, the red crossed-out mic when muted; rest the cursor for a card with a mute button and "Not a call"; a red hang-up and the length for 3 s when it ends

  Also mention the "Calls" switch in the Island settings sentence.
- Modify: `docs/superpowers/specs/2026-09-25-notch-companion-design.md`. In the priority table add `30  call  sticky  the mic held by an app (a call)`.
- Modify: `docs/manual-checks.md`. Append "## Calls on the island (2026-10-22)" with the spec's pending list:
  1. A Zoom or FaceTime call.
  2. Meet in Safari and in Chrome.
  3. Muting from the card and from System Settings.
  4. AirPods connecting mid-call.
  5. Locking during a call.
  6. The switch off mid-call.
  7. "Not a call" on Voice Memos, and bringing it back from Settings.

  Mark which of these the user confirmed in Task 10.

- [ ] **Step 1: Make the three edits.**
- [ ] **Step 2: Commit** with the message "describe calls on the island in the readme, the spec's priority table and the manual checks".
