# Browser Video Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let video playing in Safari, Chrome, Arc, Firefox, Edge or Brave take the island the way music does. A browser gets in only while it plays something with a length, and never during a call.

**Architecture:** `MediaService` gets the pure rules: the payload's source app (the parent app when the adapter reports one), browser ids in the allow-list, and `BrowserVideoGate.admits(...)`. `LedgeSettings` gets the browser switches, and an "offered" list so new sources arrive switched on. `AppModel.handle(_ payload:)` applies the gate, keeps the last raw payload so a call starting or ending, or the 2-minute pause hold running out, can re-run it, and uses the source app for status, the favourite star and click-to-open.

**Tech Stack:** Swift 6, Swift Testing, SwiftUI Settings, `make test FILTER=…`.

**Spec:** `docs/superpowers/specs/2026-11-18-browser-video-design.md`

## Global Constraints

- Browser ids (lowercase): `com.apple.safari`, `com.google.chrome`, `company.thebrowser.browser`, `org.mozilla.firefox`, `com.microsoft.edgemac`, `com.brave.browser`. Names: Safari, Chrome, Arc, Firefox, Edge, Brave.
- The gate admits a browser only if no call is up **and** `duration` is finite and > 0 **and** (it is playing, **or** it is already shown and paused for less than 120 s).
- Music sources are untouched by the gate.
- Settings footer, exactly: "The island follows music from these apps, and video from these browsers while it plays. Calls and live streams never take the notch."
- Never log titles or artists. The source id is logged only with `privacy: .private`, as today.
- Commit only this feature's files and hunks. The working tree carries unrelated uncommitted edits (agent rows, GitHub rows, `AppModel.swift:507-525`, the live-activity service) that must stay unstaged.

## Review Focus

1. **Safari reports its WebKit helper** as `bundleIdentifier`. Expect the policy, the Settings status and click-to-open to see Safari. Click-to-open must not activate the helper's pid. Test: `sourceIsTheParentAppWhenThereIsOne` (Task 1).
2. **A live stream** (duration 0, nil or infinite) never gets in. Test: `aBrowserWithoutALengthNeverGetsIn` (Task 1).
3. **A paused tab from earlier** (paused when Ledge first sees it) never brings the card up. Test: `aPausedBrowserNeverBringsTheCardUp` (Task 1).
4. **An existing user whose saved list predates browsers** gets browsers on, and keeps any music app they switched off. A browser they switch off stays off after relaunch. Test: `browsersArriveOnForAnExistingSavedList` (Task 2).
5. **A call starting while a browser video is shown** removes the card at once, and it returns when the call ends if the video still plays. Covered by the gate's `onCall` test plus the live check. The re-run wiring is in Task 3.

---

### Task 1: Source resolution, browser allow-list and the gate (MediaService)

**Files:**
- Modify: `Sources/MediaService/MediaPayload.swift` (add `parentApplicationBundleIdentifier`, `sourceIdentifier`)
- Modify: `Sources/MediaService/MediaSourcePolicy.swift` (browser ids, `isBrowser`, doc comment)
- Create: `Sources/MediaService/BrowserVideoGate.swift`
- Test: `Tests/MediaServiceTests/MediaPayloadTests.swift`, `Tests/MediaServiceTests/MediaSourcePolicyTests.swift`, `Tests/MediaServiceTests/MediaSourcePolicyEnabledTests.swift`, create `Tests/MediaServiceTests/BrowserVideoGateTests.swift`

