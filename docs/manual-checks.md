> **Superseded — read this first.** A whole-branch review found the island
> did not actually render: content sat at opacity 0 in every state but
> `.expanded` (a progress-window mismatch), and separately rendered
> 100–145pt below the island over the desktop (`.overlay`'s default
> centre alignment against a `Shape` fill that occupies the whole canvas).
> **Both defects were present for every check recorded below** — so Task
> 8's "Revised expectation" (a visible dot + percentage at one-activity
> size) and Task 6 check 6 were not true as shipped, regardless of how they
> read. Both defects are now fixed; see **"Fix wave — corrected
> predictions and new checks"** at the end of this file for the current,
> accurate expectation and for what is still genuinely unverified. The
> sections below are kept as a historical record of what each session
> knew at the time, not as current guidance.

# Task 6 manual checks — `NotchRootView` on screen

Performed from an unattended CLI agent session: no interactive mouse/keyboard
input, no screenshot capability, and no Accessibility or Screen Recording
grant available to this process (those permissions require a human to click
"Allow" in System Settings; nothing can script around that). So **none of the
six checks below were verified by eye**, which is recorded honestly per each
item rather than claimed as passing.

What *could* be done, and was: a non-interactive smoke test (below), plus
tracing each check against the automated suite (49/49 green) and the source
as shipped in this task's diff.

## Smoke test performed

Ran the real debug binary directly (`.build/debug/Ledge`, not through `make
dev`, since no codesigning identity exists in this environment —
`security find-identity -v -p codesigning` returns zero identities here):

```
.build/debug/Ledge &          # pid 22544
```

- `lsappinfo list` showed it registered with the real WindowServer as
  `type="UIElement"` (matches `LSUIElement`/`.accessory`), alive and
  checked-in.
- `log show --info --debug --predicate 'subsystem == "com.dedemahendra.ledge"'`
  captured: `launched; notch <private>` — the last statement of
  `applicationDidFinishLaunching`, reached only after `NotchPresenter.init()`
  and `start()` both ran to completion: found `NSScreen.builtIn`, computed a
  real `NotchGeometry.notchRect` on this Mac's actual notched display,
  constructed the `NotchController`/`NotchWindow`/`NotchRootView`, registered
  the `didChangeScreenParametersNotification` observer, and installed the
  global `.mouseMoved` monitor — none of it threw or crashed.
- Process stayed alive (checked via `ps`) for the duration of the test, then
  was killed cleanly (`kill 22544`); confirmed no stray process remained
  afterward.

This confirms the app launches and wires up without crashing on real
notched hardware. It does **not** confirm anything about what appears on
screen or how it responds to input — that needs a human.

## The six checks

1. **Move the cursor onto the notch → island grows slightly (peek) with a
   spring.**
   Not eye-verified (no input injection, no screenshot). Supporting
   evidence: `NotchControllerTests.hoverPeeksAndUnhoverHides` pins
   `hidden → peek` on `setHovered(true)`; `NotchAnimationTests` pins the
   expand spring's constants and overshoot shape. Not sufficient on its own
   to claim the on-screen motion is correct.

2. **Move away → it collapses and disappears.**
   Not eye-verified, same constraints as (1). Supporting evidence:
   `NotchControllerTests.hoverPeeksAndUnhoverHides` (the unhover half) and
   `NotchWindowTests` covering `orderOut`-equivalent hit-testing (`nil` path
   claims nothing). `NotchPresenter.updateHover()` was rewritten in this task
   (see report) to only act when the hover boolean changes, and
   `syncWindowToVisibility()` orders the window out exactly when
   `controller.isVisible` is false — reasoned correct, not observed.

3. **Menu bar → Toggle Panel → island expands to the full panel size; again
   → collapses.**
   Not eye-verified. Note: this is the check where a real defect was found
   and fixed (see report) — the brief's `AppDelegate` called
   `presenter.controller.click()`/`.dismiss()` directly, which never
   reordered the window, so with the cursor away from the notch (the
   realistic position of the status item) nothing would have appeared on
   screen despite the model correctly reaching `.expanded`. Fixed by routing
   the menu action through a new `NotchPresenter.toggle()` that resyncs the
   window. `NotchControllerTests.clickExpandsAndDismissCollapses` covers the
   model transition; the window-resync half is untested by the automated
   suite (there is no window-observation test harness in this codebase) and
   was reasoned through, not observed running.

