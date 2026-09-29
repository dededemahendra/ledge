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

# Task 5 manual checks — `HUDService` and the HUD island view

Unlike Task 4, this session found a working, signed, running `Ledge.app`
already on the machine (`/Applications/Ledge.app`, self-signed with the
"Ledge Dev" identity). That let far more of this task's Step 9 be checked
directly than Task 4's note anticipated — including two corrections to
that note itself, below.

## Correction to the Task 4 entry above

Task 4's entry says `security find-identity -v -p codesigning` → "0 valid
identities found" means `make dev`/`make sign` "cannot run here at all."
That conclusion does not follow, and this session confirmed it: `-v` lists
only *trusted* identities, and `scripts/make-cert.sh`'s own comment says so
("a self-signed certificate is legitimately untrusted... `codesign` signs
happily with an untrusted identity"). The "Ledge Dev" identity is present
(`security find-certificate -a -c "Ledge Dev"` finds it) and both
`make dev` and `make install` ran successfully in this session, building,
signing, and launching the app with no prompts or errors. Recorded here so
the `-v` result isn't mistaken for a hard blocker again.

## What was checked

1. **Full package build, debug and release** (`swift build`, `swift build
   -c release`) — both clean, no warnings besides the known CLT linker
   search-path noise.

2. **Full suite passes: 126/126** (`make test`), up from the 122 this task
   started with — `NotchRenderTests` grew from 5 to 8 (three new tests
   pinning `symbolName`/`barFill` rendering, described in the task report),
   `HUDServiceTests` grew from 32 to 33 (net: -1 from consolidating the two
   `launchRecoveryActions` cases into
   `launchRecoveryAlwaysResumesUnconditionally` per a mid-task correction —
   see the task report — +2 for `composedAvailability`). Every other
   target's count is unchanged.

3. **`make dev` and `make install` both actually run here** (see the
   correction above) — built, signed, launched `/Applications/Ledge.app`
   for real, not simulated.

4. **Menu bar content verified live**, via `System Events` /
   Accessibility (`osascript` querying `menu bar items of menu bar 1` of
   the running `Ledge` process — no synthetic input, just reading what is
   actually on screen): the running app's status menu read exactly
   `HUD — ready, Power — ready, Ledge — running, Toggle Panel, Toggle
   Stock OSD Suppression, missing value, Quit Ledge` — the exact order
   `StatusItemController`'s insert-at-0 / insert-above-Quit rules predict
   for the order `AppDelegate.applicationDidFinishLaunching` calls
   `setStatus`/`addItem` in. Confirms Step 6/7's wiring end to end, not
   just in `NotchKitTests`.

5. **Startup log confirms `composedAvailability` for real**: `log show`
   against the running process shows `hud ready, brightness backend
   polling` — i.e. on this machine, at least one channel (here, brightness
   via the polling fallback) came back available, `composedAvailability`
   correctly folded that into `.available`, and the menu bar's "HUD —
   ready" (#4) matches.

6. **The full volume pipeline fires end to end against real CoreAudio**,
   not just in `HUDEventDeriverTests`. A temporary log line was added to
   `AppModel.handle(_ event: HUDEvent)` for this check only, exercised via
   `osascript -e "set volume output volume N"` (confirmed by Task 4's own
   finding to go through real CoreAudio, just not through the hardware
   media-key path `OSDUIHelper` watches), then reverted before committing
   (`git diff` confirmed clean). Observed in the log, in order, for a
   40 → 60 → 45 → 30 (+ mute) → unmute sequence:
   ```
   volume(level: 0.400..., muted: false)
   volume(level: 0.600..., muted: false)
   volume(level: 0.450..., muted: false)
   volume(level: 0.300..., muted: false)
   volume(level: 0.300..., muted: true)
   volume(level: 0.300..., muted: false)
   ```
   Every level change fired, the mute toggle fired separately at an
   unchanged level (proving mute is tracked independently of level, per
   `muteTogglingFiresEvenAtTheSameLevel`), and the values match what was
   actually set. This is real `VolumeObserver` → `HUDEventDeriver` →
   `HUDService`'s `AsyncStream` → `AppModel.handle` → queue, observed live.

7. **The brightness pipeline fired end to end too, unprompted** — while
   the same temporary logging was in place, something on the machine
   dimmed the display for real (not scripted; no headless brightness
   setter was found — `which brightness` came back empty), and the log
   shows eight `brightness(level: ...)` events tracking it smoothly down
   from 0.75 to 0.3125. Confirms the polling backend (`BrightnessObserver`
   backend reported "polling" in #5 above) is not just reading a value
   once at launch but genuinely observing change over time.

8. **`Toggle Stock OSD Suppression` clicked twice via Accessibility**
   (on, then off again, restoring the default) — the app stayed at the
   same PID throughout, i.e. did not crash either transition. With
   `OSDUIHelper` not resident (#9), there was nothing for
   `OSDSuppressionPolicy.actions` to actually signal, so this confirms the
   toggle is wired and safe, not that suppression itself does anything
   observable here.

9. **`OSDUIHelper` confirmed not resident throughout** every check above
   (`pgrep -xl OSDUIHelper` → exit 1 before, during, and after) — consistent
   with Task 4's finding that nothing short of a real hardware media-key
   event launches it.

## What remains genuinely unverified

Same fundamental limit as Task 4, now with composition in place to remove
the second reason: no hardware media-key event, no screenshot, no
Accessibility/Input Monitoring grant to synthesize one.

- That the running island actually shows the `symbolName` glyph and the
  filling `barFill` bar on screen, styled and positioned as intended.
  `NotchRenderTests` proves this at the pixel level (headless
  `ImageRenderer`, colour-tagged content, exact bounds/budget checks) for
  every state this task added coverage for, which is strong evidence — but
  it is not the same as a human (or a screenshot-capable agent) actually
  looking at the notch.
- Apple's stock overlay actually being suppressed/restored by
  `setSuppressing`/the toggle, against a *real* `OSDUIHelper` triggered by
  a real key press — `OSDUIHelper` still cannot be launched headlessly
  here (#9), so this is exactly the gap Task 4's entry already flagged,
  now with the wiring in place to actually test it.
- Connecting a real Bluetooth audio device mid-session (spec's "Review
  Focus 1", AirPods scenario) — no such device is available to this
  session. See the task report's concerns section for a related design
  gap this surfaced: `HUDEventDeriver.reset()` exists and is unit-tested
  (`resetForcesTheNextReadingToBeTreatedAsFresh`) for exactly this
  scenario, but nothing in `VolumeObserver`'s current public surface gives
  `HUDService` a signal to call it from, so a device rebind's first
  reading is not distinguished from a real user change.
- The `atexit` restoration path on a real signal-kill (same gap Task 4
  noted; still untestable without actually killing a running signed app
  with `OSDUIHelper` resident under it).

## Bottom line

Everything checkable without hardware key-press/screenshot access was
checked, including two things Task 4 assumed were unreachable here
(codesigning, and therefore `make dev`/`make install`) and two full,
real, end-to-end pipeline firings (volume via `osascript`, brightness
unprompted). What remains is exactly the on-screen/real-overlay
confirmation every prior task in this file has also deferred to a human
or a screenshot-capable agent.

# Task 8 manual checks — now-playing in the island

Same environment constraints as every check above: unattended CLI agent, no
synthetic mouse/keyboard input, no screenshot capability. No codesigning
identity in the keychain this session (`security find-identity -v
-p codesigning` → 0 identities), so `make install`/`make dev` could not be
used as written. Substituted: `make bundle` (unsigned build) followed by
`codesign --force --sign - --identifier com.dedemahendra.ledge dist/Ledge.app`
(ad-hoc signing, no identity required), then `open dist/Ledge.app` — this
produces a real, properly bundled `.app` with the vendored adapter under
`Contents/Resources`, launched the normal way (not the raw debug binary),
which matters here specifically because `AdapterLocator.inMainBundle()`
resolves paths relative to `Bundle.main.resourceURL`.

## What was checked

1. **The app launches clean with the new media wiring in place.**
   `/usr/bin/log show --info --debug --predicate 'subsystem ==
   "com.dedemahendra.ledge"'` against the ad-hoc-signed bundle showed, in
   order: `hud ready, brightness backend polling`, then `launched; notch
   <private>` — the same final statement every prior task's smoke test
   confirmed reaches only after `AppDelegate.applicationDidFinishLaunching`
   runs to completion. Critically, **no `media unavailable` line appeared**
   this time (contrast with the raw-debug-binary run below) — see #2.

2. **The vendored adapter actually launches and stays up on real
   hardware.** `ps` after launch showed a second process beside `Ledge`
   itself: `/usr/bin/perl .../Contents/Resources/mediaremote-adapter/
   mediaremote-adapter.pl .../MediaRemoteAdapter.framework stream` — the
   exact command `MediaRemoteSource.run()` builds. This proves
   `AdapterLocator.inMainBundle()` resolved real paths, `locator.validate()`
   passed, `MediaRemoteSource.probe(locator:)` passed (a failed probe logs
   and never calls `launch()`), and the real `stream` subprocess is running
   under `/usr/bin/perl` (entitled, per the design doc). Both processes
   (`Ledge`, the adapter) were still alive and not crash-looping 49s later
   (`ps -p ... -o pid,etime,command`).

3. **Graceful degradation, confirmed the OTHER way too.** Running
   `.build/debug/Ledge` directly (bypassing `make bundle`, so
   `Bundle.main.resourceURL` does not contain `mediaremote-adapter`)
   logged `media unavailable: unavailable — adapter script missing from
   bundle` and then still reached `launched; notch <private>` — i.e. the
   app completes startup and HUD/power keep working with media entirely
   absent, no crash, no modal alert. This is the closest this environment
   can get to Step 9's "delete the adapter and relaunch" check without a
   codesigned install to delete a resource from.

4. **Menu bar status row — reasoned, not eye-verified, and here is
   exactly why not.** `AppDelegate.applicationDidFinishLaunching` calls
   `item.setStatus(key: "media", text: "Media — \(model.mediaStatus)")`
   unconditionally, immediately before the final `Self.log.info("launched;
   ...")` line — since #1/#2 confirm that final log line was reached, the
   call before it structurally must have executed without throwing
   (`StatusItemController.setStatus` has no failure path). Attempted to
   confirm this on screen via the same Accessibility technique the Task 6
   fix-wave check used (`osascript` querying `System Events`): it failed
   for a different reason than "no permission was ever granted" — `every
   process whose name is "Ledge"` only ever returned the **pre-existing,
   already-running, separately-installed** `/Applications/Ledge.app`
   (pid 88107, an older build with no Media row, launched before this
   session), never the freshly ad-hoc-signed `dist/Ledge.app` instance
   (confirmed alive and correctly PID'd via `ps`/`lsappinfo` throughout).
   Whatever Accessibility trust exists in this environment appears scoped
   to that specific earlier bundle/signature, not to a fresh ad-hoc
   signature from this session, and granting new Accessibility trust is
   the same "requires a human to click Allow" wall every check above has
   already hit. Reasoned correct from the log evidence in #1, not observed
   on screen.

5. **Clean shutdown attempt.** Tried the same Accessibility-driven "click
   Quit Ledge" approach used successfully in the Task 6 fix-wave check;
   it silently targeted nothing (same root cause as #4 — the query cannot
   see the new instance), so this did not actually exercise
   `applicationWillTerminate` → `model.stop()` → `media.stop()`. Not
   claimed as verified; the processes were instead cleaned up directly
   (`kill -9`) once the checks above were complete.

## What remains genuinely unverified

- Artwork/title/artist/scrubber/controls actually appearing and working on
  screen, styled as intended. `NotchRenderTests` (11 assertions across 4
  new tests this task added, all green) proves the pixel-level geometry —
  content inside the island, clear of the notch, the panel's ideal height
  under its 86pt budget — for every state Task 8 touches, using the same
  headless `ImageRenderer` technique as every prior task's coverage. That
  is strong evidence the layout is correct; it is not the same as a human
  looking at the notch.
- Play/pause/next/previous and drag-to-seek against a real playing track —
  no music was played during this session (nothing was actively playing
  against the real adapter, so `hasMedia` stayed false throughout and no
  activity was ever inserted) — combined with no synthetic input capability
  to press the panel's buttons or drag its scrubber even if something were
  playing.
- Switching source apps (Music → Spotify → a browser tab) and the 1Hz tick
  visibly advancing/freezing on play/pause — same root blocker (nothing was
  playing).
- The HUD-preempts-media-then-returns sequence (spec's priority
  interaction) on screen — `ActivityQueue`/`NotchController` are unit-tested
  for this precisely (`ActivityQueueTests`, `NotchControllerTests`), and the
  render tests prove both surfaces are geometrically safe independently, but
  the live *sequence* — volume HUD taking the leading ear, then handing it
  back to media's artwork after 1.5s — was not watched happen.

## Bottom line

Went further than a plain smoke test where the environment allowed it: a
real ad-hoc-signed bundle, a real spawned adapter subprocess, confirmed
stable over time, plus the deliberate negative check (raw debug binary,
adapter genuinely absent) proving graceful degradation on both sides of
that boundary. What is not verified is on-screen appearance/interaction —
the same category every task in this file has deferred to a human or a
screenshot-capable agent, for the same reason each time.

# HUD polish — reference-style volume/brightness island

**Date:** 2026-09-28. Branch `code-check` on top of `notch-shell-and-services`.

## What changed

A lone volume/brightness activity now gets its own island size
(`NotchMetrics.hud`: notch width + 2 × 90 pt, still notch-height) and its own
ear layout: glyph + "Sound"/"Display" label leading-aligned on the left, a 5 pt
× 68 pt bar with a 10 pt trailing inset on the right. Content also blurs in/out
with the fade (`ContentFade.blurRadius`, 0 at rest). Every other one-activity
island keeps 255 pt; a HUD with company keeps the two-slot size.

## Where the numbers came from

A 20 s, 1060 × 192 px screen recording of the reference app's HUD (2× scale,
so 2 px per point), frames extracted at 2 fps and scanned pixel by pixel:

| Measured | Reference | Ledge (rendered at 2×) |
| --- | --- | --- |
| Pill width | 720 px | 718 px |
| Glyph, from pill's left edge | 21–45 px | 18–46 px |
| "Sound" label | 68–137 px | 67–138 px |
| "Display" label | 68–149 px | 68–151 px |
| Bar starts | 564 px | 562 px |
| Track length / right inset | 136 px / 20 px | 136 px / 20 px |
| Bar height | ~9.4 px | 10 px |
| Track brightness | ~23 % white | 22 % white |

## Verified

- `make test`: 193 tests across 7 targets pass, including new
  `hudSizeGivesEachEarTheMeasuredWidth`,
  `aLoneHUDActivityGetsTheHUDSizeAndNothingElseDoes`, and the two render tests
  re-pinned to `metrics.hud`.
- Headless `ImageRenderer` snapshots of Sound 40 %, Sound 90 %, Display 70 %,
  muted, and a lone power activity, measured against the reference frames as
  above (temporary test, deleted after use).

## Not verified

- The live morph on the real notch — the spring and the blur-in were not
  watched on screen; only the resting frame was compared.

# Hover-to-expand (2026-09-28)

## What changed

`NotchController.recomputeState()` now derives `.expanded` from hover: cursor
over the island + `media != nil` opens the panel, cursor leaving closes it,
`setMedia` re-derives so media arriving/leaving under a parked cursor
opens/closes it too. `click()` (tap, or "Toggle Panel") now sets
`isPinnedOpen`, which hover cannot close; `dismiss()` clears it. Hover with
nothing playing is still peek; hover over a lone HUD/battery activity stays
at activity size.

## Verified

- `make test`: all targets pass, including four new `NotchControllerTests`
  covering open-on-hover/close-on-leave, no-media hover, media arriving under a
  parked cursor, and pinned-vs-hover-opened.
- Launched via `make dev`.

## Not verified

- On-screen feel of the hover open/close on the real notch (no hover-intent
  delay was added; opening is immediate on entering the island's region).

# HUD owns the island while live (2026-09-28)

## What changed

Screenshot from the user: with music playing, a volume press landed in the
two-activity layout (HUD + sticky media) — a 342 × 62 island with the glyph
stranded top-left, a 38 pt ear bar, "Sound" as a detail-row title and a second
bar under it. `NotchController.isHUDLeading` (was `isSoloHUD`) now makes a
LEADING HUD take `NotchMetrics.hud` regardless of what is queued behind it, and
the trailing ear's bar beats the overflow pip. One row, one bar, same shape as
the reference; the artwork returns when the HUD expires 1.5 s later.

## Verified

- `make test` passes; `aLeadingHUDActivityGetsTheHUDSizeWhateverIsBehindIt`
  and the re-pinned `hudSymbolAndBarAlongsideAnotherActivity…` render test
  cover HUD + media, HUD + overflow, and non-HUD pairs.
- Headless snapshot of HUD + media at rest (temporary test, deleted after use).

# System HUD replacement via media-key interception (2026-09-28)

## Why

The user's screenshot showed the stock pill ("MacBook Air Speakers" slider under
the Sound menu bar item) next to Ledge's own HUD. `OSDSuppressor` was already
on and did nothing: on this macOS the pill is `MenuBarAgent`'s, not
`OSDUIHelper`'s — see `docs/private-api-notes.md`.

## What was checked

- Window-list diff during a real volume key press identifies `MenuBarAgent` as
  the pill's owner, and shows it also owns the menu bar window (so it is not a
  SIGSTOP candidate).
- A scripted `set volume` (osascript) opens no new window — the pill is
  key-driven, so consuming the key is sufficient.
- `make test`: 202 tests pass; `MediaKeysTests` pins the `data1` decoding for
  all five keys (down/up/repeat), pass-through of other keys, sixteenth and
  sixty-fourth steps, grid snapping and clamping.
- `make dev` launches; on first launch without the grant the interceptor
  prompts for Accessibility and the menu row reads "System HUD — needs
  Accessibility …".

## Not verified here

- That the pill actually stays hidden once Accessibility is granted (needs the
  grant, which only the user can give, then a real key press). If it still
  shows, the next suspects are: the tap not being created (check the menu row),
  or the pill also listening to a value-change path for keys in particular.
- Fine steps (Shift+Option) and key auto-repeat on real hardware.
- The system's "play feedback when volume is changed" pop is NOT reproduced
  when Ledge handles the key.

# DeviceService (2026-09-28)

## What was checked

- `make test`: 211 tests pass; `DeviceServiceTests` pins baseline/duplicate
  suppression, the built-in route being announced by name, glyph/battery
  presentation, transport mapping, and battery name matching.
- `make dev` launches and stays up. The first attempt, with `IOBluetooth`,
  aborted under TCC ("attempted to access privacy-sensitive data without a
  usage description … NSBluetoothAlwaysUsageDescription") — three crash
  reports at 19:37–19:38; the Bluetooth observer was removed rather than
  taking on the prompt.

## Not verified

- A real route change on this machine: only the built-in output was present
  during the session, so no `outputChanged` event could be produced. Connect
  AirPods and expect their name + battery in the island for 3 s, then their
  glyph in the leading ear while the activity is live.

# Click-through fix (2026-09-28)

User report: "click notch, after that can't click anything". Cause and fix in
spec §5 (Hit testing, "Corrected 2026-09-28") and `NotchWindow.init`. Also
changed: a tap on a hover-opened panel no longer pins it
(`NotchController.tap()`).

## Verified

- `make test`: window default is mouse-transparent; `setAcceptsMouse` is
  reversible; `shouldAcceptMouse` truth table; `tap()` semantics.

## Not verified

- On screen: with the panel open, clicking a Superset tab under the canvas
  (screen x 415–1055, y 0–320) must land on Superset AND close a pinned panel.
  Hover, then click a panel button, must still work.

# Lock-screen presence (2026-09-28)

## Verified

- `make test`: lock → expanded with media (not pinned), unlock → back; lock
  with nothing playing → hidden, with a power activity → activity size; a
  pinned panel survives lock/unlock; the observer maps exactly the two
  `loginwindow` notifications; the display-only card renders inside the
  island and clear of the notch.

## Not verified

- On the real lock screen (⌃⌘Q with music playing): the card should appear
  hanging from the notch above the lock UI, without the five control
  buttons, with the scrubber still ticking; unlocking should collapse it to
  the compact island. Whether the display-only card is worth keeping at all
  is a judgement to make there — the spec sequenced this last so it can be
  cut without touching anything else.

## Lock-screen result (2026-09-28, later the same evening): not visible

Checked with a detached diagnostic polling `CGWindowListCopyWindowInfo` at 2 Hz
across four lock/unlock cycles, plus two throwaway apps showing labelled
panels, and the user looking at the real lock screen:

- The `com.apple.screenIsLocked` / `screenIsUnlocked` notifications fire;
  Ledge's window went to layer 2147483629 on every lock and back to 26 on
  unlock, and stayed `onscreen=true` throughout.
- `loginwindow`'s lock UI is two windows at layers 2001 (30000×30000 backdrop)
  and 2004 (1470×956 UI); `coreautha` at 1000. `CGShieldingWindowLevel()` is
  2147483628 here.
- During the lock transition every user window, Ledge's included, is scaled
  by ~0.91 about the screen centre for ~0.5 s; the lock windows are not. The
  lock screen is a separate composited layer, not a window level.
- Test panels at levels 1000, 2005, 3000 and shield+1, opaque and labelled,
  created BEFORE the lock: none visible on the lock screen (user report:
  "no one"). A second variant creating them 1.5 s AFTER the lock notification
  was armed but not run — the user parked the feature.
- Screenshots are not evidence here: Ledge's window reports
  `kCGWindowSharingState = 0` (excluded from capture) although nothing in
  the code sets `sharingType`; presumably a side effect of the non-activating
  panel configuration. Worth understanding before relying on screenshots for
  anything else.

Conclusion: parked. See spec §7.

# Device blip over music (2026-09-28)

User screenshot: "External Headphones" plugged in with music playing landed
in the two-slot layout (laptop glyph top-left, name under the hole, empty
slab). Now: `NotchController.isDeviceLeading` keeps the one-activity island;
with media present the artwork stays left and the device icon replaces the
visualizer/progress sliver on the right (`NotchRootView.deviceIcon`). The
jack's "External Headphones" gets the headphones glyph (name beats transport).

## Verified

- `make test`: controller size rule, glyph mapping, render test for the
  over-music case, headless snapshot of both ears.

## Not verified

- Live: plug/unplug headphones while playing — expect the right ear to swap
  to the headphones glyph for 3 s and back to the visualizer.

# Paused media ear (2026-09-28)

User asked what to replace the paused-state accent progress sliver with.
Answer: nothing new — the same visualizer bars, held at their resting pose
and dimmed to 40 %, so playing→paused stills one element instead of swapping
two. Progress lives in the panel's scrubber. `compactMediaProgress` removed.

# Power blip polish (2026-09-28)

Plugging in over music used to land in the two-slot layout with a grey dot.
`PowerEvent` now carries `symbolName` + `earLabel`; `ActivityRecord`/
`ActivityDisplay` carry `label`; `NotchController.hasLabelledEars` (HUD or
power) selects the `hud` island; the trailing value is right-aligned at the
label's weight, 10pt in, so its end lines up with the HUD's bar.

## Verified

- `make test`; snapshots of charging alone and over music.

## Not verified

- Live plug/unplug with music playing.

# Brightness HUD on charger plug/unplug (2026-09-28)

User report: the "Display" HUD fired when the charger went in or out. macOS
dims the display slightly on battery and brightens it back on AC; the 10Hz
value poll saw that as a change.

Fix, two layers (`HUDService.handleObservedBrightness`):
- tap active: brightness HUDs come only from `MediaKeyInterceptor`'s own
  writes (`onBrightnessApplied`, instant); observed changes only re-baseline.
  Control Center's slider therefore shows no HUD — as in macOS itself.
- tap inactive: an observed change must land on the sixteenths key grid
  (`HUDEventDeriver.isOnKeyGrid`) and is held 300 ms so a power event within
  3 s before/after (`notePowerSourceChanged`, called from
  `AppModel.handle(PowerEvent)`) vetoes it.

Not verified live; auto-brightness drift that happens to land on the grid
without the tap can still show a HUD.

## Power blip, second pass: no words

User: "remove the text". The power blip is back to the one-activity island
with the new glyphs (bolt/plug/battery fill) left and the percentage right;
the `label` plumbing added for it is removed again. HUD words stay.

# HUD, second pass: glyph + percentage (2026-09-28)

User: remove the text, replace the bar with a percentage. The volume/
brightness HUD is now the one-activity island — glyph (waves/rays lit by
level) left, "50%" right; mute is the slashed speaker + "0%". The wide HUD
island (`NotchMetrics.hud`, `hudEarWidth`), the ear label and the bar are
removed. HUD, power and device blips now share one ear vocabulary.

# Output switching in the panel (2026-09-29)

## Verified

- `make test`: glyph vocabulary shared with the route blip; the catalog on
  this machine lists ≥1 output with exactly one default and unique UIDs;
  re-setting the current default succeeds and an unknown UID is refused;
  controller stores outputs and forwards `selectOutput`; the picker row
  measures the same height as the control row and within the budget.
- Headless snapshot of the card with the picker open.

## Not verified

- Live: hover with music playing, tap the output glyph (fifth control), pick
  a device, hear the route change and see the device blip in the ears. Only
  one output was present on this machine during the session, so the button
  was dimmed here.

# Cleanup (2026-09-29)

Removed: `ArtworkAccent` (nothing drew with it once the compact bars went
white) and the two-slot layout (`NotchMetrics.twoActivities`, the
non-expanded detail row) — unreachable once HUD, power and device blips each
own the island alone. Three render tests that pinned the two-slot budget went
with it. `make test` passes.

# Motion polish (2026-09-29)

See spec §5 "Motion polish". Verified: `make test` (resting layouts unchanged;
`springDirectionIsDecidedByArea` pins the new rule). Not verifiable headlessly:
the live morph — ears travelling with the shape, blip-to-blip crossfades, the
card's fade on collapse. Judge on the notch.

# Shuffle state (2026-09-29)

`MediaPayload` now decodes the adapter's `shuffleMode`/`repeatMode` (MediaRemote
now-playing info keys the framework passes through when the source reports
them — Music/Spotify do, browsers do not). The panel's shuffle button shows
on (full glyph + dot), off (dim) or unavailable (dimmer, disabled). Repeat is
decoded but has no control since the output picker took its slot.

Not verified live: only a browser was playing during the session, so the
button was in its "unavailable" state here. Play something in Music, toggle
shuffle there, and the dot should follow within a diff.

# Media clickable (2026-09-29)

Clicking the card's artwork or title brings the playing app to the front
(`NotchIntent.openSource` → `AppModel.openSourceApp`: LaunchServices
`openApplication(at:)` by bundle id, pid `activate()` as fallback). The
visualizer is not part of the button. Not verified live.

# Music apps only (2026-09-29)

`MediaSourcePolicy` allow-lists music players by bundle id;
`AppModel.handle(_ payload:)` treats anything else as nothing playing (no
artwork, no panel, no position tick). Tests cover the list, case-insensitivity,
browsers, QuickTime, Zoom and a missing id. Live check: a browser video should
no longer appear in the island; Music/Spotify still should.

# Review fixes (2026-09-29)

A medium-depth review of the whole branch (11 finder passes, 15 findings)
after the day's work. Fixed, each with a test where the scenario could be
pinned:
- media: adapter callbacks carry a generation and are ignored after
  `stop()`/relaunch (no relaunch-after-stop race); `terminate()` disarms the
  pipe readers; `reapOrphans` is async like `probe`; an enveloped `null`
  payload clears state.
- keys: key-ups are consumed only when their key-down was
  (`MediaKeyUpTracker`); the tap dies with the interceptor (`deinit`).
- brightness targets the built-in display, not `CGMainDisplayID()`.
- volume observer and interceptor now both prefer VirtualMainVolume.
- battery: best (exact, then longest) product match, not first.
- menu: status rows in the order added; rows follow ANY service's status via a
  per-tick fingerprint; no retain cycle through the refresh closure.
- lock screen: the artwork button is disabled in display-only mode.
- artwork decoded once per change (`NotchController.mediaArtworkImage`).
Deferred: a shared process-supervisor type (one subprocess exists).

# Launch at login (2026-09-29)

`LoginItem.ensureRegistered()` (`SMAppService.mainApp.register()`) on every
launch; a menu row with a fix appears if approval is pending or the app moved.
Verified: build + tests; the registration itself and the system notice need
the real launch (`make dev` did it — check System Settings › General › Login
Items for "Ledge").

# Caps Lock blip (2026-09-29)

`CapsLockObserver` polls `CGEventSource.flagsState(.combinedSessionState)` at
10 Hz (no permission); `HUDEventDeriver.capsLockChanged` baselines then fires;
`HUDEvent.capsLock` presents as `capslock`/`capslock.fill` + "On"/"Off".
Tests cover the deriver and presentation. Live: press Caps Lock — a 1.5 s
blip, at most 100 ms after the key.

# Output picker as a list (2026-09-29)

User: "can make this expand bottom?" The chips row is replaced by a list
below the controls; the island grows by `outputRowHeight` per output while
open (`NotchController.isOutputPickerOpen` → `expanded(outputRows:)`) and
shrinks back after a pick or when the panel closes. Tests: metrics, controller
state, and a render test that the list fits the grown budget and adds one row
per output. Snapshot below the card's controls verified headlessly.

# Song-change caption and swipe to skip (2026-09-29)

From the reference app's demo video. Caption: `AppModel` sets
`presenter.setCaption("Title · Artist")` on every new title, clears it after
`NotchController.captionDuration` (3 s); the island is `NotchMetrics.captioned`
(342 × notch+26) only while media leads at activity size. Swipe:
`SwipeToSkipTracker` (pure, tested: once per gesture at 50 pt, momentum
ignored, finger direction wins over the scrolling setting) fed by a local
scroll-wheel monitor in `NotchPresenter`; on commit an intent, a haptic, and a
0.7 s skip glyph in the leading ear.

Verified: tests + a headless snapshot of the captioned island. Not verified
live: the spring down/up on a real track change; the swipe on the trackpad.

# Battery colour and the favourite star (2026-09-29)

Power blip glyph: green (`.positive`) while charging or charged, red
(`.warning`) when low, white otherwise — `ActivityTint` on the record, never
applied under the render-test hook. Favourite: `MusicFavorites` (Ledge target)
drives Music via `NSAppleScript` (`favorited of current track`), off the main
actor; never queries until the star has been tapped once (`favorites.synced`
in UserDefaults), so the Automation prompt only ever appears in context.
`NSAppleEventsUsageDescription` added to Info.plist.in. Spotify and the rest:
star disabled.

Not verified live: the prompt and the toggle against Music (only a browser
was playing here); the green/red glyphs on a real plug/unplug.

# Disc artwork and output glyph (2026-09-29)

User: replace the visualizer with the output icon, and make the cover spin
like a DVD. `SpinningArtwork` (circle clip, 12 s per turn while playing,
angle frozen on pause, resumed from there; still under Reduce Motion) wraps
both the ear's and the card's artwork. The equalizer bars are gone
(`AudioVisualizerBars` deleted with its tests); the compact trailing ear and
the card's top-right show the current output's glyph, dim when paused.
Not verified live: the spin and its pause/resume.

# Controls like Apple Music (2026-09-29)

`MusicControlButton`: glyph on a rounded highlight under the pointer, filled
highlight with a dark glyph while on, dimmed/disabled when unsupported.
Row: shuffle · previous · play/pause (28pt heavy) · next · repeat (cycles via
the adapter's toggle; `repeat.1` when one). Star beside the title; the output
glyph top-right is the picker's button (filled while the list is open).
Verified headlessly (snapshot); hover highlights need the pointer.

# Pop on blips (2026-09-29)

`NotchAnimation.pop` for growth from hidden (tests pin overshoot 5–12 % and
that only that case gets it); ear content inserts with scale 0.6 + blurReplace
on the pop spring; `ValueBump` keyframes (1 → 1.2 → 1) on the compact value
and the HUD glyph per change. Not observable headlessly — judge on the
notch: plug the charger, tap volume repeatedly.

# Blip pulse (2026-09-29)

User: "not working on plug" — with music showing, the island was already at
the blip's size, so the pop spring never ran. `NotchController.blipPulse`
counts blips that land without a shape change (and blip-to-blip
replacements); the view keyframes the whole island 1 → 1.05 → 1 from its top
edge on each change. Tested; judge on the notch with music playing.

# More motion (2026-09-29)

Emerge-from-notch ear transitions, rolling digits, symbol replace + bounce,
cover flip on track change, card cascade on appear (`revealed` state; starts
revealed under Reduce Motion and the render-test hook so single-frame renders
are the resting frame), caption slide-up, 7 % pulse. Judge on the notch.

# Output list polish (2026-09-29)

Rows: hover highlight, press dip (`ListRowButtonStyle`, no shrink), the
highlight and tick glide to the picked row (`matchedGeometryEffect`, optimistic
`pendingOutput` until CoreAudio confirms), the list holds ~0.5 s then closes;
rows cascade in. The list sits outside the spaced stack so it costs nothing
while closed (the budget tests caught the 7 pt spacing slot). Judge on the notch.

## Output list, second pass (2026-09-29): Control Center idiom

User: "the list looks ugly". No slab: each glyph in a 22 pt circle, the
selected one filled white with a dark glyph, names 12.5 pt regular, a tick
on the right; rows 30 pt. The filled disc is what glides on a pick.

## Charging glyph (2026-09-29)

User: swap the plug-in icon. Charging now shows the menu bar's own charging
glyph (battery with a bolt, green), held on AC the plug, fully charged the
plain full battery (green), low the empty battery (red). Headless renders of
all four states checked; a test pins that every power glyph resolves in SF
Symbols. Judge live: plug in below 100% — green battery with a bolt on the
left, percentage on the right.

The same renders showed "100…" in the trailing ear; that was the 3x render
scale rounding the numeric-text label a third of a point short (2x displays
were fine). The label is now sized to its ideal width, so no scale can clip it.

## Control interactions, toned down (2026-09-29)

User: "animation interactions for control is too much, less it a little bit".
Press dip 0.88/0.65 -> 0.93/0.80 on a 0.2 s critically damped spring (every
`PressableButtonStyle` control: transport row, star, output glyph, title);
play <-> pause swaps on a plain 0.2 s crossfade instead of a blur. Hover
highlight and the one-time row cascade unchanged. Judge live: click play and
next a few times — the control should dip, not flinch.

## Volume/brightness blip, toned down (2026-09-29)

User: the volume and brightness control animations were too much. Per key
press the speaker/sun glyph no longer bounces (its waves/rays still light up
with the level); the percentage still rolls, with a 10% tick instead of 20%.
The blip's arrival (island pop, ear emerge) and the island pulse on a new
blip are unchanged. Judge live: hold volume up — one quiet motion per step.

## Hover intent (2026-09-29)

The cursor must rest on the island 0.2 s before the panel opens or the notch
peeks; leaving closes at once. `HoverIntentTracker` is pure and unit tested;
the presenter arms a one-shot timer for the exact dwell end so a still cursor
still opens on time. Mouse acceptance follows the raw pointer position, so a
click during the dwell still pins. Judge live: sweep the cursor up through the
notch to the menu bar — nothing should move; rest on it — the card opens after
a beat; click a blip straight away — it pins.

## Player quits (2026-09-29)

User asked what to show when the music app closes: nothing — back to idle.
Already the case for a hover-opened card; a PINNED card used to outlive the
player as an empty slab. `setMedia(nil)` now releases the pin when the card
departs (nil-to-nil leaves a blip's own pin alone). Judge live: play, click
the notch to pin, quit the player — the island collapses at once; with a
volume blip live it lands on the blip.

## Blip click (2026-09-29)

Clicking a volume/battery/device blip used to pin open the pre-card
title-and-bar layout at full card size. The expanded panel is now only ever the
now-playing card: `click()`/`tap()` need media, the legacy list is deleted.
Judge live: with nothing playing, press volume and click the blip — nothing
opens; with music playing, click the blip — the card pins as before.

## Calendar reminders (2026-09-29)

Meeting blip: calendar glyph + "5m"/"Now", "Title · 10:00" in the caption for
8 s, click joins the call or opens Calendar. Link detection and the reminder
policy are unit tested; EventKit is not. Judge live: allow Calendars at first
launch; create an event 6 min out with a Meet link in the location — at 5 min
the blip appears; click it — the browser opens the link; at the start, "Now".
With music playing the blip leads the ears and the cover returns after 8 s.
Decline the permission once to see the menu row "Calendar needs Calendars
access…".