**Interfaces — Produces:**
- `MediaPayload.parentApplicationBundleIdentifier: String?`, decoded from the `"parentApplicationBundleIdentifier"` key.
- `MediaPayload.sourceIdentifier: String?`: the parent if non-empty, else `bundleIdentifier`.
- `MediaSourcePolicy.musicBundleIdentifiers: Set<String>` (today's list). `MediaSourcePolicy.browserBundleIdentifiers: Set<String>`. `allowedBundleIdentifiers` = the union of the two.
- `MediaSourcePolicy.isBrowser(bundleIdentifier: String?) -> Bool` (case-insensitive).
- `BrowserVideoGate.pausedHold: TimeInterval = 120`
- `BrowserVideoGate.admits(_ payload: MediaPayload, isShowing: Bool, pausedSince: Date?, onCall: Bool, now: Date) -> Bool`

- [ ] **Step 1: Write failing tests**
  - `sourceIsTheParentAppWhenThereIsOne`: decode `["bundleIdentifier": "com.apple.WebKit.GPU", "parentApplicationBundleIdentifier": "com.apple.Safari"]`, then `sourceIdentifier == "com.apple.Safari"`. Without the parent, `== bundleIdentifier`. With an empty-string parent, `== bundleIdentifier`.
  - Update `musicPlayersAreAllowedAndEverythingElseIsNot`: Safari and Arc are now allowed. `net.imput.helium`, QuickTime, Zoom, nil and "" are still not. Rename it to `musicPlayersAndBrowsersAreAllowedAndEverythingElseIsNot`.
  - `browsersAreKnownAsBrowsers`: `isBrowser("com.google.Chrome")` and `isBrowser("COM.APPLE.SAFARI")` are true. `isBrowser("com.apple.music")` and `isBrowser(nil)` are false.
  - In `theSettingsNarrowTheAllowList`, replace the Safari line: `isAllowed("com.apple.Safari", enabled: ["com.apple.safari"])` is now true, and `isAllowed("com.apple.Safari", enabled: onlyMusic)` is false.
  - `BrowserVideoGateTests` uses a helper `video(playing: Bool, duration: Double?)`:
    - `aPlayingBrowserVideoGetsIn`: playing, 600 s, not showing, no call → true.
    - `aBrowserWithoutALengthNeverGetsIn`: duration nil, 0 and `.infinity`, each playing → false.
    - `aPausedBrowserNeverBringsTheCardUp`: paused, 600 s, `isShowing: false` → false.
    - `aShownBrowserVideoHoldsTwoMinutesWhilePaused`: `isShowing: true`, `pausedSince: t0`. At `t0+119` true, at `t0+120` false. With `pausedSince: nil` while paused → false.
    - `aCallKeepsTheBrowserOut`: playing, 600 s, `onCall: true` → false.

- [ ] **Step 2: Run them and confirm they fail**
  Run: `make test FILTER=MediaServiceTests`. Expected: compile errors on `sourceIdentifier`, `isBrowser` and `BrowserVideoGate`.

- [ ] **Step 3: Implement the interfaces above.** `admits` returns false when `onCall`, then false unless the duration is finite and > 0, then true when playing, else `isShowing && pausedSince.map { now.timeIntervalSince($0) < pausedHold } == true`. Rewrite the `MediaSourcePolicy` doc comment: since 2026-11-18, browsers are on the list too, behind `BrowserVideoGate`.

- [ ] **Step 4: Run** `make test FILTER=MediaServiceTests`. Expected: all pass.

- [ ] **Step 5: Commit** these files: "media: browsers on the allow-list behind a playing, has-a-length, no-call gate; the source is the parent app".

### Task 2: Browser switches that arrive on (LedgeSettings)

**Files:**
- Modify: `Sources/LedgeSettings/AppSettings.swift` (Key `offeredMediaSources`, `knownMusicSources`, `knownBrowserSources`, init migration)
- Test: `Tests/LedgeSettingsTests/AppSettingsTests.swift`

**Interfaces — Produces:**
- `AppSettings.knownMusicSources: [(id: String, name: String)]` (today's five). `AppSettings.knownBrowserSources` (the six, in the Global Constraints order). `knownMediaSources` = music + browsers.
- `Key.offeredMediaSources = "offeredMediaSources"`: every id the settings have ever offered.

- [ ] **Step 1: Write failing tests**
  - `browsersArriveOnForAnExistingSavedList`: preset `defaults.set(["com.apple.music"], forKey: "mediaSources")` with no offered key, then `AppSettings(defaults:)`. Expect `isMediaSourceEnabled("com.apple.music")`, `!isMediaSourceEnabled("com.spotify.client")`, and every `knownBrowserSources` id enabled.
  - `aBrowserSwitchedOffStaysOff`: fresh settings, `setMediaSource("com.google.chrome", enabled: false)`. A second `AppSettings(defaults:)` shows Chrome off and Safari on.
  - The existing `everythingIsOnByDefault…` already checks that every known source is on. It now covers browsers too.

- [ ] **Step 2: Run** `make test FILTER=AppSettingsTests`. Expected: FAIL (no `knownBrowserSources`).

- [ ] **Step 3: Implement.** In init: `stored = defaults [String]?` for `mediaSources`. If nil, use all known. Otherwise, `offered = defaults[offeredMediaSources] ?? knownMusicSources ids` (a list saved before this key existed was offered the music apps only), and `mediaSources = Set(stored) ∪ (allKnownIds − offered)`. Then save `offeredMediaSources = allKnownIds` and save `mediaSources`. `didSet` doesn't run in init, so call `save` directly.

- [ ] **Step 4: Run** `make test FILTER=AppSettingsTests`. Expected: pass.

- [ ] **Step 5: Commit**: "settings: browser switches, and sources never offered before arrive on".

### Task 3: The island follows browser video (AppModel, Settings pane, docs)

**Files:**
- Modify: `Sources/Ledge/AppModel.swift` (around `handle(_ payload:)` at line 1305, `previewContent` at 1072, `openSourceApp` at 1964, the call `.live`/`.ended`/`.idle` branches at 1720-1756)
- Modify: `Sources/Ledge/SettingsPanes.swift:205-235`
- Modify: `README.md` (the Now Playing row), `docs/manual-checks.md` (new section), `docs/superpowers/specs/2026-09-25-notch-companion-design.md` (one line under the allow-list note)

**Interfaces — Consumes:** everything Task 1 produces, plus `AppSettings.knownMusicSources` and `knownBrowserSources` from Task 2.

- [ ] **Step 1: Gate in `handle(_ payload:)`.** Store every incoming payload in `private var lastMediaPayload = MediaPayload()` before the guard. Let `source = payload.sourceIdentifier` and pass it to `MediaSourcePolicy.isAllowed(bundleIdentifier:enabled:)`. If `MediaSourcePolicy.isBrowser(source)`, also require `BrowserVideoGate.admits(payload, isShowing: presenter.controller.media != nil && MediaSourcePolicy.isBrowser(mediaPayload.sourceIdentifier), pausedSince: browserPausedSince, onCall: callShown != nil, now: Date())`. A refusal for a call or an expired hold calls `clearMedia()` at once, not `holdThenClearMedia()`. Any other refusal keeps today's `holdThenClearMedia()`.
- [ ] **Step 2: Pause bookkeeping.** `private var browserPausedSince: Date?` and `private var browserHoldTask: Task<Void, Never>?`. When an admitted browser payload is paused and `browserPausedSince == nil`, set it to now and schedule `browserHoldTask` to sleep `BrowserVideoGate.pausedHold` seconds, then call `handle(lastMediaPayload)`. A playing payload, a non-browser payload or `clearMedia()` resets both (cancel the task).
- [ ] **Step 3: Re-run on call changes.** In the call refresh, when `callShown` goes nil → non-nil (`.live`), or non-nil → nil (`.ended`, `.idle`), call `handle(lastMediaPayload)` after updating `callShown`, if `MediaSourcePolicy.isBrowser(lastMediaPayload.sourceIdentifier)`.
- [ ] **Step 4: Use the source app elsewhere.** `previewContent` gets `mediaSource: … mediaPayload.sourceIdentifier?.lowercased()`, so it matches the lowercase ids in Settings status. `favorites.trackChanged(bundleIdentifier: payload.sourceIdentifier)`. `openSourceApp` gets `activateApp(bundleID: mediaPayload.sourceIdentifier, pid: mediaPayload.parentApplicationBundleIdentifier == nil ? pid : nil)`. Rewrite the September comment on the guard to describe the gate.
- [ ] **Step 5: Settings pane.** Split the one section into two `Section`s over `knownMusicSources` (header "Now playing from") and `knownBrowserSources` (header "Video from"), with the same row and toggle. The footer goes on the second section, using the exact text in Global Constraints. In `status(of:)`, compare `content.mediaSource == bundleIdentifier`.
- [ ] **Step 6: Build and run everything.** `make test`. Expected: all suites pass, the same count as before plus the new tests.
- [ ] **Step 7: Docs.** In the README Now Playing row, add browser video under the three rules. Add a `docs/manual-checks.md` section "# Browser video (2026-11-18)" with the live checks: a YouTube video in Safari and in Chrome shows the card; pause holds 2 min, then it leaves; a live stream stays off; a Meet call takes over and the video comes back after; a muted tab paused from earlier doesn't appear; click opens the browser; Chrome switched off stays off. In the companion design, add one line under the 2026-09-29 note pointing to the new spec.
- [ ] **Step 8: Commit** only this task's hunks. `AppModel.swift` has unrelated uncommitted edits at 507-525: stage with `git diff Sources/Ledge/AppModel.swift > /tmp/x`, cut to this feature's hunks, then `git apply --cached`. Message: "follow video in browsers: it takes the island while it plays something with a length, holds two minutes paused, and steps aside for a call".
- [ ] **Step 9: Install and relaunch** (`make install`, `make stop`, `open /Applications/Ledge.app`), then hand over the live checks.