4. **Click the menu bar just left of the notch (e.g. Finder menu) → it opens
   normally.** Marked as the important, blocking check.
   Not eye-verified — flagging this plainly rather than inferring a pass.
   Supporting evidence, none of it a substitute for watching it happen:
   `NotchWindowTests.notchShapePathClaimsTheIslandAndNotTheMenuBarBesideIt`
   (pre-existing, passing, unmodified) asserts directly that a point beside
   the island's claimed path is not hit-tested. This task does not touch
   `NotchHostingView.hitTest` or `NotchWindow.setInteractiveShape` — the
   geometry that decides what is claimed is exactly Task 5's reviewed code.
   Task 6 only changes *when* `setInteractiveShape`/`interactivePath = nil`
   are invoked (on hover-change, on toggle, on rebuild), never the shape
   math itself. That is a reason for confidence, not a verification — a
   human must confirm this one before shipping.

5. **System Settings → Displays → change scaling → island repositions and
   still behaves.**
   Not eye-verified (requires System Settings interaction). Supporting
   evidence: `NotchGeometryTests.scaledModeYieldsDifferentButValidGeometry`,
   `NotchShapeTests.restingHeightsNeverShrinkAndAlwaysCoverTheCutout`,
   `NotchWindowTests.canvasIsAnchoredToTheTopCentreOfItsScreen` and
   `repositioningClearsTheStaleInteractivePath` cover the geometry and
   window-repositioning math in isolation.
   `didChangeScreenParametersNotification` → `rebuildForCurrentScreen()` →
   `window.reposition(for:)` was never exercised end-to-end with a real
   scaling change event in this session.

6. **Nothing is ever drawn inside the notch cutout itself.**
   Not eye-verified. Supporting evidence: `NotchRootView.islandContent`
   reserves `Color.clear.frame(width: notch.width, height: notch.height)`
   for the hole (unchanged from the brief; `Sources/NotchKit/NotchRootView.swift`),
   and nothing else is drawn at that position in the `HStack`. Source-level
   confirmable, not screen-confirmable from here.

## Bottom line

Automated coverage (49/49) plus the launch smoke test give reasonable
confidence the plumbing is sound, but **all six by-eye checks, including the
blocking check 4, still need a human to actually run `make dev` (after `make
cert` to create a local signing identity) and look at the screen** before
this is considered verified end to end.

---

# Task 8 manual checks — `PowerService` driving a live charging activity

Same environment as Task 6: no interactive mouse/keyboard input, no
screenshot capability, no Accessibility or Screen Recording grant, and (still)
no local codesigning identity (`security find-identity -v -p codesigning`
returns zero identities; `make cert` was not run — it is an interactive
step this session has no standing to perform unprompted). So `make dev`
itself cannot run (it signs before launching); the smoke test below again
runs the debug binary directly, as Task 6 did.

None of the six checks below were verified by eye. Recorded honestly per
item, not claimed as passing.

## Smoke test performed

The machine this session is running on happens to be on AC power and
charging, which made a genuinely useful live check possible for once (not
just source-level reasoning):

```
pmset -g batt
  Now drawing from 'AC Power'
  -InternalBattery-0 (id=35782755) 54%; charging; 4:22 remaining present: true
```

Launched `.build/debug/Ledge` directly (twice, pids 50643 and 50776), each
left running ~3–15s, then killed cleanly (confirmed via `ps` that neither pid
remained afterward):

- `lsappinfo list` showed the second run registered with the real
  WindowServer as `type="UIElement"`, checked in, alive.
