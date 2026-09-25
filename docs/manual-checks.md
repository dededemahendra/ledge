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
