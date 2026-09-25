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

## Finding: a single activity cannot show its title text

While implementing Step 11, tracing the actual geometry turned up something
worth flagging before, not after, a human sits down to run check 1 and 2.

`NotchMetrics.oneActivity.height` is pinned (Task 3, `NotchShapeTests
.specifiedTargetGeometryIsHonoured`) to exactly `notchRect.height` — per spec
§6, "One activity is minimal and notch-height." `NotchRootView.islandContent`
(Task 6, unmodified by Task 8) only renders `detailRow` when
`parameters.height > notch.height + 8`. Since `oneActivity.height` **equals**
`notch.height`, that condition is `x > x + 8`, which is false for any `x` —
not a near-miss depending on hardware measurements, a structural
impossibility. `AppModel` only ever feeds one `.power` record at a time, so
`queue.visible.count == 1` for the common lone-charging-event case, which
drives `NotchController` to exactly the `oneActivity` size.

Net effect: plugging in or unplugging the charger with nothing else active
will grow the island to the correct `~255 × 32pt` size and show the leading-ear
dot (`activityCount > 0`), but **the title text itself
(`"Charging · NN% · NN min to full"`) will not be visible** — there is no
vertical room below the hole at that size, by design, regardless of this
task's `detailRow`/`ContentFade` wiring. Text only appears once a second
activity is concurrently queued (`twoActivities`, 62pt tall, has room).

This is not something Task 8 fixes: `NotchMetrics`'s resting sizes and
`NotchController`'s state→size mapping are Tasks 3 and 2's reviewed,
pinned-by-test surface, out of this task's file list, and spec §6 reads as a
deliberate choice (1 activity = compact ears-only, glyph-like content — the
spec's own example is media's "artwork; waveform", which doesn't exist yet
either). Changing either would mean breaking or rewriting currently-passing,
previously-reviewed tests on my own authority, which this task does not ask
for. Flagging it here instead: **checks 1 and 2 below, even if a human ran
them today, would show the correctly-sized, correctly-timed island with no
readable text — only the dot** — until a second simultaneous activity exists
(HUD or media, both future work). This is a real product question (what,
if anything, a lone power/HUD/notification/device activity should show in
the ears, absent artwork) rather than a Task 8 implementation bug, but it
means check 1/2's literal wording will not be satisfied by this diff.

## The six checks

1. **Plug in the charger → island morphs out showing `Charging · NN% · NN min
   to full`, then collapses after ~3s.**
   Not eye-verified (no charger to physically toggle in this session, no
   screenshot). **Additionally, per the finding above, the text portion of
   this check is predicted not to pass even under human observation** for a
   lone charging event — only the sizing/motion/dot would show. Supporting
   evidence for the parts that should work: `PowerEventDeriverTests
   .plugInIsReported` and `.eventTitlesAreHumanReadable` pin the event and its
   exact title string; `ActivityQueueTests` covers the 3s TTL
   (`ActivityKind.power.defaultTTL == 3`) and its expiry; `NotchControllerTests
   .activityShowsWithoutHoverAndRestsOnActivityState` pins hidden→activity on
   a nonzero count. None of this substitutes for watching it happen.

2. **Unplug → island shows `On battery · NN%`, then collapses.**
   Not eye-verified, same constraints as (1), same text-visibility caveat
   from the finding above. Supporting evidence: `PowerEventDeriverTests
   .unplugIsReported`.

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
all-reasoned baseline. The geometry finding above means a human running
check 1 or 2 today should expect the island to size and time correctly but
**not** show readable text for a lone power activity; that is a traced,
reasoned prediction, not a guess, and is a strong reason to route this
specific point back to review rather than to further "unverified" hedging.