- `log show --info --debug --predicate 'subsystem == "com.dedemahendra.ledge"'`
  (via `rtk proxy log show ...` — the direct invocation was mangled by this
  session's shell wrapper) captured, for **both** launches:
  `launched; notch <private>` — the last statement of
  `applicationDidFinishLaunching`, reached only after `NotchPresenter.start()`,
  `AppModel.start()` (which calls `PowerService.start()`, which calls
  `IOPSNotificationCreateRunLoopSource` and an initial `poll()` against the
  real IOKit power sources on this Mac), and both `StatusItemController`
  status rows completed without throwing or crashing.
- Filtering the same window to `category == "power"` (PowerService's own
  `OSLog` category) returned **zero lines at any level** — no error (so
  `IOPSNotificationCreateRunLoopSource` did not fail; `availability` stayed
  `.available`), no `"no power sources returned"` debug line (so it found and
  parsed the real battery), and critically no `"power event: ..."` line.

That last point is a real, live confirmation of **check 5 below**, not just
source-level reasoning: the machine was genuinely on AC power and charging at
launch, `PowerEventDeriver`'s first reading fired no event (by design — see
`PowerEventDeriverTests.firstReadingEmitsNothing`), so nothing was ever
inserted into `AppModel`'s queue, so no spurious charging activity was
announced. This is the one check in this document backed by something
stronger than "reasoned, not observed."

## Finding (fixed in fix round 1): a single activity showed no text at all

While implementing Step 11, tracing the actual geometry turned up something
worth flagging before, not after, a human sits down to run check 1 and 2.

`NotchMetrics.oneActivity.height` is pinned (Task 3, `NotchShapeTests
.specifiedTargetGeometryIsHonoured`) to exactly `notchRect.height` — per spec
§6, "One activity is minimal and notch-height." `NotchRootView.islandContent`
(Task 6, unmodified by Task 8) only renders `detailRow` when
`parameters.height > notch.height + 8`. Since `oneActivity.height` **equals**
`notch.height`, that condition is `x > x + 8`, which is false for any `x` —
not a near-miss depending on hardware measurements, a structural
impossibility, and true since Task 3 (confirmed: with the original hardcoded
`height: 32` it was equally `32 > 40`, false). `AppModel` only ever feeds one
`.power` record at a time, so `queue.visible.count == 1` for the common
lone-charging-event case, which drives `NotchController` to exactly the
`oneActivity` size — where, as originally shipped, `trailingEar` only ever
tested `overflowCount > 0` and `leadingEar` only ever drew an anonymous dot.
Net effect as originally shipped: the island sized and timed correctly but
showed **no text anywhere** for the single most common case.

**Fixed in fix round 1**, without touching `NotchMetrics` or
`NotchController`'s state→size mapping (both remain Tasks 2/3's reviewed,
pinned-by-test surface; spec §6's "1 activity = compact ears-only" is a
deliberate choice — layout C over layout B — not a bug, so growing the
island for one activity was rejected as the fix). Instead, `PowerEvent` now
exposes `compactText` (e.g. `"87%"` — a few characters, sized for the
trailing ear's ~38pt width, not the full title), threaded through
`ActivityRecord.compactText` → `NotchController.ActivityDisplay.compactText`
→ `NotchRootView.trailingEar`. The trailing ear now shows the overflow pip
when there's overflow, else the first activity's `compactText` when there is
one. See `Sources/PowerService/PowerEventDeriver.swift`,
`Sources/ActivityKit/ActivityRecord.swift`,
`Sources/NotchKit/NotchController.swift`, `Sources/NotchKit/NotchRootView.swift`.

Revised expectation for checks 1 and 2 below: a human running them today
should see the island widen to `oneActivity` size, the leading-ear dot, and
**the percentage in the trailing ear** (e.g. `"87%"`) — not the full
sentence (`"Charging · 87% · 24 min to full"`), which still only appears once
a second activity is concurrently queued (`twoActivities`, 62pt tall, has
room for `detailRow`). That remains a real, unaddressed product question for
a future task (what a lone HUD/notification/device activity — no
`compactText` producer of its own yet — should show), not something this fix
round expands scope to cover.

## The six checks

1. **Plug in the charger → island morphs out showing `Charging · NN% · NN min
   to full`, then collapses after ~3s.**
   Not eye-verified (no charger to physically toggle in this session, no
   screenshot). **Revised expectation per the finding above (now fixed):** a
   lone charging event shows the island at `oneActivity` size, the
   leading-ear dot, and `"NN%"` in the trailing ear — not the full sentence,
   which needs a second concurrent activity to have room. Supporting
   evidence: `PowerEventDeriverTests.plugInIsReported`,
   `.eventTitlesAreHumanReadable`, and the new
   `.compactTextIsAFewGlanceableCharacters` pin the event and both its full
   and compact text; `ActivityQueueTests` covers the 3s TTL
   (`ActivityKind.power.defaultTTL == 3`) and its expiry; `NotchControllerTests
   .activityShowsWithoutHoverAndRestsOnActivityState` pins hidden→activity on
   a nonzero count. None of this substitutes for watching it happen.

2. **Unplug → island shows `On battery · NN%`, then collapses.**
   Not eye-verified, same constraints as (1), same revised expectation (a
   lone unplug event shows `"NN%"` in the trailing ear, not the full
   sentence). Supporting evidence: `PowerEventDeriverTests.unplugIsReported`
   and `.compactTextIsAFewGlanceableCharacters`.

3. **Plug in, then hover the island as it is about to collapse → it stays
   until the cursor leaves.**
   Not eye-verified. This mechanism is orthogonal to the finding above (it
   governs *whether* the island stays open, not what text it shows, so it
   should hold even though check 1/2's text will not be visible for a solo
   activity). Supporting evidence: `ActivityQueueTests
   .hoverSuppressesExpiryAndUnhoverThenExpiresEverythingDue` pins that
   `prune(hovered: true)` drops nothing; `AppModel.prune()` passes
   `presenter.controller.isHovered` into that call every 0.25s. The
   hover-tracking mechanism itself (`NotchPresenter.updateHover`) predates
   Task 8 and is unmodified.

4. **Menu bar shows `Power — ready`.**
   Partially verified: the smoke test confirms the *code path* that computes
   and sets this string (`AppDelegate.applicationDidFinishLaunching` →
   `model.powerStatus` → `power.availability.statusText`) ran to completion
   without crashing on real hardware, with `availability` never observed
   moving to `.unavailable` (no error-level log). `ServiceAvailability
   .available.statusText == "ready"` is a fixed string, not dependent on
   runtime data. **Not visually confirmed** — reading the actual menu bar
   text needs a human; there is no Accessibility/screenshot path here to do
   it non-interactively.

5. **Launch the app while already plugged in → no spurious charging
   activity.**
   **Genuinely verified live**, not just reasoned — see "Smoke test
   performed" above. The real machine was on AC power and charging at both
   launches; the `power`-category log was empty at every level, meaning no
   `PowerEvent` was ever derived or yielded, meaning `AppModel.handle(_:)`
   was never called. This is the one check in this file (Task 6's or Task
   8's) backed by a live observation rather than by source-reasoning alone.

6. **Click the Finder menu while an activity is showing → the menu still
   opens.**
   Not eye-verified — flagging plainly rather than inferring a pass. Task 8
   does not touch `NotchWindow.swift`, `NotchHostingView.hitTest`, or the
   click-through geometry Task 6's check 4 already covers; it only changes
   *what is drawn* inside the already-reviewed interactive-region math, via
   `ContentFade`'s opacity and `detailRow`'s content — neither affects
   `setInteractiveShape`'s path. Reason for confidence, not a substitute for
   a human clicking it.

## Bottom line

Five of six checks remain by-eye-only and unverified in this session, same
structural reason as Task 6 (no input injection, no screenshot, no
Accessibility grant, no local signing identity). Check 5 is now backed by a
live log observation rather than pure reasoning — a step up from Task 6's
all-reasoned baseline. The geometry finding above (fix round 1) means a human
running check 1 or 2 today should expect the island to size and time
correctly **and** show a short percentage in the trailing ear for a lone
power activity — not the full sentence, which still needs a second
concurrent activity. That revised expectation is a traced, reasoned
prediction plus 19/19 `PowerServiceTests` green, not a guess, but it is still
not an eye-verified observation of pixels on a real screen.

---

# Fix wave — corrected predictions and new checks

Same environment constraints as every session above: no interactive
mouse/keyboard input, no screenshot capability, no Accessibility or Screen
Recording grant. This session went further than that baseline, though —
**it did not even run the launch smoke test** Task 6 and Task 8 did
(`.build/debug/Ledge` directly, or `make dev`), because `make cert`'s
keychain import needs an interactive "Allow" click this session has no
standing to trigger unprompted, and nothing about this fix wave changes
that constraint. So everything below is either (a) verified by an
automated test that actually runs, and said which, or (b) reasoned from
the diff, and said so — **nothing in this section is an eye-verified
observation, and none of it claims to be**.

## What was wrong, and what changed

A whole-branch review found two defects in `NotchRootView.swift` that made
island content invisible or misplaced in every state the six checks above
exercise:

1. **Content was opacity 0 outside `.expanded`.** The fade-in math compared
   the wrong two quantities (a height normalised against the global
   collapsed→expanded span, against a window defined over a transition's
   own 0→1 progress). Fixed by driving the fade from `controller.isVisible`
   and letting SwiftUI's `Animatable` interpolation supply the transition
   progress.
2. **Content rendered 100–145pt below the island**, over the desktop,
   unbacked, in every state but the tallest. `.overlay {}`'s default
   alignment is `.center`, applied to a `Shape` fill that occupies the
   whole 640×320 canvas, not the island's own drawn extent. Fixed with
   `.overlay(alignment: .top)`.
3. A third, smaller defect the new test below caught while verifying the
   first two: the detail row's height frame centred its content by
   default, so two stacked activity rows could overflow upward into the
   ear row/notch area instead of clipping safely below. Fixed by
   top-aligning that frame.

Full detail, including the exact arithmetic and the render test's
before/after pixel counts, is in
`.superpowers/sdd/2026-09-25-notch-shell-and-first-activity/final-fix-report.md`.

## New automated evidence (not eye-verification)

`Tests/NotchRenderTests` renders the real `NotchRootView` headlessly via
`ImageRenderer` (no window, no screen) for the one-activity, two-activity,
and expanded states, and checks the actual rendered pixels: at least one
content pixel lands inside the island's drawn bounds, none lands inside the
notch rect, and none lands outside the island's bounds. Confirmed this
fails against the pre-fix code (for the reasons above) and passes against
the fix, for all three states. This is real, automated, pixel-level
evidence that content is geometrically correct — but it is a synthetic
render, not a screenshot of the real app on real notched hardware, and it
says nothing about animation feel, timing, or input handling. Checks 1, 2,
and 6 below still need a human.

## Corrected expectation for checks already in this file

- **Task 8, checks 1–2** ("a human running check 1 or 2 today should expect
  ... a short percentage in the trailing ear"): that prediction assumed
  content was visible at one-activity size, which defect 1 made false for
  the entire time it was true on paper. With defect 1 fixed, the
  **original** fix-round-1 prediction is now actually deliverable: a lone
  charging/unplug event should show the island at `oneActivity` size, the
  leading-ear dot, and `"NN%"` in the trailing ear — not the full sentence.
  Still not eye-verified; now backed by the render test above in addition
  to the reasoning that was already there.
- **Task 6, check 6** ("nothing is ever drawn inside the notch cutout"):
  the previous supporting evidence only read the source structure, which
  never actually proved the hole stayed clear once defect 2 shifted
  everything downward (displaced content wouldn't have touched the hole
  either way — which is exactly why defect 2 needed a pixel-level check,
  not a source-level one, to be caught at all). The render test's second
  assertion now checks this directly, pixel by pixel, for all three states.

## New checks needed for this fix wave (none eye-verified)

Interaction and lifecycle changes with no prior manual-check coverage at
all, because the behaviour did not exist before this fix wave:

1. **Tap the island when it is showing (peek/activity) → it expands.**
   New: `NotchRootView` now has an `.onTapGesture` routed through
   `NotchPresenter.toggle()`. Reasoned correct (mirrors the menu bar's
   already-covered "Toggle Panel" path), not observed.
2. **Click anywhere outside the island while expanded → it dismisses.**
   New: a `.leftMouseDown` global monitor in `NotchPresenter`. Reasoned
   correct from Apple's documented global-monitor semantics (see the
   report), not observed.
3. **Press Escape while expanded → it dismisses.** New: a *local* keyDown
   monitor. Flagged plainly in the report as a real, unresolved tension:
   `NotchWindow.canBecomeKey` is hardwired `false`, so this window can
   never become key, and a local monitor structurally needs a key window
   to see keyDown — this is unlikely to fire while some other app has
   focus, which is the realistic case. A human should verify this
   specifically, and may find it simply does not work while focus is
   elsewhere; that would confirm the concern already on record rather than
   be a new finding.
4. **Turn Reduce Motion on/off in System Settings while Ledge is already
   running → springs switch to the crossfade (and back) without
   relaunching.** New: `NotchPresenter` now observes
   `accessibilityDisplayOptionsDidChangeNotification`. Not observed.
5. **Menu bar item's menu reads `power, app, ─, Quit Ledge` with Quit
   last**, regardless of how many status rows or action items exist.
   Previously read `power, app, ─, Quit Ledge, Toggle Panel` with Quit in
   the middle. Reasoned correct by tracing the exact call sequence against
   the new insertion logic (see the report); not observed.
6. **On a Mac with no battery (e.g. a desktop Mac), the menu bar reads
   `Power — unavailable — no internal battery`, not `Power — ready`.** New:
   `PowerService.poll()` now filters for the internal battery specifically
   and reports unavailability when none is found. Not observed on any
   battery-less Mac; this development session has no such hardware.
7. **Dismissing an open panel while an activity is live does not briefly
   flash the notch cutout uncovered**, and hovering from peek onto a
   one-activity island does not visibly dip before settling. Both are
   spring-selection fixes (item 4 in the report) with no automated
   coverage possible here — `NotchAnimationTests` still only pins the
   spring constants themselves, not which one a given transition picks.
   Needs a human watching the actual motion.

## Bottom line

Nothing in this fix wave has been eye-verified — this session did not even
attempt the launch smoke test earlier sessions ran. What's new is a
pixel-level automated test proving the two worst defects are actually
fixed in the rendered output, not just in the reasoning about the code,
plus seven new behaviours (above) that have no manual verification at all
yet and did not exist before this pass. Before shipping, a human needs to:
run `make cert` once (interactive), `make dev`, and go through Task 6's
six checks, Task 8's six checks (with the corrected expectation above),
and the seven new checks in this section.

# Task 4 manual checks — `OSDSuppressor`

Performed from the same unattended CLI agent session described throughout
this file: no interactive mouse/keyboard input, no screenshot capability,
and no Accessibility/Input Monitoring grant available to this process. That
matters more than usual for this specific task, because the thing being
checked — Apple's stock volume/brightness overlay — is driven by real
hardware media-key HID events, not by a value change, and Task 4's own
constraints forbid requesting Accessibility/Input Monitoring to synthesize
one. So the brief's literal Step 5 procedure (`make dev`, press volume
keys, watch for the overlay) could not be carried out here. Recorded
honestly below rather than claimed.

**Also relevant: `OSDSuppressor` is not wired into the running app yet.**
Tasks 2–4 build the three services; composing them into `Ledge`'s
`AppDelegate` (calling `recoverAtLaunch()`, `setSuppressing(true)`,
`shutdown()`) is Task 5's job. So even with key-press access, `make dev`
would not exercise suppression at all right now — there is nothing in the
running app yet that calls into `OSDSuppressor`. The checks below verify
what is checkable before that wiring exists; the brief's actual Step 5
procedure needs to be re-run by a human (or an agent with input/screenshot
access) after Task 5 lands.

## What was checked

1. **No codesigning identity exists in this environment**
   (`security find-identity -v -p codesigning` → "0 valid identities
   found"), matching the precedent already recorded elsewhere in this file.
   `make dev`/`make sign` cannot run here at all, independent of the
   composition-ordering point above.

2. **`OSDUIHelper` is confirmed not resident**, matching the task's
   verified environment facts: `pgrep -xl OSDUIHelper` found nothing at
   baseline.

3. **Tried a headless way to trigger it anyway, and confirmed it does not
   work**: changing system volume via `osascript -e "set volume output
   volume N"` several times in a row did not launch `OSDUIHelper`
   (`pgrep` still found nothing afterward). This confirms the overlay is
   tied specifically to the hardware media-key event path, not to CoreAudio
   volume changes — consistent with `VolumeObserver` (Task 2) and
   `OSDSuppressor` needing to be independent mechanisms, and confirms there
   is no scriptable, permission-free way to trigger the real overlay from
   this environment.

4. **Validated the actual `kill()`-based signal mechanics against a real
   process** (a spawned `sleep 300`, standing in for the helper, since the
   real one cannot be launched here): `kill -STOP` brought it to `ps`'s `T`
   state, `kill -CONT` brought it back out of `T`, and sending `SIGSTOP`
   twice in a row was confirmed idempotent (state stays `T`, no error) —
   this is exactly what `OSDSuppressionPolicy`'s sweep relies on needing no
   process-state inspection. This exercises the identical `kill(pid,
   SIGSTOP)` / `kill(pid, SIGCONT)` calls `OSDSuppressor.apply(_:)` makes,
   just against a stand-in pid rather than a real `OSDUIHelper` one.

5. **Validated `NSRunningApplication.runningApplications(withBundleIdentifier:)`**
   — the real API `helperPIDs()` wraps — actually runs cleanly from a plain
   command-line process (no crash, no hang), the same execution context
   `swift test` uses (not a signed `.app` bundle): returned an empty array
   both for `com.apple.OSDUIHelper` (not running) and for a bundle id that
   can never exist. This is the exact call `OSDSuppressor` makes on every
   sweep tick and at launch recovery; confirming it behaves under `swift
   test`'s process context (rather than only inside a full signed app)
   closes a gap the automated suite itself doesn't cover, since none of
   `OSDSuppressorTests.swift`'s 7 tests instantiate `OSDSuppressor` itself
   (by design — they test the pure `OSDSuppressionPolicy` decisions; the
   brief's own Step 1 tests don't exercise the shell either).

6. **Full package build succeeds** (`swift build`) and the full suite
   passes (122/122 at the time of this task) with `OSDSuppressor` compiled
   in as part of `HUDService`.

## What remains genuinely unverified

Everything that requires either (a) a real hardware media-key event, or
(b) `OSDSuppressor` actually wired into the running app (Task 5):

- That `setSuppressing(true)` actually keeps Apple's overlay from
  appearing when volume/brightness keys are pressed for real.
- That the repeating sweep (`sweepInterval` = 0.75s) actually catches a
  real on-demand `OSDUIHelper` launch before it draws, rather than after —
  timing against a real process launch was not observable here.
- The crash-recovery scenario exactly as the brief describes it end to end
  (`pkill -9 -x Ledge`, confirm a real `OSDUIHelper` is left in `T` state,
  relaunch, confirm `recoverAtLaunch()` resumes it, quit cleanly, confirm
  the stock overlay returns). The `SIGSTOP`/`SIGCONT` mechanics underneath
  this are verified (#4 above) and the unconditional-resume *decision* is
  proven by `launchRecoveryResumesUnconditionallyWhenNotSuppressing` and
  `launchRecoveryStillResumesFirstEvenWhenAboutToSuppress`, but the
  end-to-end real-process version of this — the one the brief calls "the
  one failure that damages the user's system rather than the app" — needs
  a human, or an agent with input and screenshot access, after Task 5.
- The `atexit` handler firing on real process termination paths (it cannot
  be triggered by a unit test, and this session never ran `Ledge` as a
  signed app to terminate).

**Recommendation for whoever picks this up after Task 5:** run the brief's
Step 5 procedure verbatim once composition exists, paying specific
attention to the crash-recovery half — that is the one path where a bug
degrades the user's system rather than just this app.
